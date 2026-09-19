"""The AI coach endpoint — POST /api/coach (Bearer-auth).

Thin (standards §2): authorize + gate → validate the body → call ``run_coach`` →
shape the reply. ``CoachUser`` is the premium gate (``api.gate``): a non-premium owner
gets 402 before a single token is spent, which is the point — the coach is the most
expensive surface in the product ($0.179 a question, PRICING.md §3.1), and this is the
only place its entitlement is checked (the coach's own tools deliberately do not
re-check it). It is also the only surface that is capped *for a paying owner*.

## What one counted coach QUESTION is

``PRICING.md`` §0 includes **20 coach questions per rolling 30 days** in a subscription,
and the unit is this **request** — one turn — not one LLM call. A tool-calling turn can
make up to 22 (``insights.coach.GATHERING_ROUNDS`` + the reserved validation attempts);
metering calls would charge a curious question twenty times and an incurious one once,
which is not a promise anybody could read off the pricing page. That separation is what
lets the gathering allowance be generous: the ledger is keyed to the question, so a
question that genuinely needs the data costs the owner exactly what a trivial one does.

The gate charges the turn; this handler refunds it when the turn produced no answer, and
the cases are exactly the ones the coach itself already names: ``refused`` (classified
out of scope before any model ran — no tokens, no answer), ``validated=False`` (the
honest fallback shipped, which is the product working correctly and still not what the
owner asked for), and ``answered=False`` (the request carried no owner turn, so the reply
is the canned greeting). A transport failure refunds too, on its way out. **A slot is
never billed for an answer we did not deliver** — that is the honesty contract applied to
the meter, and it is why the refund is four branches rather than one convenient one.

The greeting branch was missing, and the omission was not academic. ``CoachResult``'s
defaults are ``refused=False, validated=True``, so ``{"messages": []}`` — or a body with
only assistant turns, or one empty-string user turn — matched none of the other three and
charged one of the owner's twenty for a fixed sentence no model wrote. This app never
sends such a body (``coach_controller.ask`` returns early on empty text and always
appends the owner's question first), but a direct request is exactly the threat model
``tests/premium/test_ai_gate.py`` was written against.


All grounding, tool-calling, refusal-gating and blocking validation live in
``healthee.insights.coach``, which is one of the two entry points into the shared §3
choke point (``insights.pipeline``); nothing LLM-shaped happens in this router.
"""

from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from healthee.api import coach_stream, gate
from healthee.api.gate import CoachUser
from healthee.insights import coach_thread
from healthee.insights.coach import coach_reply_payload, run_coach

router = APIRouter(tags=["coach"])


# ── The bounds on the conversation the client sends ──────────────────────────
#
# ``insights.coach.py`` already bounds the history it USES to the last 12 well-formed
# turns, so the turn COUNT was bounded and the per-turn SIZE was not — the body was
# limited in practice only by nginx's ``client_max_body_size``. That is the same
# denial-of-wallet shape ``read/logs.py`` names for manual-entry notes, against the one
# surface that is measured at $0.179 a question.
#
# ``_MAX_TURNS`` is comfortably above the 12 the pipeline reads, so a client sending its
# full visible thread is never refused for length; ``_MAX_CONTENT`` is ~700 words, which
# is far more than anyone types into a chat box and fatal to a prompt-sized paste.
_MAX_TURNS = 40
_MAX_CONTENT = 4000
_MAX_ROLE = 32


class CoachMessage(BaseModel):
    """One conversation turn from the client."""

    role: str = Field(max_length=_MAX_ROLE)
    content: str = Field(max_length=_MAX_CONTENT)


class CoachRequest(BaseModel):
    """POST body: the running conversation (system turns are ignored server-side).

    ``topic`` is optional and says WHICH SCREEN the owner opened the coach from — the
    metric whose trend they were reading, the session they were reviewing, the finding
    they wanted talked through. Five app surfaces link in and two of them are about
    something specific; without this the server never learned what, because the app can
    only put the subject in the first user turn and grounding was then whatever the model
    inferred from that prose. With it, ``insights.coach_thread.retrieval_key`` ranks the
    context and the evidence on the subject as well as the words.

    ⛔ **A topic is context, not evidence**, and none of the honesty layer steps aside
    for it: it is screened by the pre-LLM refusal gate exactly like an owner's turn, it
    is rendered inside a fence that tells the model it is a label rather than a finding,
    and the answer that follows faces the same validator, guardrails and personal-claims
    gate as any other. It is bounded here — the boundary standards section 2 asks for — at
    ``coach_thread.TOPIC_MAX_CHARS``; the app's own topics are one short sentence.
    """

    messages: list[CoachMessage] = Field(default_factory=list, max_length=_MAX_TURNS)
    topic: str | None = Field(default=None, max_length=coach_thread.TOPIC_MAX_CHARS)


@router.post("/api/coach")
def post_coach(request: Request, user: CoachUser, req: CoachRequest) -> dict:
    """Answer the conversation as the grounded coach (validated or honest fallback)."""
    try:
        result = run_coach(
            [m.model_dump() for m in req.messages],
            user.id,
            user.timezone,
            topic=req.topic,
        )
    except Exception:
        # Not a swallow — it is re-raised unchanged for the error handler to log and
        # report. The refund is the only thing that must happen before it leaves, because
        # the gate has already charged one of the owner's included questions.
        gate.refund_ai_use(request, user)
        raise
    if result.refused or not result.validated or not result.answered:
        gate.refund_ai_use(request, user)
    return coach_reply_payload(result)


@router.post("/api/coach/stream")
def post_coach_stream(request: Request, user: CoachUser, req: CoachRequest) -> StreamingResponse:
    """The streaming twin of ``/api/coach`` — live progress, then the validated answer.

    Same body, same gate (``CoachUser``): a request that fails BEFORE any model call —
    401 unauthenticated, 402 not entitled or the cap spent, 422 a malformed body, 429
    rate-limited — behaves identically to ``/api/coach``, because the gate runs first on
    both routes and nothing below it has started. Everything that happens once the
    response has begun (raw model tokens NEVER included — INTELLIGENCE §3: unvalidated
    text does not ship, streamed or not) lives in ``api.coach_stream``, including the
    refund: it runs inside the worker, before the terminal event, so it is not raced by
    a client reading the stream. A client that disconnects mid-turn does not stop it —
    the model call is already paid for, so it runs to completion and the same refund
    rule applies to whatever it produced.
    """
    return coach_stream.stream_response(
        request, user, [m.model_dump() for m in req.messages], req.topic
    )
