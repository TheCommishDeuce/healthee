"""Answer capture (``records.py``/``runner.py``) and the offline ``score`` subcommand.

No network and no database: ``score_answer`` is always monkeypatched here, the same seam
the real ``support.py`` (built separately, see its module docstring) is designed for. This
file is the reason two arms can be READ, not only counted — the harness's own stated gap.
The report/stats lines ``score`` unlocks are tested separately in ``test_score_report.py``
(this file was pushing the 400-line gate).
"""

from __future__ import annotations

import json
from pathlib import Path
from uuid import uuid4

import pytest
from tests.grounding_eval import questions as qs
from tests.grounding_eval import records as records_mod
from tests.grounding_eval import runner as runner_mod
from tests.grounding_eval.__main__ import main
from tests.grounding_eval.meter import MeteredClient
from tests.grounding_eval.records import ERROR, FALLBACK, GROUNDED, EvalRun, RunRecord
from tests.grounding_eval.support import ClaimSupport, SupportScore

from healthee.insights.client import ChatResponse, Usage
from healthee.insights.coach import CoachResult
from healthee.insights.grounded import GroundedResult


class _FakeInner:
    """An LLM that returns a scripted list of responses (usage included)."""

    def __init__(self, responses: list[ChatResponse]) -> None:
        self._responses = responses
        self.calls = 0

    def complete(  # noqa: ARG002
        self, messages: list[dict], *, tools=None, model=None, response_format=None
    ) -> ChatResponse:
        response = self._responses[min(self.calls, len(self._responses) - 1)]
        self.calls += 1
        return response


# ── recording the answer text (records.py / runner.py) ───────────────────────────────


def test_an_old_shape_record_dict_still_loads_with_defaults(tmp_path: Path) -> None:
    """A minimal record dict from before ``answer``/``support_*`` existed must still load."""
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

    record = run.records[0]
    assert record.answer == ""
    assert record.grade_floor == ""
    assert record.cached_prompt_tokens == 0
    assert record.support_claims == 0
    assert record.support_cited == 0
    assert record.support_supported == 0
    assert record.support_threshold == 0.0
    assert record.support_unsupported == []
    assert record.support_model == ""


@pytest.mark.usefixtures("env")
def test_run_one_stores_the_answer_text_and_grade_floor(monkeypatch: pytest.MonkeyPatch) -> None:
    """The whole point: a saved arm can be READ, not only counted."""

    def fake_ask(question, user_id, tz, client):  # noqa: ARG001 — matches `_ask`'s signature
        return (GROUNDED, ["k_alcohol"], [], "the verbatim answer text", "Probable")

    monkeypatch.setattr(runner_mod, "_ask", fake_ask)
    client = MeteredClient(_FakeInner([ChatResponse(text="x", usage=Usage(1, 1, 0))]))
    question = qs.QUESTIONS[0]

    record = runner_mod._run_one(question, 0, uuid4(), "UTC", client)

    assert record.answer == "the verbatim answer text"
    assert record.grade_floor == "Probable"


@pytest.mark.usefixtures("env")
def test_run_one_on_error_leaves_answer_and_grade_floor_blank_not_guessed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A transport failure must not fabricate an answer that was never produced."""

    def raising_ask(question, user_id, tz, client):  # noqa: ARG001
        raise RuntimeError("boom")

    monkeypatch.setattr(runner_mod, "_ask", raising_ask)
    client = MeteredClient(_FakeInner([ChatResponse(text="x", usage=Usage(1, 1, 0))]))
    question = qs.QUESTIONS[0]

    record = runner_mod._run_one(question, 0, uuid4(), "UTC", client)

    assert record.answer == ""
    assert record.grade_floor == ""
    assert record.error.startswith("RuntimeError")


def test_ask_reads_the_coach_answer_from_reply_not_text(monkeypatch: pytest.MonkeyPatch) -> None:
    """Exercises the REAL ``_ask`` body — not ``_run_one`` copying an already-built tuple.

    ``CoachResult`` has no ``.text`` attribute; the answer is ``.reply``. A regression
    that read the wrong (nonexistent, or blank) field must fail here, not just when
    ``_ask`` itself is stubbed out.
    """
    fake_result = CoachResult(
        reply="the real coach reply",
        citations=["k_alcohol"],
        grade_floor="Probable",
        tool_calls=[{"tool": "get_metric"}],
        refused=False,
        validated=True,
    )
    monkeypatch.setattr(runner_mod, "run_coach", lambda *args, **kwargs: fake_result)
    question = next(q for q in qs.QUESTIONS if q.surface == "coach")
    client = MeteredClient(_FakeInner([ChatResponse(text="x", usage=Usage(1, 1, 0))]))

    outcome, citations, tools, answer, grade_floor = runner_mod._ask(
        question, uuid4(), "UTC", client
    )

    assert answer == "the real coach reply"
    assert grade_floor == "Probable"
    assert citations == ["k_alcohol"]
    assert tools == ["get_metric"]


def test_ask_reads_the_grounded_answer_from_text(monkeypatch: pytest.MonkeyPatch) -> None:
    """The non-conversational surface's result carries ``.text``, not ``.reply``."""
    fake_result = GroundedResult(
        text="the real grounded text",
        citations=["k_alcohol"],
        grade_floor="Established",
        refused=False,
        validated=True,
    )
    monkeypatch.setattr(runner_mod, "grounded_ask", lambda *args, **kwargs: fake_result)
    question = next(q for q in qs.QUESTIONS if q.surface == "grounded")
    client = MeteredClient(_FakeInner([ChatResponse(text="x", usage=Usage(1, 1, 0))]))

    outcome, citations, tools, answer, grade_floor = runner_mod._ask(
        question, uuid4(), "UTC", client
    )

    assert answer == "the real grounded text"
    assert grade_floor == "Established"
    assert tools == []


