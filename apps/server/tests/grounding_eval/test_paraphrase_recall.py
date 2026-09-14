"""Recall over the HELD-OUT paraphrase probes — the half the alias pass cannot see.

``test_retrieval_recall.py``'s pinned set measured 18/18 = 100% the moment
``packages/knowledge/manifest.json`` grew aliases written for those exact phrasings —
a hand-tuned lexical match, not evidence retrieval understands meaning. These fourteen
probes (``paraphrase_probes.PARAPHRASE_PROBES``) are phrased to avoid every current
alias of their targets, so only meaning links them to a note; a change that only widens
the alias list cannot move this number, and a genuine embedding/ranking improvement is
exactly what would.

Measured 2026-09-14 at commit 3ba0c60 (the tip this file was written against — retrieval
itself is untouched by anyone as of this measurement): recall@6 = 10/14 = 0.714 (71.4%),
with four real misses: ``pp_dragging``, ``pp_shut_eye``, ``pp_espresso``, ``pp_desk_job``.
Deliberately NOT tuned into hits — a miss here is this test doing its job, and closing it
is what the next retrieval change is FOR (the same ratchet discipline as the pinned set's
own miss targets, one level higher: this time immune to an alias-only fix).
"""

from __future__ import annotations

import re

from tests.grounding_eval.paraphrase_probes import PARAPHRASE_PROBES
from tests.grounding_eval.recall import recall_at_k

from healthee.insights.manifest import all_notes
from healthee.insights.retrieval import DEFAULT_TOP_N, rank_notes

# The exact probe ids that hit @ DEFAULT_TOP_N, measured today (see module docstring).
# Moving in EITHER direction — losing a hit or gaining a new one — means retrieval (or
# the corpus) changed, and this pin must move with it DELIBERATELY: re-measure, update
# this frozenset, and say why in the commit. Do not "fix" a miss by rewording the probe;
# reword only if the wording itself turns out to leak an alias (checked below).
_PINNED_HITS: frozenset[str] = frozenset(
    {
        "pp_nightly_red",
        "pp_move_more",
        "pp_gym_today",
        "pp_ticker",
        "pp_hrv_spelled",
        "pp_snooze",
        "pp_overtraining",
        "pp_late_dinner",
        "pp_five_hours",
        "pp_grumpy_morning",
    }
)

# Named for the report: these four miss on today's ranker, on purpose (see module
# docstring) — the targets a genuine retrieval improvement (not another alias) should
# turn into hits.
_KNOWN_MISSES: frozenset[str] = frozenset(
    {"pp_dragging", "pp_shut_eye", "pp_espresso", "pp_desk_job"}
)


def _phrase_in_text(phrase: str, text: str) -> bool:
    """``phrase`` as a word-bounded, separator-insensitive match in ``text``.

    Deliberately a SEPARATE implementation from ``retrieval._alias_re`` rather than an
    import of it: these probes exist to be independent of that module's internals, and
    importing its private function would tie a held-out check to the very
    implementation the probes are meant to stay agnostic of. Same semantics on purpose
    (word boundaries, any run of non-alphanumerics matching any other) so "no alias
    leaks into a probe" means the same thing here as it does in production ranking.
    """
    parts = [re.escape(p) for p in re.split(r"[^a-z0-9]+", phrase.lower()) if p]
    if not parts:
        return False
    pattern = r"(?<!\w)" + r"[^a-z0-9]+".join(parts) + r"(?!\w)"
    return re.search(pattern, text.lower()) is not None


def test_every_probe_target_exists_in_the_manifest() -> None:
    known_ids = {note.id for note in all_notes()}
    for probe in PARAPHRASE_PROBES:
        for note_id in probe.expects_any_of:
            assert note_id in known_ids, (probe.id, note_id)


def test_probe_ids_are_unique() -> None:
    ids = [probe.id for probe in PARAPHRASE_PROBES]
    assert len(ids) == len(set(ids))


def test_every_probe_carries_at_least_one_expectation() -> None:
    """Unlike the paid set, a held-out probe with no expectation would score nothing —
    there is no out-of-domain analogue here, so an empty pin is always a mistake."""
    for probe in PARAPHRASE_PROBES:
        assert probe.expects_any_of, probe.id


def test_no_probe_leaks_a_current_alias_id_or_name_of_its_target() -> None:
    """The load-bearing check: only MEANING may link a probe to its note.

    Checked against the REAL manifest, not a snapshot, so a future alias addition that
    happens to match an existing probe's wording is caught here — as a failure telling
    the editor to reword the probe — rather than silently turning a meaning-only probe
    back into a spelling match.
    """
    notes_by_id = {note.id: note for note in all_notes()}
    violations: list[tuple[str, str, str]] = []
    for probe in PARAPHRASE_PROBES:
        for note_id in probe.expects_any_of:
            note = notes_by_id[note_id]
            for phrase in (note.id, note.name, *note.aliases):
                if _phrase_in_text(phrase, probe.text):
                    violations.append((probe.id, note_id, phrase))
    assert not violations, violations


def _print_probe_table(hits: dict[str, bool]) -> None:
    for probe in PARAPHRASE_PROBES:
        top = [n.id for n in rank_notes(probe.text, probe.metrics)[:DEFAULT_TOP_N]]
        mark = "HIT " if hits.get(probe.id) else "MISS"
        print(f"{mark}  {probe.id:20s} expects={probe.expects_any_of} top6={top}")


def test_paraphrase_recall_matches_the_pinned_baseline() -> None:
    """The regression gate for the held-out set — see module docstring for the number.

    Both directions fail: losing a pinned hit AND a miss unexpectedly starting to hit
    are equally "the pin no longer describes today's code" and both demand a deliberate,
    explained update rather than a silent drift.
    """
    rate, hits = recall_at_k(PARAPHRASE_PROBES, DEFAULT_TOP_N)
    hit_ids = frozenset(pid for pid, hit in hits.items() if hit)
    print(f"paraphrase recall@{DEFAULT_TOP_N} = {rate:.3f} ({len(hit_ids)}/{len(hits)})")
    if hit_ids != _PINNED_HITS:
        _print_probe_table(hits)
    assert hit_ids == _PINNED_HITS, (
        f"paraphrase recall moved — lost {_PINNED_HITS - hit_ids}, "
        f"gained {hit_ids - _PINNED_HITS}; update _PINNED_HITS deliberately if intended"
    )


def test_the_known_misses_are_exactly_the_unpinned_probes() -> None:
    """The four misses named in the module docstring are named ON PURPOSE, not left
    implicit as "everything not in _PINNED_HITS" — a probe added later with no opinion
    recorded either way would otherwise silently join this set unexamined."""
    all_ids = {probe.id for probe in PARAPHRASE_PROBES}
    assert all_ids - _PINNED_HITS == _KNOWN_MISSES
