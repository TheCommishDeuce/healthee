"""Which LLM endpoint `LLM_BASE_URL` names, and what that changes.

Completions go to any OpenAI-compatible `/v1` endpoint: OpenRouter by default, or a
local llama.cpp/vLLM server (DESIGN_DECISIONS P2). Set OPENROUTER_API_KEY to whatever
that server expects — any non-empty string when it checks none, because the key is
also the switch that turns the AI layer on.

Two things are OpenRouter's alone and are skipped elsewhere: its request extensions
(`usage`, `reasoning`, `provider` — some servers ignore unknown fields, some refuse
the request) and its `/credits` billing endpoint, which a local server has no
equivalent of.
"""

from __future__ import annotations

from urllib.parse import urlsplit


def is_openrouter(base_url: str) -> bool:
    """Whether `base_url` is OpenRouter."""
    return urlsplit(base_url).hostname == "openrouter.ai"
