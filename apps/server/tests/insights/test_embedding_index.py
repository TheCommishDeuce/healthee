"""``insights/embedding_index.py`` — the local passage-embedding index for hybrid
retrieval (Step 2a). Every test here uses a FAKE embedder: no network, no ONNX runtime, no
DB. The real ``fastembed`` model is exercised only in the opt-in smoke test at the
bottom, gated on ``HEALTHEE_EMBED_MODEL_TESTS=1``.
"""

from __future__ import annotations

import json
import logging
import os
from collections.abc import Iterator, Sequence

import numpy as np
import pytest
from numpy.typing import NDArray

from healthee.insights import embedding_index as ei
from healthee.insights.passages import Passage


class _FakeEmbedder:
    """Deterministic, hash-seeded vectors — no model, no network.

    Two calls with the same text always produce the same vector (so cache-hit tests can
    tell "rebuilt" from "loaded" by counting calls, not by comparing output), and
    unrelated texts land in different directions.
    """

    def __init__(self, dim: int = 8) -> None:
        self.dim = dim
        self.doc_calls = 0
        self.query_calls = 0

    def _vector(self, text: str) -> NDArray[np.float32]:
        rng = np.random.default_rng(abs(hash(text)) % (2**32))
        return rng.normal(size=self.dim).astype(np.float32)

    def embed_documents(self, texts: Sequence[str]) -> NDArray[np.float32]:
        self.doc_calls += 1
        return np.stack([self._vector(t) for t in texts])

    def embed_query(self, text: str) -> NDArray[np.float32]:
        self.query_calls += 1
        return self._vector(text)


class _MappedEmbedder:
    """A fake embedder whose vectors are an explicit ``text -> vector`` table, so a test
    can control exact similarities instead of relying on a hash's happenstance."""

    def __init__(self, vectors: dict[str, NDArray], query_vector: NDArray) -> None:
        self._vectors = vectors
        self._query_vector = query_vector

    def embed_documents(self, texts: Sequence[str]) -> NDArray[np.float32]:
        return np.stack([self._vectors[t] for t in texts])

    def embed_query(self, text: str) -> NDArray[np.float32]:
        return self._query_vector


def _passage(note_id: str, text: str, index: int = 0) -> Passage:
    return Passage(note_id=note_id, index=index, section="s", text=text)


@pytest.fixture(autouse=True)
def _reset_the_process_singleton() -> Iterator[None]:
    """Every test starts AND ends with ``ei._INDEX`` cleared.

    Without this, a test that populates the singleton with a fake object (e.g.
    ``test_index_is_built_once_and_cached_in_process``) leaks it to whatever test runs
    next in this process — including, across files, the grounding_eval recall gates,
    which then measure against a stale fake index instead of the real committed one.
    """
    ei.reset_index()
    yield
    ei.reset_index()


# ── cache key ──────────────────────────────────────────────────────────────


def test_cache_key_changes_when_a_passage_text_changes() -> None:
    a = [_passage("n", "hello world, a real passage")]
    b = [_passage("n", "hello mars, a real passage")]
    assert ei._cache_key("model-x", a) != ei._cache_key("model-x", b)


def test_cache_key_changes_when_the_model_id_changes() -> None:
    p = [_passage("n", "hello world, a real passage")]
    assert ei._cache_key("model-a", p) != ei._cache_key("model-b", p)


def test_the_committed_artifacts_key_matches_a_fresh_computation_over_the_real_corpus() -> None:
    """The multi-passage sensitivity a one- or two-item synthetic list cannot exercise.

    A mutation that hashes only a SUBSET of passages (the first, the last, every other
    one) cannot be told apart from a correct implementation by the tiny lists above —
    both endpoints of the comparison still differ, just for the wrong reason. It was
    caught for real only by a full-corpus rebuild timing out at >180 s, not by an
    assertion. This is that same check, at unit-test speed: the REAL 4,510-passage
    corpus's freshly recomputed key must still equal what ``packages/knowledge/
    embeddings/passages.json`` (built by the unmutated function) actually recorded.
    """
    committed_meta = json.loads((ei._COMMITTED_DIR / ei._META_FILE).read_text(encoding="utf-8"))
    recomputed = ei._cache_key(committed_meta["model_id"], ei.passages.all_passages())
    assert recomputed == committed_meta["key"]


def test_cache_key_is_stable_for_the_same_inputs() -> None:
    p = [_passage("n", "hello world, a real passage")]
    assert ei._cache_key("model-x", p) == ei._cache_key("model-x", p)


# ── build / cache round-trip ─────────────────────────────────────────────


def test_a_cached_index_is_loaded_not_rebuilt(tmp_path) -> None:
    passages = [_passage("n", "a passage of real length, well above the floor")]
    embedder = _FakeEmbedder()
    first = ei.build_index(embedder, passages, tmp_path, "model-x")
    assert embedder.doc_calls == 1

    second = ei.build_index(embedder, passages, tmp_path, "model-x")
    assert embedder.doc_calls == 1, "the embedder must not be called again on a cache hit"
    assert second.key == first.key
    assert second.refs == first.refs
    assert np.allclose(second.vectors, first.vectors)


