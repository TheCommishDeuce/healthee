"""``RunRecord.support_details`` — the per-claim audit trail ``score`` writes.

Split out of ``test_score.py`` (see that file's own docstring on the 400-line gate):
this file only tests the NEW field, both round-tripping through ``records.save/load``
and being populated by the ``score`` subcommand with the exact shape a person would
need to audit an "unsupported" verdict without re-running the model.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from tests.grounding_eval import questions as qs
from tests.grounding_eval import records as records_mod
from tests.grounding_eval.__main__ import main
from tests.grounding_eval.records import GROUNDED, EvalRun, RunRecord
from tests.grounding_eval.support import ClaimSupport, SupportScore


def _rec(qid: str, *, answer: str = "") -> RunRecord:
    return RunRecord(
        question_id=qid,
        kind=qs.KNOWLEDGE,
        surface="coach",
        repeat=0,
        outcome=GROUNDED,
        success=True,
        answer=answer,
    )


def _arm(records: list[RunRecord]) -> EvalRun:
    return EvalRun(
        label="arm",
        commit="abc1234",
        question_set="fp",
        repeats=1,
        started_at="2026-01-01T00:00:00+00:00",
        records=records,
    )


# ── round trip through records.save/load ──────────────────────────────────────


def test_an_old_shape_record_without_support_details_loads_with_empty_list(
    tmp_path: Path,
) -> None:
    old = {
        "label": "old",
        "commit": "abc1234",
        "question_set": "deadbeefcafe",
        "repeats": 1,
        "started_at": "2026-01-01T00:00:00+00:00",
        "records": [
            {
                "question_id": "q",
                "kind": qs.KNOWLEDGE,
                "surface": "coach",
                "repeat": 0,
                "outcome": GROUNDED,
                "success": True,
            }
        ],
    }
    path = tmp_path / "old.json"
    path.write_text(json.dumps(old), encoding="utf-8")

    run = records_mod.load(path)

    assert run.records[0].support_details == []


def test_support_details_round_trips_through_save_and_load(tmp_path: Path) -> None:
    detail = {
        "sentence": "Widgets improve grip strength.",
        "fragments": ["Widgets improve grip strength."],
        "cited": ["known_note"],
        "best_ref": "known_note#p0",
        "best_fragment": "Widgets improve grip strength.",
        "entailment": 0.9,
        "contradiction": 0.02,
        "supported": True,
        "interpretive": False,
    }
    record = RunRecord(
        question_id="q",
        kind=qs.KNOWLEDGE,
        surface="coach",
        repeat=0,
        outcome=GROUNDED,
        success=True,
        answer="text",
        support_details=[detail],
    )
    path = tmp_path / "arm.json"
    records_mod.save(_arm([record]), path)

    loaded = records_mod.load(path)

    assert loaded.records[0].support_details == [detail]


# ── populated by `score` ──────────────────────────────────────────────────────


def _fake_score_answer(text: str, *, threshold: float = 0.5, nli=None) -> SupportScore:  # noqa: ARG001
    details = (
        ClaimSupport(
            "Widgets improve grip strength.",
            ("known_note",),
            "known_note#p0",
            0.9,
            0.02,
            True,
            interpretive=False,
            fragments=("Widgets improve grip strength.",),
            best_fragment="Widgets improve grip strength.",
        ),
    )
    return SupportScore(claims=1, cited_claims=1, supported=1, threshold=threshold, details=details)


def test_score_writes_the_full_claim_detail_shape(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    import tests.grounding_eval.support as support_module

    monkeypatch.setattr(support_module, "score_answer", _fake_score_answer)
    arm_path, out_path = tmp_path / "arm.json", tmp_path / "arm.scored.json"
    records_mod.save(_arm([_rec("a", answer="text")]), arm_path)

    assert main(["score", str(arm_path), "--out", str(out_path)]) == 0

    detail = records_mod.load(out_path).records[0].support_details[0]
    assert detail == {
        "sentence": "Widgets improve grip strength.",
        "fragments": ["Widgets improve grip strength."],
        "cited": ["known_note"],
        "best_ref": "known_note#p0",
        "best_fragment": "Widgets improve grip strength.",
        "entailment": 0.9,
        "contradiction": 0.02,
        "supported": True,
        "interpretive": False,
        "scorable": True,
    }


def test_score_writes_an_empty_support_details_list_for_a_non_grounded_record(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    import tests.grounding_eval.support as support_module

    def explode(text: str, *, threshold: float = 0.5, nli=None):  # noqa: ARG001
        raise AssertionError("score_answer must never be called for a non-grounded record")

    monkeypatch.setattr(support_module, "score_answer", explode)
    arm_path, out_path = tmp_path / "arm.json", tmp_path / "arm.scored.json"
    from tests.grounding_eval.records import FALLBACK

    records_mod.save(
        _arm([RunRecord("a", qs.KNOWLEDGE, "coach", 0, FALLBACK, False, answer="fallback text")]),
        arm_path,
    )

    main(["score", str(arm_path), "--out", str(out_path)])

    assert records_mod.load(out_path).records[0].support_details == []
