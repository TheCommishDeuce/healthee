"""Local passage-embedding index — the similarity signal for hybrid retrieval (Step 2a).

``retrieval.py`` scores notes by explicit signals + a lexical tie-break; this module
adds a real similarity on top. Every corpus passage (``passages.all_passages()``) is
embedded with a small, torch-free ONNX model (``fastembed.TextEmbedding``,
``BAAI/bge-small-en-v1.5`` — 69 MB, 384-d, MIT), persisted as a float32 ``.npy`` + a
JSON sidecar keyed by a SHA-256 over the model id and every passage TEXT in order —
not an mtime or count, either of which can stay unchanged while the wording moves.

## The committed artifact — no build on prod

The matrix is MACHINE-INDEPENDENT, so it ships WITH the corpus (``packages/knowledge/
embeddings/``, ~7 MB, built here and checked in like the manifest). The production box
(4 CPUs, under 1 GB free) cannot safely run the embedding pass, so :func:`index` loads
the artifact read-only once its key matches the live corpus, and only a stale/missing
one falls back to building into ``EMBEDDING_CACHE_DIR`` (logged, naming ``--build``).
The ONNX MODEL FILE is NOT committed — it downloads there on first use regardless,
since query embedding needs a live model. ``--check`` is a hash-only comparison.

## Failure policy — no swallowing

A missing model with no network to fetch it is a real failure, not "no notes are
similar": :class:`EmbeddingIndexUnavailableError` is the ONE type a caller may catch
and fall back on; anything else propagates as the real bug it is.

## Passage-level similarity (Step 2b)

:func:`note_scores` reduces the matrix to one similarity per NOTE; ``all_passage_
similarities`` returns the UNREDUCED per-passage scores for ``insights/evidence.py``'s
selection instead — one query embed, one matmul, shared across every note.
"""

from __future__ import annotations

import hashlib
import json
import sys
import time
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol

import numpy as np
from fastembed import TextEmbedding
from numpy.typing import NDArray

from healthee.core.config import get_settings
from healthee.core.logging import get_logger
from healthee.insights import passages
from healthee.insights.passages import Passage

log = get_logger(__name__)

_VECTORS_FILE = "passages.npy"
_META_FILE = "passages.json"

# The committed artifact — repo root / packages/knowledge/embeddings. Machine-
# independent (the cache key is model id + passage texts only), so it ships with the
# corpus like the manifest does. This file lives at
# apps/server/src/healthee/insights/embedding_index.py; parents[5] from here is the
# repo root (insights -> healthee -> src -> server -> apps -> repo root).
_COMMITTED_DIR = Path(__file__).resolve().parents[5] / "packages" / "knowledge" / "embeddings"


class EmbeddingIndexUnavailableError(RuntimeError):
    """The embedding model could not be loaded.

    Raised only for "the model itself is unreachable" (no cached ONNX file and no
    network on first run, or a download that failed) — never for a corpus or numpy
    problem, which propagates as whatever it actually is. This is the ONE type
    ``retrieval.py`` may catch (see its module docstring); catching anything broader
    there would hide a real bug behind the same "similarity unavailable" fallback.
    """


class _Embedder(Protocol):
    """What :class:`EmbeddingIndex` needs to turn text into unit vectors.

    A protocol, not the concrete fastembed wrapper, so tests inject a fake with no
    model file, network call, or ONNX runtime involved at all.
    """

    def embed_documents(self, texts: Sequence[str]) -> NDArray[np.float32]: ...
    def embed_query(self, text: str) -> NDArray[np.float32]: ...


# Bounded ONNX-runtime concurrency/batch size for whoever regenerates the committed
# artifact (never prod — see the module docstring). onnxruntime's per-thread arenas
# scale with THREAD COUNT, not corpus size: unbounded threads peaked at ~10.5 GB RSS
# on a 24-core dev machine embedding the full corpus; threads=1/batch=8 stayed <700 MB.
_EMBED_THREADS = 1
_EMBED_BATCH_SIZE = 8


