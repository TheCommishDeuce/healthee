"""The twelve ``intent`` questions — split out of ``questions.py`` to stay under the
400-line file gate. See ``questions.py``'s module docstring for what the kind means and
why it is opt-in; this file is just the data.

Plain-intent phrasing, no metric name, no note id, no alias in the text — the way an
owner actually types. Each comment names the retrieval weakness the question probes: the
vocabulary gap a lexically-anchored question never exposes.
"""

from __future__ import annotations

from tests.grounding_eval.question_types import INTENT, EvalQuestion

INTENT_QUESTIONS: tuple[EvalQuestion, ...] = (
    EvalQuestion(
        # probes: no "recovery"/"readiness" — c_train_today asks the same thing but
        # names both outright.
        # MISS on today's code — retrieval hands this specificity/polarized-training/
        # critical-speed notes, never recovery_readiness.
        id="i_train_or_rest",
        kind=INTENT,
        surface="coach",
        text="Should I push hard in my workout today, or would I be better off taking it easy?",
        expects_any_of=("recovery_readiness",),
    ),
    EvalQuestion(
        # probes: a vague symptom with no sleep/recovery vocabulary anywhere in it.
        # MISS on today's code — none of caffeine/critical-speed/environmental-stress/
        # fueling/morning-light/specificity is a sleep-need or readiness note.
        id="i_tired",
        kind=INTENT,
        surface="coach",
        text="I've been feeling wiped out for the past few days — any idea why?",
        expects_any_of=("sleep_need_debt", "sleep_and_recovery", "recovery_readiness"),
    ),
    EvalQuestion(
        # probes: "nap" (verb), not the note id "napping" — does the colloquial singular
        # still retrieve it?
        id="i_nap",
        kind=INTENT,
        surface="coach",
        text="Would it be a bad idea for me to nap this afternoon?",
        expects_any_of=("napping",),
    ),
    EvalQuestion(
        # probes: "HRV" is what an owner actually types — not the note id
        # "heart_rate_variability" or the metric "hrv_sleep_avg".
        id="i_hrv_worried",
        kind=INTENT,
        surface="coach",
        text="My HRV numbers have been sliding lately — is that something to worry about?",
        expects_any_of=("heart_rate_variability",),
    ),
    EvalQuestion(
        # probes: no "sleep score"/"sleep efficiency" — a plain quality judgment.
        id="i_good_sleep",
        kind=INTENT,
        surface="coach",
        text="Was last night actually a good night's sleep for me?",
        expects_any_of=("sleep_and_recovery",),
    ),
    EvalQuestion(
        # probes: zero metric anchor at all — nothing for lexical retrieval to key on.
        # No expectation: this spans sleep, activity and recovery equally, so there is
        # no single note (or small id set) a correct retrieval would be judged against —
        # forcing one here would just be a second, arbitrary opinion about what "one
        # change" means, not a recall target.
        id="i_one_change",
        kind=INTENT,
        surface="coach",
        text="If I could only change one thing this week to feel better, what should it be?",
    ),
    EvalQuestion(
        # probes: "drinks", not "alcohol" — the note is titled alcohol_sleep.
        # MISS on today's code — retrieval hands this specificity/illness-flag/recovery-
        # readiness notes, never alcohol_sleep itself.
        id="i_drinks_recovery",
        kind=INTENT,
        surface="coach",
        text=(
            "I've been having a couple of drinks most evenings — is that messing with my recovery?"
        ),
        expects_any_of=("alcohol_sleep",),
    ),
    EvalQuestion(
        # probes: "walk", not "steps" — every shipped metric name here is steps_*.
        # MISS on today's code — retrieval hands this napping/cadence/injury notes,
        # never a steps-or-MVPA mortality note.
        id="i_walking_worth",
        kind=INTENT,
        surface="coach",
        text="Would it actually do my health any good to walk more?",
        expects_any_of=("steps_mortality", "mvpa_minutes_mortality"),
    ),
    EvalQuestion(
        # probes: "pulse", not "resting heart rate" / "rhr" — same quantity, different word.
        id="i_pulse_healthy",
        kind=INTENT,
        surface="coach",
        text="Does my resting pulse look healthy to you?",
        expects_any_of=("resting_heart_rate",),
    ),
    EvalQuestion(
        # probes: a comparison naming no subject at all — which metric, if any, answers it?
        # No expectation, deliberately: there is no note that answers "compare my own
        # months" — that is a personal-data comparison the coach's tools would compute,
        # not a corpus claim, so no manifest id would make retrieval "right" here.
        id="i_month_compare",
        kind=INTENT,
        surface="coach",
        text="How does this past month stack up against the one before it?",
    ),
    EvalQuestion(
        # probes: "a few hours", not "sleep duration" or a number of hours as data.
        id="i_short_night",
        kind=INTENT,
        surface="coach",
        text="I only got a few hours of sleep last night — should I be worried about that?",
        expects_any_of=("sleep_and_recovery", "sleep_need_debt", "sleep_duration_mortality"),
    ),
    EvalQuestion(
        # probes: the plainest phrasing of the shipped sleep-tonight surface's own
        # territory, asked of the free-form coach instead of the fixed prompt.
        id="i_sleep_tonight_plain",
        kind=INTENT,
        surface="coach",
        text="What can I actually do to sleep better tonight?",
        expects_any_of=("sleep_and_recovery",),
    ),
)
