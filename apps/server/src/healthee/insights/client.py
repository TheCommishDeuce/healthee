"""OpenRouter chat client (OpenAI-compatible API) — the ONE LLM transport.

OpenRouter exposes Anthropic / OpenAI / Google models behind a single
OpenAI-compatible endpoint; we point the ``openai`` SDK at its base URL. Every
LLM surface reaches this through the grounded-ask choke point (``grounded.py``),
never directly (standards §2: "LLM access only via the grounded-ask choke point").

The API key is read once from ``core.config`` and never logged (standards
§Errors: no secret ever reaches a log line). Neither is the MODEL ID: it is kept out of
git on purpose (ids resolve from ``DEFAULT_MODEL`` / ``COACH_MODEL``) and a log line that
prints it undoes that at runtime, so every diagnostic here names the TIER instead
(:func:`tier_of`). Tests inject a stub implementing the ``LLMClient`` protocol, so no
network call happens under pytest.
"""

from __future__ import annotations

import time
from collections.abc import Callable
from dataclasses import dataclass
from functools import lru_cache
from types import SimpleNamespace
from typing import Any, Protocol

from healthee.core.config import get_settings
from healthee.core.llm_endpoint import is_openrouter
from healthee.core.logging import get_logger
from healthee.insights import client_stream, transport_health

log = get_logger(__name__)


class LLMDeadlineExceeded(TimeoutError):  # noqa: N818 — named to match `transport_health`'s lookup
    """One completion ran past `Settings.llm_deadline_s` of WALL-CLOCK time.

    A `TimeoutError`, the family `openai.APITimeoutError` is diagnosed as too — every
    handler here catches broad `Exception` at its supervised boundary (`jobs/chain.py`,
    `api/routers/coach.py`) rather than the SDK's own class, so nothing had to change
    there; `transport_health.classify` names it by class name for the same reason.
    Raised by `client_stream.accumulate`/`watchdog_accumulate` as an injected
    `deadline_exc`, not imported, so that module never has to import this one back.
    """


# Model ids live in settings (env: DEFAULT_MODEL / COACH_MODEL), NOT hardcoded here —
# the source never reveals which models we run; they're resolved per call. Per-surface
# tiers: default_model = the cheap, high-volume tier (recs/insights/notable/daily-
# action); coach_model = a stronger tier for the interactive coach (low volume, high
# engagement, where answer quality is most felt). Low temperature: health data wants
# factual, reproducible output, not creative tails. See docs/PRICING.md §6 / task #23.
DEFAULT_TEMPERATURE = 0.1
DEFAULT_TOP_P = 0.9
# A CEILING, not a spend: output is billed on tokens actually produced, so raising this
# costs nothing until an answer genuinely needs the room.
#
# 2000 was measured to be too small, and the old comment ("headroom so verbose/reasoning
# models aren't truncated") was wrong for the tier we actually run. A REASONING model
# spends its thinking out of this SAME budget: measured on the coach tier, one ordinary
# answer used 1068 completion tokens of which **892 were reasoning** — leaving ~180 for
# the visible reply. Longer answers then stopped mid-citation, the validator's truncation
# guard correctly refused them, and the coach shipped the honest fallback to ordinary
# questions. The failure read as "can't ground that" when the real cause was "ran out of
# room to finish the sentence".
DEFAULT_MAX_TOKENS = 10_000


def default_model() -> str:
    """The cheap, high-volume model tier (batch surfaces: recs/insights/notable/action)."""
    return get_settings().default_model


def coach_model() -> str:
    """The stronger model tier for the interactive coach (low volume, quality-first)."""
    return get_settings().coach_model


def tier_of(model: str) -> str:
    """Which configured TIER an id is — the diagnostic value a log line may carry.

    Standing owner constraint: the model we run must not be discoverable. It is kept out
    of git by design (ids resolve from ``DEFAULT_MODEL`` / ``COACH_MODEL``), and then the
    runtime logged it on every completion — the same category of leak as a bot token in a
    request URL, differing only in blast radius. Operators need to know *which surface's
    model* answered, not which model: "the coach tier is slow" and "the default tier is
    slow" are the two different diagnoses, and both are legible without the id.

    ``unconfigured`` is deliberately distinguishable from the two known tiers — an id
    that matches neither setting is a real operational fact (a caller passing an explicit
    ``model=``, or an env that changed under a running process) and hiding it would trade
    one silence for another.
    """
    settings = get_settings()
    if not model:
        return "unset"
    if model == settings.coach_model:
        return "coach"
    if model == settings.default_model:
        return "default"
    return "unconfigured"