class _FastEmbedder:
    """The real embedder — the only place ``fastembed`` is constructed."""

    def __init__(self, model_id: str, cache_dir: str) -> None:
        try:
            self._model = TextEmbedding(model_id, cache_dir=cache_dir, threads=_EMBED_THREADS)
        except Exception as exc:
            raise EmbeddingIndexUnavailableError(
                f"could not load embedding model {model_id!r} (EMBEDDING_CACHE_DIR="
                f"{cache_dir!r}): {exc}. Pre-populate the cache with `python -m "
                "healthee.insights.embedding_index --build` on a machine with network "
                "access, or check that EMBEDDING_CACHE_DIR is writable."
            ) from exc

    def embed_documents(self, texts: Sequence[str]) -> NDArray[np.float32]:
        vectors = self._model.embed(list(texts), batch_size=_EMBED_BATCH_SIZE)
        return np.asarray(list(vectors), dtype=np.float32)

    def embed_query(self, text: str) -> NDArray[np.float32]:
        return np.asarray(next(iter(self._model.query_embed([text]))), dtype=np.float32)


def _unit_rows(vectors: NDArray) -> NDArray[np.float32]:
    """L2-normalise every row so cosine similarity reduces to a dot product.

    A zero-norm row (an empty passage — cannot happen via ``passages.py``'s own
    ``_MIN_PASSAGE_CHARS`` floor, but a fake test embedder might) is left as zeros
    rather than divided by zero: it then scores 0 similarity against everything,
    which is the honest answer for a vector with no direction.
    """
    arr = np.atleast_2d(np.asarray(vectors, dtype=np.float32))
    norms = np.linalg.norm(arr, axis=1, keepdims=True)
    safe = np.where(norms == 0, 1.0, norms)
    return (arr / safe).astype(np.float32)


def _cache_key(model_id: str, passages_: Sequence[Passage]) -> str:
    """SHA-256 over the model id and every passage text, in order — see module docstring."""
    digest = hashlib.sha256(model_id.encode("utf-8"))
    for p in passages_:
        digest.update(b"\x00")
        digest.update(p.text.encode("utf-8"))
    return digest.hexdigest()


@dataclass(frozen=True)
class EmbeddingIndex:
    """A built, ready-to-query passage index. See the module docstring for the shape."""

    key: str
    model_id: str
    refs: tuple[str, ...]
    vectors: NDArray[np.float32]  # (len(refs), dim), unit-norm rows
    embedder: _Embedder = field(compare=False, repr=False)

    def _similarities(self, question: str) -> NDArray[np.float32]:
        qv = _unit_rows(self.embedder.embed_query(question))[0]
        return self.vectors @ qv

    def search(self, question: str, k: int) -> list[tuple[str, float]]:
        """Top-``k`` ``(passage ref, cosine similarity)``, highest first."""
        if k <= 0 or not self.refs:
            return []
        sims = self._similarities(question)
        order = np.argsort(-sims)[:k]
        return [(self.refs[i], float(sims[i])) for i in order]

    def note_scores(self, question: str) -> dict[str, float]:
        """Max passage similarity per note id — what ``retrieval.rank_notes`` consumes."""
        if not self.refs:
            return {}
        sims = self._similarities(question)
        scores: dict[str, float] = {}
        for ref, sim in zip(self.refs, sims.tolist(), strict=True):
            note_id = ref.split("#p", 1)[0]
            if sim > scores.get(note_id, float("-inf")):
                scores[note_id] = sim
        return scores

    def all_passage_similarities(self, question: str) -> dict[str, float]:
        """Every passage's cosine similarity to ``question``, keyed by its ref.

        The UNREDUCED counterpart to :meth:`note_scores`: one query embed, one matmul
        against the whole matrix — ``insights/evidence.py``'s passage selection (Step
        2b) reads this once per question rather than re-embedding the question per note.
        """
        if not self.refs:
            return {}
        sims = self._similarities(question)
        return dict(zip(self.refs, sims.tolist(), strict=True))


