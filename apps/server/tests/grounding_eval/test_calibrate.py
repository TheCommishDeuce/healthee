"""``tests/grounding_eval/calibrate.py`` — the human-labelling loop, offline throughout.

``sample`` is exercised against a hand-built, already-``score``d :class:`EvalRun` (no
real corpus, a :class:`FakeNLI` standing in for the model ``rank_passages`` would
otherwise load); ``evaluate``/``report`` are exercised against a hand-labelled sheet
with numbers worked out by hand in each test's docstring, per the brief's "assert exact
numbers".
"""

from __future__ import annotations

from pathlib import Path

import pytest
from tests.grounding_eval import calibrate
from tests.grounding_eval.records import GROUNDED, EvalRun, RunRecord
from tests.grounding_eval.test_support import FakeNLI, _fake_passages


def _detail(sentence: str, *, supported: bool, entailment: float = 0.0) -> dict:
    return {
        "sentence": sentence,
        "fragments": [sentence],
        "cited": ["known_note"],
        "best_ref": "known_note#p0" if supported else None,
        "best_fragment": sentence if supported else None,
        "entailment": entailment,
        "contradiction": 0.0,
        "supported": supported,
        "interpretive": True,
    }


def _run(details: list[dict]) -> EvalRun:
    records = [
        RunRecord(
            question_id=f"q{i}",
            kind="knowledge",
            surface="coach",
            repeat=0,
            outcome=GROUNDED,
            success=True,
            answer="text",
            support_details=[detail],
        )
        for i, detail in enumerate(details)
    ]
    return EvalRun(
        label="arm",
        commit="abc",
        question_set="fp",
        repeats=1,
        started_at="2026-01-01",
        records=records,
    )


# ── sample() ───────────────────────────────────────────────────────────────


def test_sample_is_stratified_half_supported_half_not() -> None:
    details = [_detail(f"s{i}", supported=True, entailment=0.9) for i in range(6)]
    details += [_detail(f"u{i}", supported=False, entailment=0.1) for i in range(6)]
    run = _run(details)

    rows = calibrate.sample(run, n=4, seed=1, nli=FakeNLI())

    assert len(rows) == 4
    assert sum(1 for r in rows if r["currently_supported"]) == 2
    assert sum(1 for r in rows if not r["currently_supported"]) == 2


def test_sample_is_deterministic_for_a_fixed_seed() -> None:
    details = [_detail(f"s{i}", supported=True, entailment=0.9) for i in range(6)]
    details += [_detail(f"u{i}", supported=False, entailment=0.1) for i in range(6)]
    run = _run(details)

    first = calibrate.sample(run, n=4, seed=7, nli=FakeNLI())
    second = calibrate.sample(run, n=4, seed=7, nli=FakeNLI())

    assert [r["sentence"] for r in first] == [r["sentence"] for r in second]


def test_sample_draws_everything_a_short_group_has_rather_than_raising() -> None:
    """Only one supported claim exists; asking for 4 (half = 2 supported) must not
    raise — it draws the ONE available and does not top the total back up to 4, per
    the module docstring: a short group shrinks the sheet, it never blocks it."""
    details = [_detail("only_supported", supported=True, entailment=0.9)]
    details += [_detail(f"u{i}", supported=False, entailment=0.1) for i in range(6)]
    run = _run(details)

    rows = calibrate.sample(run, n=4, seed=1, nli=FakeNLI())

    assert len(rows) == 3  # 1 supported (all there is) + 2 unsupported (n - half)
    assert sum(1 for r in rows if r["currently_supported"]) == 1


def test_sample_includes_top_passages_for_each_row(monkeypatch: pytest.MonkeyPatch) -> None:
    """`rank_passages` runs against the real (fake, here) corpus for each sampled
    claim — the evidence a human needs without re-running the model themselves."""
    details = [
        _detail("Widgets improve grip strength over many weeks", supported=True, entailment=0.9)
    ]
    run = _run(details)
    fake = FakeNLI(
        rules={("improve grip strength", "Widgets improve grip strength"): (0.02, 0.9, 0.08)}
    )
    import tests.grounding_eval.support as support_module

    monkeypatch.setattr(support_module.manifest, "note_ids", lambda: {"known_note"})
    monkeypatch.setattr(support_module.passages_mod, "passages", _fake_passages)

    rows = calibrate.sample(run, n=2, seed=1, nli=fake)

    assert rows[0]["top_passages"]
    assert rows[0]["top_passages"][0]["ref"] == "known_note#p0"


# ── evaluate() / report() ────────────────────────────────────────────────────

# Hand-worked confusion matrix, shared by every threshold test below:
#   entailment  label
#     0.9       True    (TP at every threshold <= 0.9)
#     0.2       False   (TN at every threshold above 0.2)
#     0.6       False   (the "false positive at 0.5" row)
#     0.4       True    (the "false negative at 0.5" row)
_LABELLED_SHEET = [
    {"entailment": 0.9, "label": True},
    {"entailment": 0.2, "label": False},
    {"entailment": 0.6, "label": False},
    {"entailment": 0.4, "label": True},
    {"entailment": 0.5, "label": None},  # unlabelled — must be excluded entirely
]


def test_evaluate_excludes_unlabelled_rows_from_n() -> None:
    result = calibrate.evaluate(_LABELLED_SHEET, thresholds=(0.5,))
    assert result[0].tp + result[0].fp + result[0].fn + result[0].tn == 4