@dataclass(frozen=True)
class Usage:
    """Provider-COUNTED tokens for one completion — the measured number, not an estimate.

    ``reasoning_tokens`` is carried separately because it is the field that made a live
    bug unreadable: a reasoning model spends its thinking out of the same ``max_tokens``
    budget as its visible answer, so 892 of 1068 completion tokens were invisible and the
    coach's answers stopped mid-citation (VERIFICATION_2026_08_01 §6). That was diagnosed
    by instrumenting this call by hand; keeping the number costs nothing and makes the
    diagnosis repeatable — including by the grounding eval harness, which reads it
    through an injected client to report what an answer actually cost.

    ``cached_prompt_tokens`` is the same kind of field for the other half of the bill.
    The coach's system turn — persona, the owner's context and the evidence block — is
    built ONCE per request and re-sent unchanged on every round, ~40,000 tokens of it.
    Whether the provider serves that from its cache is the difference between a round
    that re-reads the corpus and one that does not, and it decides which lever makes
    the coach faster. Nothing recorded it, so "is the prompt the problem?" could only
    be answered by guessing.

    ``cost`` is OpenRouter's own BILLED dollar figure for this completion — not the
    published-rate estimate `tests/grounding_eval/report.py` computes from token counts,
    which is wrong whenever a provider's actual price differs from the rate table (or
    the table is stale). Requesting it costs nothing extra; ``None`` means the provider
    didn't report one, same "unknown, not zero" rule as every other field here.
    """

    prompt_tokens: int = 0
    completion_tokens: int = 0
    reasoning_tokens: int = 0
    cached_prompt_tokens: int = 0
    cost: float | None = None


@dataclass(frozen=True)
class ChatResponse:
    """A single assistant turn: its text plus any tool calls it requested.

    ``tool_calls`` is a list of ``client_stream.ToolCall`` (or None) — reassembled from
    the streamed deltas, but carrying the same ``.id`` / ``.function.name`` /
    ``.function.arguments`` shape the coach tool-loop (WP5b) always read off a
    non-streamed response, so nothing downstream of this type changed. Insight
    surfaces use only ``text``.

    ``usage`` is None when the provider (or a test stub) reported none — "we don't know"
    and "zero tokens" are different states and stay distinguishable.
    """

    text: str
    tool_calls: list[Any] | None = None
    usage: Usage | None = None


class LLMClient(Protocol):
    """The one method the choke point needs. A stub implements this in tests."""

    def complete(
        self,
        messages: list[dict],
        *,
        tools: list[dict] | None = None,
        model: str | None = None,
        response_format: dict | None = None,
    ) -> ChatResponse: ...