def _load_cached(cache_dir: Path, key: str) -> tuple[tuple[str, ...], NDArray[np.float32]] | None:
    """``(refs, vectors)`` from disk if present and current, else ``None``.

    Any of "no cache yet", "corrupt sidecar", "corrupt matrix" or "row-count mismatch"
    is treated the same way — a cache miss that triggers a rebuild — because all four
    describe a cache that cannot be trusted, not a reason to fail the request.
    """
    meta_path, vec_path = cache_dir / _META_FILE, cache_dir / _VECTORS_FILE
    if not meta_path.exists() or not vec_path.exists():
        return None
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        log.warning("embedding index cache metadata unreadable (%s) — rebuilding", exc)
        return None
    if meta.get("key") != key:
        return None
    try:
        vectors = np.load(vec_path)
    except (OSError, ValueError) as exc:
        log.warning("embedding index cache matrix unreadable (%s) — rebuilding", exc)
        return None
    refs = tuple(meta.get("refs", ()))
    if vectors.shape[0] != len(refs):
        log.warning(
            "embedding index cache row count %d != ref count %d — rebuilding",
            vectors.shape[0],
            len(refs),
        )
        return None
    return refs, vectors.astype(np.float32, copy=False)


def _save_cache(
    cache_dir: Path, key: str, model_id: str, refs: tuple[str, ...], vectors: NDArray
) -> None:
    cache_dir.mkdir(parents=True, exist_ok=True)
    np.save(cache_dir / _VECTORS_FILE, vectors)
    (cache_dir / _META_FILE).write_text(
        json.dumps({"key": key, "model_id": model_id, "count": len(refs), "refs": list(refs)}),
        encoding="utf-8",
    )


def build_index(
    embedder: _Embedder, passages_: Sequence[Passage], cache_dir: Path, model_id: str
) -> EmbeddingIndex:
    """Load ``passages_`` from ``cache_dir`` if the key matches, else embed and save.

    The pure, testable core: embedder and passage list are arguments, not process
    singletons, so a test injects a fake embedder and a temp dir — no model, network.
    """
    key = _cache_key(model_id, passages_)
    cached = _load_cached(cache_dir, key)
    if cached is not None:
        refs, vectors = cached
        log.info("embedding index loaded from cache: %d passages (key=%s)", len(refs), key[:12])
        return EmbeddingIndex(
            key=key, model_id=model_id, refs=refs, vectors=vectors, embedder=embedder
        )

    t0 = time.monotonic()
    refs = tuple(p.ref for p in passages_)
    if refs:
        vectors = _unit_rows(embedder.embed_documents([p.text for p in passages_]))
    else:
        vectors = np.zeros((0, 1), dtype=np.float32)
    elapsed = time.monotonic() - t0
    log.info("embedding index built: %d passages in %.1fs (key=%s)", len(refs), elapsed, key[:12])
    _save_cache(cache_dir, key, model_id, refs, vectors)
    return EmbeddingIndex(key=key, model_id=model_id, refs=refs, vectors=vectors, embedder=embedder)


def _index_uncached() -> EmbeddingIndex:
    """Prefer the COMMITTED artifact; fall back to building into the runtime cache.

    The embedder is constructed either way (query embedding needs a live model
    regardless); only the passage-embedding pass is skippable, when the committed
    key still matches the live corpus.
    """
    settings = get_settings()
    embedder = _FastEmbedder(settings.embedding_model, settings.embedding_cache_dir)
    passages_ = passages.all_passages()
    key = _cache_key(settings.embedding_model, passages_)
    committed = _load_cached(_COMMITTED_DIR, key)
    if committed is not None:
        refs, vectors = committed
        log.info(
            "embedding index loaded from committed artifact: %d passages (key=%s)",
            len(refs),
            key[:12],
        )
        return EmbeddingIndex(
            key=key,
            model_id=settings.embedding_model,
            refs=refs,
            vectors=vectors,
            embedder=embedder,
        )
    log.warning(
        "committed embedding index at %s is missing or stale for the current corpus — "
        "building into EMBEDDING_CACHE_DIR instead. Run `python -m "
        "healthee.insights.embedding_index --build` and commit packages/knowledge/embeddings/.",
        _COMMITTED_DIR,
    )
    return build_index(
        embedder, passages_, Path(settings.embedding_cache_dir), settings.embedding_model
    )


