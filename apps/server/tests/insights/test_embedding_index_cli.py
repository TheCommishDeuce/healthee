"""``python -m healthee.insights.embedding_index`` — split out of
``test_embedding_index.py`` (that file was pushing the 400-line file gate). Same
offline-only rules apply: every test here uses a FAKE embedder or none at all.
"""

from __future__ import annotations

import json
import sys

from tests.insights.test_embedding_index import _FakeEmbedder, _passage

from healthee.insights import embedding_index as ei


def test_cli_build_writes_to_the_given_out_dir(monkeypatch, tmp_path, capsys) -> None:
    monkeypatch.setattr(sys, "argv", ["embedding_index", "--build", "--out", str(tmp_path)])
    monkeypatch.setattr(ei, "_FastEmbedder", lambda _model_id, _cache_dir: _FakeEmbedder())
    monkeypatch.setattr(
        ei.passages, "all_passages", lambda: (_passage("n", "a real passage of length"),)
    )
    assert ei._main() == 0
    out = capsys.readouterr().out
    assert "embedding index ready: 1 passages" in out
    assert str(tmp_path) in out
    assert (tmp_path / "passages.npy").exists()


def test_cli_build_defaults_to_the_committed_dir(monkeypatch, tmp_path, capsys) -> None:
    monkeypatch.setattr(sys, "argv", ["embedding_index", "--build"])
    monkeypatch.setattr(ei, "_COMMITTED_DIR", tmp_path)
    monkeypatch.setattr(ei, "_FastEmbedder", lambda _model_id, _cache_dir: _FakeEmbedder())
    monkeypatch.setattr(
        ei.passages, "all_passages", lambda: (_passage("n", "a real passage of length"),)
    )
    assert ei._main() == 0
    assert str(tmp_path) in capsys.readouterr().out
    assert (tmp_path / "passages.npy").exists()


def test_cli_build_out_requires_a_directory_argument(monkeypatch) -> None:
    monkeypatch.setattr(sys, "argv", ["embedding_index", "--build", "--out"])
    assert ei._main() == 2


def test_cli_build_reports_model_load_failure_without_crashing(monkeypatch, capsys) -> None:
    monkeypatch.setattr(sys, "argv", ["embedding_index", "--build"])

    def _boom(_model_id: str, _cache_dir: str) -> _FakeEmbedder:
        raise ei.EmbeddingIndexUnavailableError("simulated: no network")

    monkeypatch.setattr(ei, "_FastEmbedder", _boom)
    assert ei._main() == 1
    assert "embedding index build FAILED" in capsys.readouterr().err


def test_cli_check_reports_up_to_date(monkeypatch, tmp_path, capsys) -> None:
    key = ei._cache_key(ei.get_settings().embedding_model, ei.passages.all_passages())
    (tmp_path / "passages.json").write_text(json.dumps({"key": key, "count": 4510, "refs": []}))
    monkeypatch.setattr(ei, "_COMMITTED_DIR", tmp_path)
    monkeypatch.setattr(sys, "argv", ["embedding_index", "--check"])
    assert ei._main() == 0
    assert "up to date" in capsys.readouterr().out


def test_cli_check_reports_a_stale_artifact(monkeypatch, tmp_path, capsys) -> None:
    (tmp_path / "passages.json").write_text(json.dumps({"key": "deadbeef", "count": 0, "refs": []}))
    monkeypatch.setattr(ei, "_COMMITTED_DIR", tmp_path)
    monkeypatch.setattr(sys, "argv", ["embedding_index", "--check"])
    assert ei._main() == 1
    err = capsys.readouterr().err
    assert "STALE" in err
    assert "--build" in err


def test_cli_check_reports_a_missing_artifact(monkeypatch, tmp_path, capsys) -> None:
    monkeypatch.setattr(ei, "_COMMITTED_DIR", tmp_path / "does-not-exist")
    monkeypatch.setattr(sys, "argv", ["embedding_index", "--check"])
    assert ei._main() == 1
    assert "unreadable" in capsys.readouterr().err


def test_cli_check_never_constructs_an_embedder(monkeypatch, tmp_path) -> None:
    """The whole point of ``--check``: hash-only, no model, no network (task brief D)."""
    key = ei._cache_key(ei.get_settings().embedding_model, ei.passages.all_passages())
    (tmp_path / "passages.json").write_text(json.dumps({"key": key, "count": 4510, "refs": []}))
    monkeypatch.setattr(ei, "_COMMITTED_DIR", tmp_path)

    def _boom(*_args: object, **_kwargs: object) -> None:
        raise AssertionError("--check must never construct an embedder")

    monkeypatch.setattr(ei, "_FastEmbedder", _boom)
    monkeypatch.setattr(sys, "argv", ["embedding_index", "--check"])
    assert ei._main() == 0


def test_cli_rejects_an_unknown_argument(monkeypatch) -> None:
    monkeypatch.setattr(sys, "argv", ["embedding_index", "--nonsense"])
    assert ei._main() == 2