class OpenRouterClient:
    """Real transport: the ``openai`` SDK pointed at OpenRouter. Constructed lazily
    so importing this module never requires a key or touches the network."""

    def __init__(self) -> None:
        self._sdk: Any | None = None

    def _client(self) -> Any:
        """The SDK client, built once — with OUR limits, never the SDK's defaults.

        `timeout`/`max_retries` are passed explicitly because omitting them inherits
        `Timeout(read=600)` and `max_retries=2` — 30 minutes of hang for one stuck
        call, which the single-threaded scheduler tick pays for EVERY later owner
        (see `core.config.llm_timeout_s` for the numbers and why).
        """
        if self._sdk is None:
            settings = get_settings()
            if not settings.openrouter_api_key:
                raise RuntimeError("OPENROUTER_API_KEY is unset — LLM features are unavailable")
            from openai import OpenAI  # local import: heavy SDK, only when a call happens

            self._sdk = OpenAI(
                api_key=settings.openrouter_api_key,
                base_url=settings.llm_base_url,
                timeout=settings.llm_timeout_s,
                max_retries=settings.llm_max_retries,
            )
        return self._sdk

    def complete(
        self,
        messages: list[dict],
        *,
        tools: list[dict] | None = None,
        model: str | None = None,
        response_format: dict | None = None,
        reasoning: bool | None = None,
        on_text: Callable[[str], None] | None = None,
    ) -> ChatResponse:
        """One completion, STREAMED, assembled back into one assistant turn.

        ``response_format`` (e.g. ``{"type": "json_object"}``) is forwarded to the
        SDK when supplied — the grounded-ask choke point sets it for JSON surfaces
        (recs) so the model returns a parseable object, not fenced prose. Default
        ``None`` leaves the request unchanged (prose path is byte-identical).

        ``reasoning=False`` asks the provider NOT to spend thinking tokens on this call
        (OpenRouter's ``reasoning: {enabled: false}``; ``Settings.coach_reasoning`` says
        why). ``None`` sends nothing, so the model's own default stands — the request is
        byte-identical to before the parameter existed. ``True`` is deliberately also
        "send nothing": the shipped behaviour IS the model default, and asking for
        thinking explicitly would change the request for models that never think.
        ``on_text`` (the coach's live draft) is forwarded the same way — only when set,
        never part of ``LLMClient``.

        Every call is made with ``stream=True``: a non-streaming call's ``httpx`` read
        timeout (``llm_timeout_s``) only fires when the socket goes silent, and
        OpenRouter's keepalive bytes during a long generation mean it never is —
        measured, one coach question ran 594 s across 3 calls under a supposed 60 s
        cap. Streaming lets ``client_stream.watchdog_accumulate`` enforce a WALL-CLOCK
        deadline (``llm_deadline_s``) instead: a per-chunk check plus a real timer
        backstop for the phase before the first chunk, where OpenRouter's own
        keepalives never reach the SDK as a chunk at all (module docstring).

        Errors propagate (the endpoint degrades to an honest error body) — never
        swallowed. Two exceptions carry a timeout: ``openai.APITimeoutError``
        (``llm_timeout_s``, a dead socket) and :class:`LLMDeadlineExceeded`
        (``llm_deadline_s``, a live-but-slow one), landing on the chain's supervisor
        (logged + Telegram-notified) rather than quietly becoming an empty answer — a
        blank card and a broken transport must stay distinguishable (standards, errors).

        Every attempt is recorded in ``insights.transport_health``, which makes a dead
        AI layer VISIBLE without any probe paying for a completion — `_client()` raising
        for an unset key is a *configuration* fact, not a transport one, uncounted here.
        """
        settings = get_settings()
        model = model or settings.default_model  # resolve the env-configured default
        kwargs: dict[str, Any] = {
            "model": model,
            "messages": messages,
            "temperature": DEFAULT_TEMPERATURE,
            "top_p": DEFAULT_TOP_P,
            "max_tokens": DEFAULT_MAX_TOKENS,
            "extra_headers": {"X-Title": "healthee"},
            "stream": True,
            "stream_options": {"include_usage": True},
        }
        if tools:
            kwargs["tools"] = tools
        if response_format is not None:
            kwargs["response_format"] = response_format
        # `usage: {"include": true}` is OpenRouter's own extension for the provider-
        # BILLED `cost` field (Usage.cost); `reasoning`/`provider` stay opt-in. None of
        # the three is sent to another endpoint (`core.llm_endpoint`).
        if is_openrouter(settings.llm_base_url):
            extra_body: dict[str, Any] = {"usage": {"include": True}}
            if reasoning is False:
                extra_body["reasoning"] = {"enabled": False}
            provider = _provider_routing(model)
            if provider is not None:
                extra_body["provider"] = provider
            kwargs["extra_body"] = extra_body
        sdk = self._client()
        started = time.monotonic()
        deadline_s = settings.llm_deadline_s
        try:
            stream = sdk.chat.completions.create(**kwargs)
            acc = client_stream.watchdog_accumulate(
                stream, deadline_s=deadline_s, deadline_exc=LLMDeadlineExceeded, on_text=on_text
            )
        except Exception as exc:  # recorded on the health surface, then re-raised untouched
            transport_health.record_failure(exc)
            raise
        elapsed = time.monotonic() - started
        transport_health.record_success()
        _warn_if_truncated(SimpleNamespace(finish_reason=acc.finish_reason), model)
        usage = _usage(SimpleNamespace(usage=acc.usage_raw))
        # tier, never the id: the model we run must not be discoverable, and a log line
        # is a place it reaches operators, log shippers and anyone with read access.
        #
        # ⛔ **The duration and the token split are the point.** Without them "the coach
        # is slow" could only be answered by subtracting timestamps of consecutive log
        # lines and guessing which half was to blame — which is how a 46,000-token prompt
        # got named as the cause of a ~100 s round before anybody had checked whether the
        # time was going into INPUT at all. This tier is a reasoning model and its
        # thinking is DECODE, generated a token at a time; prompt size and reasoning
        # length are different problems with different fixes, and one line here tells
        # them apart. Counts and seconds only — never a prompt, never an answer.
        log.info(
            "llm completion: tier=%s tools=%d in %.1fs "
            "(prompt=%d cached=%d completion=%d reasoning=%d cost=%s)",
            tier_of(model),
            len(tools or []),
            elapsed,
            usage.prompt_tokens if usage else -1,
            usage.cached_prompt_tokens if usage else -1,
            usage.completion_tokens if usage else -1,
            usage.reasoning_tokens if usage else -1,
            f"${usage.cost:.4f}" if usage and usage.cost is not None else "n/a",
        )
        return ChatResponse(
            text=acc.text,
            tool_calls=acc.tool_calls or None,
            usage=usage,
        )