# ── the `score` subcommand ────────────────────────────────────────────────────────────


def _rec(qid: str, *, outcome: str = GROUNDED, answer: str = "") -> RunRecord:
    return RunRecord(
        question_id=qid,
        kind=qs.KNOWLEDGE,
        surface="coach",
        repeat=0,
        outcome=outcome,
        success=(outcome == GROUNDED),
        answer=answer,
    )


def _arm(records: list[RunRecord], label: str = "arm") -> EvalRun:
    return EvalRun(
        label=label,
        commit="abc1234",
        question_set="fp",
        repeats=1,
        started_at="2026-01-01T00:00:00+00:00",
        records=records,
    )


def _fake_score_answer_factory(threshold_seen: list[float]):
    def fake_score_answer(text: str, *, threshold: float = 0.5, nli=None) -> SupportScore:  # noqa: ARG001
        threshold_seen.append(threshold)
        return SupportScore(
            claims=3,
            cited_claims=2,
            supported=1,
            threshold=threshold,
            details=(
                ClaimSupport("s1 supported", ("k_alcohol",), "k_alcohol", 0.9, 0.0, True),
                ClaimSupport("s2 not supported", ("k_alcohol",), "k_alcohol", 0.2, 0.1, False),
            ),
        )

    return fake_score_answer


def _patch_support(monkeypatch: pytest.MonkeyPatch, threshold_seen: list[float] | None = None):
    """Patch the module attribute ``score`` looks up at call time — not a rebound name."""
    import tests.grounding_eval.support as support_module

    if threshold_seen is None:
        threshold_seen = []
    monkeypatch.setattr(support_module, "score_answer", _fake_score_answer_factory(threshold_seen))


def test_score_leaves_non_grounded_records_untouched_and_zero(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """A fallback/refused record ships REAL text — the honest fallback sentence or the
    refusal template, never empty — so the guard must key on ``outcome``, not on whether
    ``answer`` happens to be blank. The scorer explodes if it is ever called here.
    """

    def explode(text: str, *, threshold: float = 0.5, nli=None):  # noqa: ARG001
        raise AssertionError("score_answer must never be called for a non-grounded record")

    import tests.grounding_eval.support as support_module

    monkeypatch.setattr(support_module, "score_answer", explode)

    arm_path, out_path = tmp_path / "arm.json", tmp_path / "arm.scored.json"
    records_mod.save(
        _arm(
            [
                _rec("a", outcome=FALLBACK, answer="the honest fallback sentence, shipped."),
                _rec("b", outcome=ERROR, answer=""),
            ]
        ),
        arm_path,
    )

    assert main(["score", str(arm_path), "--out", str(out_path)]) == 0

    scored = records_mod.load(out_path)
    assert all(r.support_threshold == 0.0 for r in scored.records)
    assert all(r.support_claims == 0 for r in scored.records)


def test_score_counts_and_reports_empty_answer_records(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    """A grounded record with no answer predates capture — counted, never guessed at."""
    _patch_support(monkeypatch)
    arm_path, out_path = tmp_path / "arm.json", tmp_path / "arm.scored.json"
    records_mod.save(
        _arm([_rec("a", answer=""), _rec("b", answer=""), _rec("c", answer="has text")]),
        arm_path,
    )

    main(["score", str(arm_path), "--out", str(out_path)])

    out = capsys.readouterr().out
    assert "2 records have no answer text (arm predates answer capture)" in out
    scored = records_mod.load(out_path)
    by_id = {r.question_id: r for r in scored.records}
    assert by_id["a"].support_claims == 0
    assert by_id["c"].support_claims == 3


def test_score_never_overwrites_the_input_file(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    _patch_support(monkeypatch)
    arm_path, out_path = tmp_path / "arm.json", tmp_path / "arm.scored.json"
    original = _arm([_rec("a", answer="text")])
    records_mod.save(original, arm_path)
    before = arm_path.read_text(encoding="utf-8")

    main(["score", str(arm_path), "--out", str(out_path)])

    assert arm_path.read_text(encoding="utf-8") == before
    assert out_path.exists()


def test_score_fills_support_fields_from_a_grounded_answer(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    _patch_support(monkeypatch)
    arm_path, out_path = tmp_path / "arm.json", tmp_path / "arm.scored.json"
    records_mod.save(_arm([_rec("a", answer="the model's answer")]), arm_path)

    main(["score", str(arm_path), "--out", str(out_path)])

    record = records_mod.load(out_path).records[0]
    assert record.support_claims == 3
    assert record.support_cited == 2
    assert record.support_supported == 1
    assert record.support_threshold == 0.5
    assert record.support_unsupported == ["s2 not supported"]


def test_score_passes_the_threshold_through(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    seen: list[float] = []
    _patch_support(monkeypatch, seen)
    arm_path, out_path = tmp_path / "arm.json", tmp_path / "arm.scored.json"
    records_mod.save(_arm([_rec("a", answer="text")]), arm_path)

    main(["score", str(arm_path), "--out", str(out_path), "--threshold", "0.7"])

    assert seen == [0.7]


def test_score_sets_the_support_model_from_env(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    _patch_support(monkeypatch)
    monkeypatch.setenv("HEALTHEE_SUPPORT_MODEL", "some/nli-model")
    arm_path, out_path = tmp_path / "arm.json", tmp_path / "arm.scored.json"
    records_mod.save(_arm([_rec("a", answer="text")]), arm_path)

    main(["score", str(arm_path), "--out", str(out_path)])

    assert records_mod.load(out_path).records[0].support_model == "some/nli-model"