_INDEX: EmbeddingIndex | None = None


def index() -> EmbeddingIndex:
    """The process-wide index, built once lazily on first use.

    Not ``@lru_cache`` — a module-level singleton reads more plainly here and
    ``reset_index()`` gives tests an explicit, named way to force a rebuild, which a
    bare ``.cache_clear()`` on a private wrapper would not.
    """
    global _INDEX
    if _INDEX is None:
        _INDEX = _index_uncached()
    return _INDEX


def reset_index() -> None:
    """Drop the cached singleton so the next call to :func:`index` rebuilds it."""
    global _INDEX
    _INDEX = None


def search(question: str, k: int) -> list[tuple[str, float]]:
    """Top-``k`` ``(passage ref, similarity)`` for ``question`` against the live index."""
    return index().search(question, k)


def note_scores(question: str) -> dict[str, float]:
    """Max passage similarity per note id for ``question`` against the live index."""
    return index().note_scores(question)


_USAGE = "usage: python -m healthee.insights.embedding_index --build [--out DIR] | --check"


def _run_build(rest: list[str]) -> int:
    """Embed the corpus and write it to ``--out`` (default: the committed artifact dir).

    Never fatal to a caller: prints the reason and exits 1 on a model-load failure.
    """
    out_dir = _COMMITTED_DIR
    if rest:
        if len(rest) != 2 or rest[0] != "--out":
            print(_USAGE, file=sys.stderr)
            return 2
        out_dir = Path(rest[1])
    settings = get_settings()
    try:
        embedder = _FastEmbedder(settings.embedding_model, settings.embedding_cache_dir)
    except EmbeddingIndexUnavailableError as exc:
        print(f"embedding index build FAILED: {exc}", file=sys.stderr)
        return 1
    t0 = time.monotonic()
    idx = build_index(embedder, passages.all_passages(), out_dir, settings.embedding_model)
    elapsed = time.monotonic() - t0
    print(
        f"embedding index ready: {len(idx.refs)} passages, key={idx.key[:12]}, "
        f"{elapsed:.1f}s -> {out_dir}"
    )
    return 0


def _run_check() -> int:
    """Recompute the corpus key and compare it to the committed artifact's — HASH ONLY.

    No model construction, no network, no ``EMBEDDING_CACHE_DIR`` touched — safe to run
    in CI on the ``uv sync --frozen`` env with no model file present, same as
    ``gen_manifest.py --check``.
    """
    settings = get_settings()
    key = _cache_key(settings.embedding_model, passages.all_passages())
    meta_path = _COMMITTED_DIR / _META_FILE
    fix = "run: python -m healthee.insights.embedding_index --build"
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"embedding index artifact unreadable at {meta_path}: {exc}\n{fix}", file=sys.stderr)
        return 1
    committed_key = meta.get("key")
    if committed_key != key:
        print(
            f"embedding index artifact is STALE for the current corpus "
            f"(committed key={str(committed_key)[:12]}, current key={key[:12]}).\n{fix}",
            file=sys.stderr,
        )
        return 1
    print(f"embedding index artifact up to date: {meta.get('count')} passages (key={key[:12]})")
    return 0


def _main() -> int:
    """``python -m healthee.insights.embedding_index --build [--out DIR] | --check``."""
    args = sys.argv[1:]
    if args[:1] == ["--check"] and len(args) == 1:
        return _run_check()
    if args[:1] == ["--build"]:
        return _run_build(args[1:])
    print(_USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(_main())