def test_evaluate_at_threshold_0_5() -> None:
    """t=0.5: predicted-supported = {0.9, 0.6}; TP=1 (0.9/True), FP=1 (0.6/False),
    FN=1 (0.4/True), TN=1 (0.2/False) -> precision 0.5, recall 0.5, f1 0.5."""
    result = calibrate.evaluate(_LABELLED_SHEET, thresholds=(0.5,))[0]
    assert (result.tp, result.fp, result.fn, result.tn) == (1, 1, 1, 1)
    assert result.precision == 0.5
    assert result.recall == 0.5
    assert result.f1 == 0.5


def test_evaluate_at_threshold_0_3() -> None:
    """t=0.3: predicted-supported = {0.9, 0.6, 0.4}; TP=2 (0.9,0.4 both True),
    FP=1 (0.6/False), FN=0, TN=1 (0.2/False) -> precision 2/3, recall 1.0, f1 0.8."""
    result = calibrate.evaluate(_LABELLED_SHEET, thresholds=(0.3,))[0]
    assert (result.tp, result.fp, result.fn, result.tn) == (2, 1, 0, 1)
    assert result.precision == 2 / 3
    assert result.recall == 1.0
    assert result.f1 == 0.8


def test_evaluate_at_threshold_0_7() -> None:
    """t=0.7: predicted-supported = {0.9}; TP=1, FP=0, FN=1 (0.4/True),
    TN=2 (0.2, 0.6 both False) -> precision 1.0, recall 0.5, f1 2/3."""
    result = calibrate.evaluate(_LABELLED_SHEET, thresholds=(0.7,))[0]
    assert (result.tp, result.fp, result.fn, result.tn) == (1, 0, 1, 2)
    assert result.precision == 1.0
    assert result.recall == 0.5
    assert result.f1 == 2 / 3


def test_evaluate_threshold_boundary_is_inclusive() -> None:
    """(review C2) A score exactly EQUAL to the threshold must count as a positive
    prediction (`>=`, not `>`) and the complementary `<` (not `<=`) must not also claim
    it — a mutation flipping either comparison survives on `_LABELLED_SHEET` because no
    row there sits exactly on a tested threshold."""
    sheet = [{"entailment": 0.5, "label": True}]
    result = calibrate.evaluate(sheet, thresholds=(0.5,))[0]
    assert (result.tp, result.fp, result.fn, result.tn) == (1, 0, 0, 0)


def test_evaluate_with_no_positive_predictions_reports_zero_not_a_crash() -> None:
    """A threshold above every recorded entailment predicts nothing supported —
    precision is 0/0, and the honest value is 0.0, never a ZeroDivisionError."""
    result = calibrate.evaluate(_LABELLED_SHEET, thresholds=(0.99,))[0]
    assert result.tp == 0
    assert result.precision == 0.0
    assert result.recall == 0.0
    assert result.f1 == 0.0


def test_report_includes_the_labelled_count_and_excludes_the_unlabelled_row() -> None:
    text = calibrate.report(_LABELLED_SHEET, thresholds=(0.5,))
    assert "n labelled = 4 (of 5 sampled)" in text


def test_evaluate_can_rescore_with_a_different_model() -> None:
    """``--model`` re-scores every labelled claim against a second NLI, ignoring the
    recorded ``entailment`` entirely — proven here by a fake that disagrees with it."""
    sheet = [
        {
            "sentence": "s",
            "fragments": ["s"],
            "top_passages": [{"ref": "n#p0", "text": "premise text", "entailment": 0.1}],
            "entailment": 0.1,  # the OLD model's score — must be ignored when nli is given
            "label": True,
        }
    ]
    fake = FakeNLI(rules={("premise text", "s"): (0.0, 0.95, 0.05)})

    result = calibrate.evaluate(sheet, thresholds=(0.5,), nli=fake)[0]

    assert result.tp == 1  # 0.95 >= 0.5, not the recorded 0.1


def test_rescore_uses_the_max_entailment_across_pairs_not_the_min() -> None:
    """(review C4) Two premises for the same claim disagree sharply — one entailment
    low (0.05), one high (0.95). `_rescore` must report the MAX (0.95, so tp=1 at
    t=0.5): a mutation swapping `max` for `min` would report 0.05 instead and this
    threshold would then see zero positive predictions."""
    sheet = [
        {
            "sentence": "s",
            "fragments": ["s"],
            "top_passages": [
                {"ref": "n#p0", "text": "weak premise", "entailment": 0.0},
                {"ref": "n#p1", "text": "strong premise", "entailment": 0.0},
            ],
            "entailment": 0.0,
            "label": True,
        }
    ]
    fake = FakeNLI(
        rules={
            ("weak premise", "s"): (0.0, 0.05, 0.95),
            ("strong premise", "s"): (0.0, 0.95, 0.05),
        }
    )

    result = calibrate.evaluate(sheet, thresholds=(0.5,), nli=fake)[0]

    assert result.tp == 1


# ── sheet round trip ─────────────────────────────────────────────────────────


def test_write_and_load_sheet_round_trips(tmp_path: Path) -> None:
    rows = [{"sentence": "s", "label": None}]
    path = tmp_path / "sheet.json"

    calibrate.write_sheet(rows, path)
    loaded = calibrate.load_sheet(path)

    assert loaded == rows
