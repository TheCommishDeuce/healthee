"""COACH_REASONING — where the coach spends thinking, and what the request carries.

The measured motivation is in ``core/config.py``: thinking is decode-time output, and two
of a coach question's three rounds only pick a tool. These tests pin the contract at
each layer — the setting's vocabulary, the per-round decision, and the exact request
field the transport sends — with no network and no model.
"""

from __future__ import annotations

from typing import Any

import pytest
from tests.insights._client_fakes import _client_with_fake

from healthee.core.config import get_settings
from healthee.insights import coach_loop, pipeline
from healthee.insights.client import ChatResponse


@pytest.fixture
def reasoning_mode(monkeypatch: pytest.MonkeyPatch):
    def _set(mode: str) -> None:
        monkeypatch.setenv("COACH_REASONING", mode)
        get_settings.cache_clear()

    yield _set
    get_settings.cache_clear()


# ── the setting ───────────────────────────────────────────────────────────────


@pytest.mark.parametrize("bad", ["sometimes", "Off", "ANSWER_ONLY", ""])
def test_an_unknown_or_miscased_mode_is_refused_at_boot(reasoning_mode, bad: str) -> None:
    reasoning_mode(bad)
    with pytest.raises(ValueError, match="coach_reasoning"):
        get_settings()


def test_the_default_is_on_the_shipped_behaviour(reasoning_mode, monkeypatch) -> None:
    monkeypatch.delenv("COACH_REASONING", raising=False)
    get_settings.cache_clear()
    assert get_settings().coach_reasoning == "on"


# ── the per-round decision ────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("mode", "tools_allowed", "expected"),
    [
        ("on", True, None),
        ("on", False, None),
        ("off", True, False),
        ("off", False, False),
        ("answer_only", True, False),
        ("answer_only", False, None),
    ],
)
def test_reasoning_per_round(reasoning_mode, mode: str, tools_allowed: bool, expected) -> None:
    reasoning_mode(mode)
    assert coach_loop.reasoning_for_round(tools_allowed) is expected


# ── the seam: None is not sent, False is ──────────────────────────────────────


class _Recorder:
    def __init__(self) -> None:
        self.kwargs: dict[str, Any] | None = None

    def complete(self, messages: list[dict], **kwargs: Any) -> ChatResponse:  # noqa: ARG002
        self.kwargs = kwargs
        return ChatResponse(text="ok")


def test_pipeline_forwards_reasoning_only_when_set() -> None:
    rec = _Recorder()
    pipeline.complete(rec, [{"role": "user", "content": "q"}])
    assert rec.kwargs is not None and "reasoning" not in rec.kwargs
    pipeline.complete(rec, [{"role": "user", "content": "q"}], reasoning=False)
    assert rec.kwargs is not None and rec.kwargs["reasoning"] is False


# ── the transport: the exact field OpenRouter reads ───────────────────────────


def test_reasoning_off_is_sent_as_the_openrouter_field(monkeypatch) -> None:
    monkeypatch.setenv("OPENROUTER_API_KEY", "test-key")
    monkeypatch.setenv("DEFAULT_MODEL", "vendor-x/cheap")
    monkeypatch.setenv("COACH_MODEL", "vendor-x/strong")
    get_settings.cache_clear()
    try:
        client, fake = _client_with_fake()
        client.complete([{"role": "user", "content": "q"}], reasoning=False)
        sent = fake.chat.completions.kwargs
        assert sent is not None
        assert sent["extra_body"]["reasoning"] == {"enabled": False}
    finally:
        get_settings.cache_clear()


def test_reasoning_unset_or_true_changes_nothing_in_the_request(monkeypatch) -> None:
    monkeypatch.setenv("OPENROUTER_API_KEY", "test-key")
    monkeypatch.setenv("DEFAULT_MODEL", "vendor-x/cheap")
    monkeypatch.setenv("COACH_MODEL", "vendor-x/strong")
    get_settings.cache_clear()
    try:
        client, fake = _client_with_fake()
        client.complete([{"role": "user", "content": "q"}])
        plain = fake.chat.completions.kwargs
        client.complete([{"role": "user", "content": "q"}], reasoning=True)
        explicit = fake.chat.completions.kwargs
        assert plain is not None and explicit is not None
        assert "reasoning" not in plain.get("extra_body", {})
        assert plain.get("extra_body") == explicit.get("extra_body")
    finally:
        get_settings.cache_clear()