def test_a_changed_corpus_rebuilds_instead_of_using_the_stale_cache(tmp_path) -> None:
    embedder = _FakeEmbedder()
    ei.build_index(embedder, [_passage("n", "original passage text here")], tmp_path, "model-x")
    assert embedder.doc_calls == 1
    ei.build_index(embedder, [_passage("n", "edited passage text here")], tmp_path, "model-x")
    assert embedder.doc_calls == 2, "a different passage text is a different key — must rebuild"


def test_a_row_count_mismatch_is_treated_as_a_cache_miss(tmp_path, caplog) -> None:
    """A sidecar whose ``refs`` list disagrees with the matrix's row count cannot be
    trusted — one of the two was written wrong or has been hand-edited — and must be
    rebuilt rather than served with the wrong ref attached to the wrong row."""
    np.save(tmp_path / ei._VECTORS_FILE, np.zeros((2, 4), dtype=np.float32))
    (tmp_path / ei._META_FILE).write_text(
        json.dumps({"key": "k", "model_id": "m", "count": 1, "refs": ["only-one#p0"]}),
        encoding="utf-8",
    )
    with caplog.at_level(logging.WARNING, logger="healthee.insights.embedding_index"):
        result = ei._load_cached(tmp_path, "k")
    assert result is None
    assert any("row count" in r.message for r in caplog.records)


def test_rows_are_unit_norm(tmp_path) -> None:
    passages = [_passage("n", f"passage number {i} has some real content in it") for i in range(6)]
    idx = ei.build_index(_FakeEmbedder(), passages, tmp_path, "model-x")
    norms = np.linalg.norm(idx.vectors, axis=1)
    assert np.allclose(norms, 1.0, atol=1e-5)


def test_an_empty_corpus_builds_an_empty_index(tmp_path) -> None:
    idx = ei.build_index(_FakeEmbedder(), [], tmp_path, "model-x")
    assert idx.refs == ()
    assert idx.vectors.shape[0] == 0
    assert idx.search("anything", k=5) == []
    assert idx.note_scores("anything") == {}


# ── search / note_scores ─────────────────────────────────────────────────


def test_search_returns_k_results_sorted_by_similarity(tmp_path) -> None:
    passages = [_passage(f"n{i}", f"distinct passage content number {i}") for i in range(5)]
    idx = ei.build_index(_FakeEmbedder(), passages, tmp_path, "model-x")
    results = idx.search("a question about number three", k=3)
    assert len(results) == 3
    sims = [sim for _ref, sim in results]
    assert sims == sorted(sims, reverse=True)


def test_search_k_larger_than_the_corpus_returns_everything(tmp_path) -> None:
    passages = [_passage("n1", "only passage here, well above the floor length")]
    idx = ei.build_index(_FakeEmbedder(), passages, tmp_path, "model-x")
    assert len(idx.search("anything", k=50)) == 1


def test_note_scores_takes_the_max_passage_per_note(tmp_path) -> None:
    query = np.array([1.0, 0.0], dtype=np.float32)
    vectors = {
        "n1 weak passage": np.array([0.1, 1.0], dtype=np.float32),
        "n1 strong passage": np.array([1.0, 0.0], dtype=np.float32),
        "n2 mid passage": np.array([0.5, 0.5], dtype=np.float32),
    }
    passages = [
        _passage("n1", "n1 weak passage", index=0),
        _passage("n1", "n1 strong passage", index=1),
        _passage("n2", "n2 mid passage", index=0),
    ]
    idx = ei.build_index(_MappedEmbedder(vectors, query), passages, tmp_path, "model-x")
    scores = idx.note_scores("a question")
    assert scores["n1"] == pytest.approx(1.0, abs=1e-5), (
        "must take the STRONG passage, not the weak one"
    )
    assert scores["n2"] < scores["n1"]


# ── failure policy ────────────────────────────────────────────────────────


def test_an_unloadable_model_raises_the_specific_error(monkeypatch, tmp_path) -> None:
    class _BoomTextEmbedding:
        def __init__(self, *_args: object, **_kwargs: object) -> None:
            raise RuntimeError("simulated: no cached file, no network")

    monkeypatch.setattr(ei, "TextEmbedding", _BoomTextEmbedding)
    with pytest.raises(ei.EmbeddingIndexUnavailableError):
        ei._FastEmbedder("some/model", str(tmp_path))


def test_a_numpy_or_corpus_bug_is_not_swallowed(tmp_path) -> None:
    """Only model-load failure is degraded; anything else is a real bug and propagates."""

    class _BrokenEmbedder:
        def embed_documents(self, texts: Sequence[str]) -> NDArray[np.float32]:
            raise ValueError("simulated corpus bug")

        def embed_query(self, text: str) -> NDArray[np.float32]:
            raise AssertionError("not reached")

    with pytest.raises(ValueError, match="simulated corpus bug"):
        ei.build_index(
            _BrokenEmbedder(), [_passage("n", "some real passage text")], tmp_path, "model-x"
        )


# ── the process-wide singleton ────────────────────────────────────────────


