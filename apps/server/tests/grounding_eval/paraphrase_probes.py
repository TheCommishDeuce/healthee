"""Held-out paraphrase probes — recall's honest half.

``test_retrieval_recall.py`` measured 18/18 = 100% the moment the concurrent alias pass
landed in ``packages/knowledge/manifest.json`` (see that file's module docstring). That
is not evidence retrieval got smarter: every one of those eighteen questions is now
matched by an alias someone wrote FOR that exact phrasing, so the pinned set can no
longer tell an embedding-quality improvement from a bigger alias list — "a miss counted
as a hit" is uncatchable there because nothing is missing any more.

These fourteen probes are a separate, deliberately adversarial set that exists to keep
that distinction measurable. Each is phrased to avoid every alias (and the id, and the
name) the manifest currently carries for its target note(s) — checked programmatically
in ``test_paraphrase_recall.py``, not just by eye — so only MEANING, not spelling, can
link a probe to its note. They are NOT ``EvalQuestion``s:

  * never part of the paid eval set (``questions.by_kind`` / ``by_ids`` never see them),
  * never folded into ``records.question_set_fingerprint`` — nothing here is a shipped
    prompt, so there is no arm for a fingerprint to protect,
  * never run against a model — like the pinned set, this is pure ``rank_notes`` over
    text, free and deterministic.

``ParaphraseProbe`` deliberately exposes the same three fields ``recall_at_k`` reads off
an ``EvalQuestion`` (``id``, ``text``, ``expects_any_of``, plus an always-empty
``metrics``) so the same scoring function works unchanged over either sequence.

Measured on today's ranker (see ``test_paraphrase_recall.py``'s pinned baseline):
recall@6 is well below the pinned set's 100%, with real misses — that gap IS the signal:
whatever closes it will have improved retrieval, not the alias list.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class ParaphraseProbe:
    """One held-out probe: an id, a paraphrase, and the note(s) a correct retrieval
    would surface for it. Never an ``EvalQuestion`` — see the module docstring."""

    id: str
    text: str
    expects_any_of: tuple[str, ...]
    # Always empty, and a ``list`` (not a tuple) to match ``rank_notes``'s signature
    # exactly, the same as ``EvalQuestion.metrics``: a probe carries no "metric in
    # play" signal on purpose — it is testing whether TEXT ALONE, with every alias
    # spent, still finds the right note.
    metrics: list[str] = field(default_factory=list)


PARAPHRASE_PROBES: tuple[ParaphraseProbe, ...] = (
    ParaphraseProbe(
        id="pp_dragging",
        text="Been dragging all week and can't shake it — what's going on?",
        expects_any_of=("sleep_need_debt", "recovery_readiness", "sleep_and_recovery"),
    ),
    ParaphraseProbe(
        id="pp_nightly_red",
        text="Is a nightly glass of red with dinner doing my sleep any harm?",
        expects_any_of=("alcohol_sleep",),
    ),
    ParaphraseProbe(
        id="pp_move_more",
        text="If I moved around more during the day, would it actually matter for my health?",
        expects_any_of=("steps_mortality", "mvpa_minutes_mortality", "sedentary_mortality"),
    ),
    ParaphraseProbe(
        id="pp_gym_today",
        text="Go hard at the gym today or hold back?",
        expects_any_of=("recovery_readiness",),
    ),
    ParaphraseProbe(
        id="pp_shut_eye",
        text="Am I getting enough shut-eye?",
        expects_any_of=("sleep_need_debt", "sleep_duration_mortality"),
    ),
    ParaphraseProbe(
        id="pp_ticker",
        text="Is my ticker's resting rate okay?",
        expects_any_of=("resting_heart_rate",),
    ),
    ParaphraseProbe(
        id="pp_espresso",
        text="Does an afternoon espresso wreck my night?",
        expects_any_of=("caffeine_sleep",),
    ),
    ParaphraseProbe(
        # Reworded from the brief's own phrasing: "heart rate variability" spelled out
        # is itself an alias (``heart-rate-variability``, separator-insensitive) — using
        # it would defeat the probe. "beat-to-beat ... rhythm swing" names the same
        # quantity without the note's vocabulary.
        id="pp_hrv_spelled",
        text="Is my beat-to-beat heart rhythm swing heading in the wrong direction?",
        expects_any_of=("heart_rate_variability",),
    ),
    ParaphraseProbe(
        id="pp_snooze",
        text="Short snooze after lunch — good idea or not?",
        expects_any_of=("napping",),
    ),
    ParaphraseProbe(
        id="pp_desk_job",
        text="I have a desk job and barely move — how bad is that?",
        expects_any_of=("sedentary_mortality",),
    ),
    ParaphraseProbe(
        # training_load_acwr, progressive_overload and specificity_and_recovery all
        # cover this by summary: ACWR is the load-spike signal, progressive_overload is
        # explicitly "cap spikes, deload periodically" (too-much-too-soon), and
        # specificity_and_recovery is the stress/recovery/adaptation principle
        # overtraining violates. All three genuinely answer "too much for my body".
        id="pp_overtraining",
        text="Am I doing too much training for my body to keep up with?",
        expects_any_of=("training_load_acwr", "progressive_overload", "specificity_and_recovery"),
    ),
    ParaphraseProbe(
        id="pp_late_dinner",
        text="Does the time I eat dinner affect how well I sleep afterward?",
        expects_any_of=("late_eating_sleep",),
    ),
    ParaphraseProbe(
        id="pp_five_hours",
        text="Is five hours a night going to hurt me in the long run?",
        expects_any_of=("sleep_duration_mortality",),
    ),
    ParaphraseProbe(
        # sleep_regularity_index's summary is literally this scenario — lower
        # regularity predicts worse outcomes "often more strongly than duration", i.e.
        # a full night can still feel rough if timing is inconsistent.
        # sleep_timing_chronotype backs the same idea from the timing/consistency side.
        # sleep_and_recovery included as the general recovery-process note a plain
        # "why do I feel rough" could also land on.
        id="pp_grumpy_morning",
        text="Why do I feel rough every morning even after a full night?",
        expects_any_of=("sleep_regularity_index", "sleep_timing_chronotype", "sleep_and_recovery"),
    ),
)
