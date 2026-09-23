"""A local model behind `LLM_BASE_URL` (DESIGN_DECISIONS P2) — what changes, and what not.

Completions go wherever the base URL points; OpenRouter's request extensions and its
billing balance are OpenRouter's alone. No network: the SDK and `httpx.get` are fakes.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import httpx
import pytest
from tests.insights._client_fakes import _client_with_fake

from healthee.core.config import get_settings
from healthee.core.llm_endpoint import is_openrouter
from healthee.insights import credits
from healthee.insights.client import OpenRouterClient

_LOCAL = "http://gemma.lan:8080/v1"


@pytest.fixture
def keyed(monkeypatch: pytest.MonkeyPatch) -> Iterator[pytest.MonkeyPatch]:
    monkeypatch.setenv("OPENROUTER_API_KEY", "local-not-checked")
    monkeypatch.setenv("DEFAULT_MODEL", "gemma")
    monkeypatch.setenv("COACH_MODEL", "gemma")
    monkeypatch.setenv("POSTGRES_PASSWORD", "unit-test-pw")
    get_settings.cache_clear()
    credits.reset_cache()
    yield monkeypatch
    get_settings.cache_clear()
    credits.reset_cache()


def _local(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_BASE_URL", _LOCAL)
    get_settings.cache_clear()


@pytest.mark.parametrize(
    ("url", "expected"),
    [
        ("https://openrouter.ai/api/v1", True),
        ("http://gemma.lan:8080/v1", False),
        ("https://openrouter.ai.evil.example/v1", False),
        ("http://127.0.0.1:8080/v1", False),
    ],
)
def test_openrouter_is_recognised_by_host_only(url: str, expected: bool) -> None:
    assert is_openrouter(url) is expected


def test_openrouter_requests_keep_their_extensions(keyed: pytest.MonkeyPatch) -> None:  # noqa: ARG001
    client, fake = _client_with_fake()
    client.complete([{"role": "user", "content": "x"}], reasoning=False)
    body = fake.chat.completions.kwargs["extra_body"]
    assert body["usage"] == {"include": True}
    assert body["reasoning"] == {"enabled": False}


def test_a_local_endpoint_gets_a_plain_openai_request(keyed: pytest.MonkeyPatch) -> None:
    _local(keyed)
    client, fake = _client_with_fake()
    client.complete([{"role": "user", "content": "x"}], reasoning=False)
    kwargs = fake.chat.completions.kwargs
    assert "extra_body" not in kwargs
    assert kwargs["stream"] is True
    assert kwargs["model"] == "gemma"


def test_the_sdk_is_pointed_at_the_configured_base_url(keyed: pytest.MonkeyPatch) -> None:
    _local(keyed)
    sdk: Any = OpenRouterClient()._client()
    assert str(sdk.base_url).rstrip("/") == _LOCAL


def test_a_local_endpoint_has_no_balance_and_asks_openrouter_nothing(
    keyed: pytest.MonkeyPatch,
) -> None:
    _local(keyed)
    calls: list[str] = []

    def fake_get(url: str, **_: Any) -> httpx.Response:
        calls.append(url)
        return httpx.Response(200, json={"data": {"total_credits": 1, "total_usage": 0}})

    keyed.setattr(httpx, "get", fake_get)
    reading = credits.read_balance(force=True)
    assert reading.status == credits.NO_BALANCE
    assert credits.balance_state(reading) == credits.BALANCE_UNKNOWN
    assert calls == [], "the local model's key must never be sent to OpenRouter"
