"""Last-known LLM transport status, derived from REAL traffic — never from a probe.

## Why this exists

On 2026-08-01 the OpenRouter account hit its ceiling. Every LLM call 402'd — the coach,
every insight card, the whole nightly chain — and ``/healthz`` returned
``{"status":"ok","db":"ok"}`` for the duration. Nobody found out from monitoring; an
eval run happened to die and that is how it surfaced. It is the same shape as every
earlier incident here: *the liveness probe was green in every broken state.*

The fix has to answer "is the AI layer alive?" **without spending money to ask**. A
health check that makes a completion call per probe is a worse bug than the one it
detects — it bills the account on a timer, and under an outage it bills it to learn
something the failing traffic already knew. So this module does not call anything. It
is a passive record: :func:`record_success` / :func:`record_failure` are called by the
ONE transport (``insights.client.OpenRouterClient.complete``) around the SDK call it
was already making, and everything downstream reads the accumulated verdict.

The balance half of the picture — *how close to zero are we* — is
``insights.credits``, which does make a call, to a **free** endpoint that spends no
tokens. The two are complementary and deliberately separate: this one says the
transport is failing NOW, that one says it is ABOUT to.

## One blip is not an outage

A single 402/429/timeout is noise: providers stutter, a retry usually fixes it, and an
alert on the first error trains its reader to ignore it. So the record counts
CONSECUTIVE failures and only calls it :data:`DOWN` at :data:`OUTAGE_THRESHOLD`. A
success anywhere resets the streak to zero, which is the property that makes this a
statement about the present rather than a lifetime error count.

The streak counts failures of ANY kind while ``last_error_kind`` names only the most
recent one, and that asymmetry is on purpose: the streak answers "has anything got
through?", the kind answers "what is wrong?". A timeout followed by two 402s is three
consecutive failures whose diagnosis is *credit*.

## Four states, and ``unknown`` is not ``ok``

A process that has not made an LLM call yet knows NOTHING about the transport, and
reporting that as healthy is the exact conversion this whole feature exists to prevent:
"we don't know" turned into "we're fine". A monitoring feature that fails quiet is
worse than none. So the initial state is :data:`UNKNOWN` and it only becomes
:data:`OK` when a real call has actually succeeded.

## What is recorded — and what is deliberately NOT

Only the failure's KIND and its HTTP status code. No provider message text, ever.
Standing owner constraint: neither the API key nor the model id may reach a log line
(``client.tier_of`` exists for exactly this reason), and a provider error body is free
text we do not control — a 400 for a bad model id contains that id verbatim. The kind
plus the status code is the whole diagnosis an operator needs, and it cannot carry a
secret. The full exception is not lost: it propagates to the caller untouched, and the
chain's supervisor logs it (standards §Errors — reported, never swallowed).

## The record is PER PROCESS, and that is stated rather than hidden

The api and the scheduler are separate containers with separate memory, so each knows
only what its own traffic hit. A 402 that only the coach has seen is invisible to the
scheduler's copy. That gap is covered by ``insights.credits``, whose reading is a
property of the ACCOUNT and therefore identical in both — which is why the scheduler's
watcher (``jobs.llm_watch``) alerts on both signals rather than this one alone.
"""

from __future__ import annotations

import threading
from dataclasses import dataclass, replace
from datetime import UTC, datetime

from healthee.core.logging import get_logger

log = get_logger(__name__)

# ── the four states ───────────────────────────────────────────────────────────
# `UNKNOWN` is first-class: no call has been made, so nothing is known. It must never
# be collapsed into `OK` (module docstring).
UNKNOWN = "unknown"
OK = "ok"
DEGRADED = "degraded"
DOWN = "down"

# ── failure kinds — the diagnosis, carried instead of the provider's message ──
CREDIT = "credit"  # 402: the account is out of money. Will not self-heal.
AUTH = "auth"  # 401/403: the key is wrong, revoked or unprivileged. Will not self-heal.
RATE_LIMIT = "rate_limit"  # 429: too fast, or a provider-side quota. Usually transient.
TIMEOUT = "timeout"  # our own `llm_timeout_s` fired.
NETWORK = "network"  # the connection never got there.
HTTP = "http"  # some other non-2xx.
UNCLASSIFIED = "unclassified"  # anything else — named, never silently bucketed as fine.

# How many consecutive failures make an outage rather than a blip. Three, because the
# SDK is already configured for one retry (`llm_max_retries`), so three FAILED calls is
# up to six attempts — well past "the provider stuttered" — while still firing inside
# one scheduler tick's worth of chain steps rather than a day later.
OUTAGE_THRESHOLD = 3

