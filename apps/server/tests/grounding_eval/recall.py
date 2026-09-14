"""Retrieval recall@k — a free, deterministic number, no model or DB required.

``rank_notes`` (``healthee.insights.retrieval``) is a pure function over the corpus
manifest and a question string: no network, no database. That makes note-level recall
computable directly from the fixed question set's ``expects_any_of`` pins, so a
retrieval change can be judged for free instead of only through a paid eval arm (see
``test_retrieval_recall.py``, which pins today's measured numbers).
"""

from __future__ import annotations

from collections.abc import Sequence

from tests.grounding_eval.question_types import EvalQuestion

from healthee.insights.retrieval import rank_notes


def recall_at_k(questions: Sequence[EvalQuestion], k: int) -> tuple[float, dict[str, bool]]:
    """Note-level recall@k over every question in ``questions`` that carries a pin.

    A question is a HIT if any of its ``expects_any_of`` ids appears in the top-``k``
    of ``rank_notes(question.text, question.metrics)``. A question with no pin (empty
    ``expects_any_of``) contributes to neither the count nor the rate — that is "no
    expectation", not "recall failure" (``o_stock``, ``o_protein``, ``i_month_compare``,
    ``i_one_change``).

    Returns ``(0.0, {})`` when none of ``questions`` carries a pin, rather than raising
    on a division by zero — a caller sweeping an unfiltered question set should see an
    honest "nothing measured here", not a crash.
    """
    hits: dict[str, bool] = {}
    for question in questions:
        if not question.expects_any_of:
            continue
        top_ids = {note.id for note in rank_notes(question.text, question.metrics)[:k]}
        hits[question.id] = bool(top_ids & set(question.expects_any_of))
    if not hits:
        return 0.0, hits
    return sum(hits.values()) / len(hits), hits