def test_index_is_built_once_and_cached_in_process(monkeypatch) -> None:
    calls = {"n": 0}

    def _fake_build() -> ei.EmbeddingIndex:
        calls["n"] += 1
        return ei.EmbeddingIndex(
            key="k",
            model_id="m",
            refs=(),
            vectors=np.zeros((0, 1), dtype=np.float32),
            embedder=_FakeEmbedder(),
        )

    monkeypatch.setattr(ei, "_index_uncached", _fake_build)
    ei.reset_index()
    first, second = ei.index(), ei.index()
    assert first is second
    assert calls["n"] == 1
    ei.reset_index()
    ei.index()
    assert calls["n"] == 2


# ── the committed artifact — no build on prod (task brief C) ──────────────


class _SettingsStub:
    """Just enough of `Settings` for `_index_uncached` — no DB env, no validation."""

    def __init__(self, model_id: str, cache_dir: str) -> None:
        self.embedding_model = model_id
        self.embedding_cache_dir = cache_dir


def test_a_valid_committed_artifact_is_preferred_and_the_corpus_is_never_embedded(
    monkeypatch, tmp_path
) -> None:
    """The whole point of shipping the artifact with the corpus: prod must load it
    read-only and never touch the (expensive, memory-heavy) embedding pass — verified
    here by a build-time embedder that would fail loudly if `embed_documents` were ever
    called again, and by the runtime cache dir staying completely empty."""
    committed_dir = tmp_path / "committed"
    cache_dir = tmp_path / "cache"
    cache_dir.mkdir()
    fake_corpus = (_passage("n", "a tiny fake passage of real length"),)

    build_time_embedder = _FakeEmbedder()
    ei.build_index(build_time_embedder, fake_corpus, committed_dir, "fake-model")
    assert build_time_embedder.doc_calls == 1

    monkeypatch.setattr(ei, "_COMMITTED_DIR", committed_dir)
    monkeypatch.setattr(ei.passages, "all_passages", lambda: fake_corpus)
    monkeypatch.setattr(ei, "get_settings", lambda: _SettingsStub("fake-model", str(cache_dir)))
    query_time_embedder = _FakeEmbedder()
    monkeypatch.setattr(ei, "_FastEmbedder", lambda _model_id, _cache_dir: query_time_embedder)

    idx = ei._index_uncached()

    assert query_time_embedder.doc_calls == 0, "the committed artifact must not be re-embedded"
    assert list(cache_dir.iterdir()) == [], "EMBEDDING_CACHE_DIR must stay untouched"
    assert idx.refs == tuple(p.ref for p in fake_corpus)


def test_a_stale_committed_artifact_falls_back_to_building_into_the_cache_dir(
    monkeypatch, tmp_path, caplog
) -> None:
    """A committed artifact whose key no longer matches the live corpus (a knowledge
    note edited without a `--build` + commit) must not be served silently — retrieval
    would then rank against yesterday's wording. The fallback embeds fresh into
    EMBEDDING_CACHE_DIR and says so, naming the fix."""
    committed_dir = tmp_path / "committed"
    cache_dir = tmp_path / "cache"
    fake_corpus = (_passage("n", "a tiny fake passage of real length"),)
    # Built under a DIFFERENT model id, so its key cannot match "fresh-model" below.
    ei.build_index(_FakeEmbedder(), fake_corpus, committed_dir, "stale-model")

    monkeypatch.setattr(ei, "_COMMITTED_DIR", committed_dir)
    monkeypatch.setattr(ei.passages, "all_passages", lambda: fake_corpus)
    monkeypatch.setattr(ei, "get_settings", lambda: _SettingsStub("fresh-model", str(cache_dir)))
    query_time_embedder = _FakeEmbedder()
    monkeypatch.setattr(ei, "_FastEmbedder", lambda _model_id, _cache_dir: query_time_embedder)

    with caplog.at_level(logging.WARNING, logger="healthee.insights.embedding_index"):
        idx = ei._index_uncached()

    assert query_time_embedder.doc_calls == 1, "a stale committed artifact must trigger a build"
    assert (cache_dir / ei._VECTORS_FILE).exists()
    assert idx.model_id == "fresh-model"
    warnings = [r.message for r in caplog.records if r.levelno == logging.WARNING]
    assert any("--build" in w for w in warnings)


# ── opt-in: the real model (never runs in CI) ─────────────────────────────


@pytest.mark.skipif(
    os.environ.get("HEALTHEE_EMBED_MODEL_TESTS") != "1",
    reason="downloads/loads the real ONNX model — opt in with HEALTHEE_EMBED_MODEL_TESTS=1",
)
def test_real_model_embeds_and_searches(tmp_path) -> None:
    embedder = ei._FastEmbedder(ei.get_settings().embedding_model, str(tmp_path))
    passages = [
        _passage("sleep", "Sleep duration and consistency affect next-day recovery."),
        _passage("steps", "Daily step count is associated with all-cause mortality risk."),
    ]
    idx = ei.build_index(embedder, passages, tmp_path, ei.get_settings().embedding_model)
    assert idx.vectors.shape == (2, 384)
    top = idx.search("how many steps should I walk", k=1)
    assert top[0][0] == "steps#p0"