# HTTP status → kind. Only statuses whose meaning is unambiguous appear here; anything
# else is `HTTP` plus its code, which is honest about how much we actually know.
_STATUS_KINDS: dict[int, str] = {401: AUTH, 402: CREDIT, 403: AUTH, 429: RATE_LIMIT}

# Exception class name → kind, for the failures that never reached a status code.
# Matched by NAME rather than by `isinstance`, because importing `openai` here would
# undo the deliberate laziness in `client._client` (a heavy SDK imported only when a
# call actually happens) for no gain — a name table cannot fail open: an unrecognised
# class becomes `UNCLASSIFIED`, which still counts as a failure and still trips the
# streak. The classification only ever changes the WORDS in the alert.
_NAME_KINDS: dict[str, str] = {
    "APITimeoutError": TIMEOUT,
    "APIConnectionTimeoutError": TIMEOUT,
    "APIConnectionError": NETWORK,
    "ConnectError": NETWORK,
    "ConnectTimeout": TIMEOUT,
    "ReadTimeout": TIMEOUT,
    # `insights.client.LLMDeadlineExceeded` — our own WALL-CLOCK deadline, distinct from
    # the SDK's read timeout above but the same diagnosis for an operator either way.
    "LLMDeadlineExceeded": TIMEOUT,
}


@dataclass(frozen=True)
class TransportHealth:
    """An immutable snapshot of what the transport has been doing lately."""

    consecutive_failures: int = 0
    last_error_kind: str | None = None
    last_status_code: int | None = None
    last_ok_at: datetime | None = None
    last_failure_at: datetime | None = None

    @property
    def status(self) -> str:
        """``unknown`` → ``ok`` → ``degraded`` → ``down``, in that order of certainty.

        ``unknown`` outranks ``ok`` at the start deliberately: a process that has made
        no call has no evidence, and evidence-free optimism is the failure mode.
        """
        if self.consecutive_failures >= OUTAGE_THRESHOLD:
            return DOWN
        if self.consecutive_failures > 0:
            return DEGRADED
        return OK if self.last_ok_at is not None else UNKNOWN

    @property
    def will_not_self_heal(self) -> bool:
        """True when the last failure was one nobody's retry can fix (402 / 401 / 403).

        The distinction an operator acts on: a rate limit or a timeout wants patience,
        an exhausted balance or a dead key wants a human with a credit card.
        """
        return self.last_error_kind in (CREDIT, AUTH)


_lock = threading.Lock()
_state = TransportHealth()


def classify(exc: BaseException) -> tuple[str, int | None]:
    """Map a transport exception to ``(kind, status_code)`` — never to its message.

    ``status_code`` is read by duck-typing rather than by importing the SDK's error
    hierarchy: ``openai.APIStatusError`` carries it, and so does anything else that
    wraps an HTTP response, so this works without the import and without a guess.
    """
    status = getattr(exc, "status_code", None)
    if isinstance(status, int):
        return _STATUS_KINDS.get(status, HTTP), status
    return _NAME_KINDS.get(type(exc).__name__, UNCLASSIFIED), None


def record_success(now: datetime | None = None) -> None:
    """A completion came back. Clears the failure streak — the outage, if any, is over."""
    global _state
    with _lock:
        _state = replace(
            _state,
            consecutive_failures=0,
            last_ok_at=now or datetime.now(tz=UTC),
        )


def record_failure(exc: BaseException, now: datetime | None = None) -> TransportHealth:
    """A completion raised. Extends the streak and records the diagnosis, not the text.

    Returns the resulting snapshot so a caller that wants to log the crossing can,
    without a second read that another thread could have moved underneath it.
    """
    global _state
    kind, status_code = classify(exc)
    with _lock:
        _state = replace(
            _state,
            consecutive_failures=_state.consecutive_failures + 1,
            last_error_kind=kind,
            last_status_code=status_code,
            last_failure_at=now or datetime.now(tz=UTC),
        )
        current = _state
    if current.status == DOWN:
        # WARNING, not exception: the exception itself is logged by whoever catches it
        # (the chain supervisor, the endpoint layer). This line adds the fact that fine
        # is a PATTERN — the thing no single stack trace can say.
        log.warning(
            "LLM transport looks DOWN: %d consecutive failures, last kind=%s status=%s",
            current.consecutive_failures,
            current.last_error_kind,
            current.last_status_code,
        )
    return current


def snapshot() -> TransportHealth:
    """The current record. A frozen copy, so a reader can never see a half-written one."""
    with _lock:
        return _state


def reset() -> None:
    """Forget everything — for tests, which must not inherit another test's transport."""
    global _state
    with _lock:
        _state = TransportHealth()
