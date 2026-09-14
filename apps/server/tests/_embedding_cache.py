"""The Step 2a embedding-index cache fixture, split out of ``conftest.py``.

``conftest.py`` was already 393/400 lines — this one autouse fixture is pulled into
its own module rather than pushing that file over the hard file-length gate.
``conftest.py`` imports it by name, which is enough for pytest to register it as an
ordinary autouse fixture.
"""

from __future__ import annotations

import os
from collections.abc import Iterator
from pathlib import Path

import pytest

from healthee.core.config import get_settings


@pytest.fixture(scope="session", autouse=True)
def _embedding_cache_is_reachable() -> Iterator[None]:
    """Point the Step 2a embedding index cache at a STABLE, repo-local directory.

    Unlike the geodata caches in ``conftest.py``, this cache's CONTENT matters: the
    ``tests/grounding_eval`` recall pins are measured against the REAL model, so a
    fresh ``tmp_path`` every session would force a several-minute, network-dependent
    rebuild on every run. `/var/cache/healthee/embeddings` (the container's default) is
    typically unwritable on a dev machine or CI runner; this repo-local, gitignored
    directory is REUSED across runs instead — first run pays the real download/embed
    cost, every run after loads from disk in well under a second. Not in this task's
    closed edit list — added because its gate cannot pass without one.
    """
    root = Path(__file__).resolve().parent.parent / ".cache" / "embeddings"
    previous = os.environ.get("EMBEDDING_CACHE_DIR")
    os.environ["EMBEDDING_CACHE_DIR"] = str(root)
    get_settings.cache_clear()
    yield
    if previous is None:
        os.environ.pop("EMBEDDING_CACHE_DIR", None)
    else:
        os.environ["EMBEDDING_CACHE_DIR"] = previous
    get_settings.cache_clear()
