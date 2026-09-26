# packages/knowledge — the evidence base

> **Frozen 2026-09-26.** Not edited here any more; the maintained copy of this corpus is
> `knowledge/` in [TheCommishDeuce/strap](https://github.com/TheCommishDeuce/strap) (its decision D16).

Everything interpretive Healthee says must trace to a note in this package.
Two collections, one destination format:

## `sports-science/` — imported corpus (the target standard)

~29 docs (metrics / principles / wellness) imported 2026-07-15 from the daud
project's knowledge layer. **Its conventions are the standard this whole
package converges on** (see `sports-science/METHODOLOGY.md` and
`ENGINEERING_STANDARDS.md` §4):

- per-claim evidence grades with calibrated language
  (Established · Probable · Emerging · Contested · Myth/Refuted)
- citations real or absent — verified primary sources only
- mandatory Honesty section (confounders, individual variation, limits)
- a Coach Directives block per doc. A directive becomes a hard guardrail the LLM
  cannot override **only** when its note declares it (`safety_critical: [5, 6]` in
  frontmatter) and a rule for it exists in `insights/guard_directives.py`; a test
  asserts the two match, both ways (#87). Writing "mirrored as a guardrail" in prose
  never made it one, and ~24 notes used to do exactly that
- docs follow `sports-science/TEMPLATE.md`; `COACHING-RULES.md` is the
  cross-cutting directives digest

Provenance note: imported from a running-focused coach, so some directives are
runner-specific — generalize on use, don't apply blindly. The original
`README.md`'s "Maps to `@daud/core`" column refers to that project's compute
layer; Healthee's equivalents live in `apps/server/src/healthee/derive`.

## `notes/` — the Healthee corpus

The notes carried over from the legacy repo and since unified (activity, sleep, hrv,
metrics, recovery, intake, meditation, recs, protocol). **49 are citable**; the five
under `notes/protocol/` carry no `id` and `gen_manifest.py` skips them as engineering
reference rather than evidence.

*(Corrected 2026-09-08. This section described a corpus that no longer exists: "55
notes … written to the older convention (numeric grades: 3 (★★★) → Established …; **no
Honesty/Directives sections yet**). Phase 5 migrates these to the template above."
That migration happened. Every citable note now carries a string `grade`, a
`## Honesty & uncertainty` section, a `## Coach Directives` block and a
`## Healthee implementation & honesty policy` section — verified by structural scan.
The numeric `evidence_grade` was removed in #83 and `make knowledge` rejects a note
that reintroduces it. A README that tells a reader the Honesty sections do not exist
is a README that tells them not to look for one.)*

## Unified frontmatter schema

Both collections normalize to one record shape. Authored frontmatter differs
per collection (see below); the generator maps both onto these fields:

| Field | Legacy source (`notes/`) | Sports-science source |
|---|---|---|
| `id` | `id` (already snake_case) | `id` (snake_case, e.g. `heart_rate_zones`) |
| `name` | `topic` (→ `title` → `id`) | `name` |
| `category` | parent directory | parent directory (`metrics`/`principles`/`wellness`) |
| `grade` | `grade` — one vocabulary, both collections (see below) | `grade` (Established/Probable/Emerging/Contested/Myth/Refuted) |
| `summary` | `topic`/`title`, else first body line | `summary` (one line) |
| `aliases` | `tags` | original hyphenated slug + existing synonyms |
| `applies_to_metrics` | `applies_to_metrics` | mapped per `docs/INTELLIGENCE.md` §7.1 (`[]` if not-yet-computed) |
| `applies_to_interventions` | `applies_to_interventions` | where natural (e.g. `strength`, `sauna`, `heat`) |
| `population` | — | `runners` on runner-specific docs |
| `last_reviewed` | `last_reviewed` (optional) | `last_reviewed` (optional) |

Sports-science docs also keep `related` and `units` as provenance; the manifest
ignores them. **`daud_metrics` is gone (#100.)** It carried the origin project's
compute-fn names — never Healthee metrics — and 13 of 18 notes had already dropped
it, recording the drop in prose; the 5 stragglers are now aligned. A frontmatter key
naming functions in a module that exists in no repo reads as a live mapping to
anyone skimming the block, which is the same false-provenance failure #83b and #87
were about. The names survive where they belong: in the notes' implementation
sections, labelled as upstream import provenance. Ids must match `[a-z0-9_]+` (the citation regex) or they
are uncitable. Notes in `notes/protocol/` carry no `id` and are skipped as
non-citable engineering references (surfaced, not silently dropped).

### One grade per note (#83, 2026-08-01)

`grade` is the single source of truth in **both** collections. Notes used to carry
a second numeric `evidence_grade` field described as a "mirror" of it. It was not a
mirror: the two could disagree, and which one the manifest published depended on the
note's directory — `notes/` was built from `evidence_grade` (its authored `grade` was
ignored), and `sports-science/` did the exact reverse (its `evidence_grade` was dead
metadata in 27 notes). A `notes/` note authored `grade: Myth` with
`evidence_grade: 3` would therefore have shipped as **Established**, and that string
is what `insights/validator.py` reads to decide whether a claim may be stated plainly
and what `MIN_ACTIONABLE_RANK` consults before letting a note drive a recommendation.
The numeric field also could not express `Contested` or `Myth` at all.

`make knowledge` now **fails** on any note that carries `evidence_grade`. Code that
needs a numeric rank derives it from the string in `insights/manifest.py::GRADE_RANK`
(the one definition, and the only one that can express Contested → 1, Myth → 0).
Removing the field left `manifest.json` and `research_summaries.json` **byte-identical**
— no note's published grade changed, only the ability to write down a disagreement.

## Manifest (generated)

`tools/gen_manifest.py` parses every doc in both collections, validates the
whole corpus (duplicate id across collections, id format, unknown grade, and
missing required fields each fail loudly with the file listed), and writes two
**generated, never-hand-edited** artifacts:

- `manifest.json` — full records, for server retrieval.
- `research_summaries.json` — compact `{id, name, grade, summary,
  applies_to_metrics}`, for the bundled mobile asset.

Output is deterministic (sorted, no timestamps) so regeneration is diff-stable.

```
make knowledge        # regenerate both artifacts
make knowledge-check  # fail if the committed files are stale / hand-edited (CI runs this)
```

The generator uses PyYAML (declared in `apps/server`'s dev group), so it runs
under that environment: `cd apps/server && uv run python
../../packages/knowledge/tools/gen_manifest.py`. Current corpus: 76 records
(46 legacy evidence notes + 30 sports-science docs).