def _provider_routing(model: str) -> dict[str, Any] | None:
    """The ordered provider preference for the COACH tier, or None to say nothing.

    Scoped by tier rather than applied globally, and that is the whole safety of it: the
    configured tags serve the coach model at a chosen quantization, while the default
    tier is a different model most of them do not host. Sent on every call, a preference
    meant for the coach would route the nightly chain to providers that cannot answer it.

    ``allow_fallbacks`` is True and is not configurable. The owner asked for these
    providers "then fallback if none of them works", which is exactly this flag: the
    order is walked first, and anything else that serves the model answers rather than
    the request failing. A hard restriction is a different feature and would need its own
    argument — a coach that 503s because four named providers were busy is a worse
    outcome than an answer from a fifth.
    """
    if tier_of(model) != "coach":
        return None
    settings = get_settings()
    order = [tag.strip() for tag in settings.llm_provider_order.split(",") if tag.strip()]
    if order:
        return {"order": order, "allow_fallbacks": True}
    # No order: sort instead. OpenRouter treats the two as alternatives (either one
    # switches off its price-weighted balancing), so an order, when set, wins.
    return {"sort": settings.llm_provider_sort} if settings.llm_provider_sort else None


def _warn_if_truncated(choice: Any, model: str) -> None:
    """Say so when the API stopped because it ran out of room.

    We used to drop the whole response object and keep only ``.message``, so the ONLY
    signal left was the validator noticing an unclosed '[' downstream — a string
    heuristic standing in for a fact the transport already knew. A truncated answer is a
    transport problem wearing a grounding problem's clothes, and it cost a live debugging
    session to tell them apart. Log it loudly; the validator still refuses the text, but
    now the cause is in the logs at the point it happened rather than inferred three
    layers up.

    ``getattr`` with a default, not ``choice.finish_reason``: not every provider (or test
    stub) sets it, and a missing stop-reason must not turn a good answer into an
    AttributeError. Absent ⇒ we simply don't know, which is not "truncated".
    """
    if getattr(choice, "finish_reason", None) != "length":
        return
    log.warning(
        "llm answer TRUNCATED by max_tokens=%d (tier=%s) — the answer stopped "
        "mid-sentence; raise DEFAULT_MAX_TOKENS rather than reading this as a "
        "grounding failure",
        DEFAULT_MAX_TOKENS,
        tier_of(model),
    )


def _usage(raw: Any) -> Usage | None:
    """The provider's own token counts, or None when it reported none.

    Read defensively with ``getattr``: not every provider behind OpenRouter returns a
    ``usage`` block, and none of them is required to break down reasoning tokens. A
    missing count must never turn a good answer into an AttributeError — a cost figure
    is diagnostic, an answer is the product.
    """
    usage = getattr(raw, "usage", None)
    if usage is None:
        return None
    details = getattr(usage, "completion_tokens_details", None)
    prompt_details = getattr(usage, "prompt_tokens_details", None)
    return Usage(
        prompt_tokens=getattr(usage, "prompt_tokens", 0) or 0,
        completion_tokens=getattr(usage, "completion_tokens", 0) or 0,
        reasoning_tokens=getattr(details, "reasoning_tokens", 0) or 0,
        # Read as defensively as the rest: providers spell this differently and some
        # omit it. A zero here means "not reported", which is NOT the same as "no cache
        # hit" — the log line says the number, and reading it as a claim either way
        # would be exactly the guess this field exists to replace.
        cached_prompt_tokens=getattr(prompt_details, "cached_tokens", 0) or 0,
        # Only present when the request carries `usage: {"include": true}` (sent on
        # every call below). `or None`, not `or 0`: a provider that billed nothing is a
        # real (rare) fact, distinct from one that never told us at all.
        cost=getattr(usage, "cost", None),
    )


@lru_cache(maxsize=1)
def get_client() -> OpenRouterClient:
    """Process-wide real client. ``grounded_ask`` defaults to this; tests pass a stub."""
    return OpenRouterClient()
