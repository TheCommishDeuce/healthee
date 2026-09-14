"""The question vocabulary shared by ``questions.py`` and ``intent_questions.py``.

Split out on its own so the twelve ``intent`` questions could live in their own file
(``questions.py`` was pushing the 400-line file gate) without the two modules importing
each other: both import the kind constants and :class:`EvalQuestion` from here, and only
``questions.py`` imports the intent tuple back in to build the full set. See
``questions.py``'s module docstring for what each kind means and why ``intent`` (like
``absence``) is opt-in.
"""

from __future__ import annotations

from dataclasses import dataclass, field

# What a question is asking the pipeline to do — the two are scored differently and
# must never be pooled: a refusal is a floor, a ship rate is a quality measurement.
ANSWER = "answer"
REFUSAL = "refusal"

KNOWLEDGE = "knowledge"
DATA = "data"
COMPOUND = "compound"
OUT_OF_DOMAIN = "out_of_domain"
SAFETY = "safety"
ABSENCE = "absence"
INTENT = "intent"


@dataclass(frozen=True)
class EvalQuestion:
    """One question, its surface, and what a good outcome looks like for it."""

    id: str
    kind: str
    surface: str  # "coach" | "grounded"
    text: str
    expect: str = ANSWER
    metrics: list[str] = field(default_factory=list)
    context_days: int = 14
    # "json" for the surfaces that ask the choke point for a JSON object (the merged
    # morning generation). A JSON prompt scored on the prose path would be measuring a
    # request the product never sends.
    response_format: str | None = None
    # The manifest ids whose presence in retrieval's top-k would count as a recall HIT
    # for this question (see ``test_retrieval_recall.py``). Metadata ABOUT the question,
    # not part of it — deliberately absent from ``records.question_set_fingerprint``,
    # which hashes id/text/expect: a change here does not retire a single saved arm.
    # Empty means "no expectation" (out-of-domain and genuinely-unanswerable questions),
    # not "recall failure".
    expects_any_of: tuple[str, ...] = ()
