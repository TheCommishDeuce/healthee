# Healthee — Intelligence & Grounding Design

How metrics show up on device, how they sync, how data is run against the
knowledgebase, and how the coach produces answers grounded in research.
Based on a full audit of the legacy implementation (2026-07-15); the audit
findings are preserved in §5–§7 so nothing gets lost.

---

## 1 · The device loop — how every number reaches the user

```
06:30  strap sync (BLE) → local store (60d samples, 400d sessions+dailies)
       → device analytics: provisional recovery, baselines, trends, confidence
       → UI renders INSTANTLY — value + personal baseline band + trend arrow
         + confidence chip + one-line grounded "why" from the bundled
         research_summaries.json          (origin tag: provisional)
       → push POST /ingest/helio → server derives canonical, runs analytics
       → GET /api/sync/down reconciles → provisional values replaced
         (drift beyond tolerance is logged, never hidden)
       → LLM surfaces (insight cards, coach, daily action) are server-generated,
         cached per day, always date-stamped; offline shows last cached text
         clearly marked stale — never presented as fresh
```

Rules:
- **Metric card anatomy is standardized**: every card shows value, personal
  baseline band, trend, confidence (coverage — §3.1's definition, the same one the
  server publishes as response metadata; freshness; origin), and a grounded
  "why" line citing a note id. Tapping ⓘ renders the knowledge note itself
  (plain-language + Honesty section) — one source of truth; no hardcoded card
  copy that can drift from the research.
- Interpretation (LLM text) is server-only. Evidence display works fully
  offline via the bundled summaries.
- Device never invents numbers: what it can't compute locally it labels
  "awaiting sync", not a guess.

## 2 · The knowledge platform (`packages/knowledge`)

- **Every doc gets frontmatter**: snake_case `id` (sports-science docs need ids
  + aliases added — see §7 migration), `name`, `category`, unified evidence
  grade (Established / Probable / Emerging / Contested / Myth; legacy numeric
  maps 3→Established, 2→Probable), `applies_to_metrics`,
  `applies_to_interventions`, one-line `summary`, `directives` with
  `safety_critical` flags, `last_reviewed`.
- **Generated manifest** (`make knowledge`): one build step emits
  `manifest.json` (server retrieval index) and `research_summaries.json`
  (mobile asset). Generated, never hand-edited.
- **Safety-critical directives compile into a hard-guardrail table** loaded by
  server code — deterministic checks the LLM can never override (bone-stress /
  REDs hard stop, never advise through chest pain, never advise sleep
  restriction…).
  > **Status — both halves are now live (#87, 2026-08-01).** *Enforcement:*
  > `insights/output_guard.py` blocks regardless of citations or validation (§3),
  > covering exactly the examples above, from a hand-compiled `_DOCUMENTED_RULES`
  > table where each rule cites the **doc line** that forbids it. *Compilation:* a
  > note declares a directive hard with `safety_critical: [5, 6]` in frontmatter;
  > `gen_manifest.py` refuses a marker that points at a directive which does not
  > exist or does not say `SAFETY-CRITICAL` in its own text;
  > `insights/guard_directives.py` compiles one blocking rule per marker; and
  > `tests/insights/test_guard_directives.py` asserts a **bijection** between the
  > markers and the rules, in both directions. `output_guard.output_rules()` is the
  > seam and returns both tables.
  >
  > The corpus is marked up **deliberately sparsely** — four directives today
  > (`napping` D5, `hydration_everyday` D5/D6, `late_eating_sleep` D5), each a case
  > where the wrong answer has a plausible path to real harm. Marking a directive is
  > research judgement and every marker costs a reviewed regex; an over-broad safety
  > filter that eats honest cited science is its own harm. What has changed is that
  > an *unmarked* note may no longer pretend otherwise: ~24 notes used to assert
  > "mirrored as a hard guardrail in `@daud/core`, the AI may not override" about a
  > module that exists in no repo, and those sentences now say what is true.
- Template (adopted from sports-science METHODOLOGY): mandatory Honesty
  section (confounders, individual variation, metric limits), Coach Directives
  block, citations real-or-absent with primary sources verified before writing.

## 3 · The grounded-ask choke point (server)

Every LLM surface is held to ONE pipeline — and since the coach was collapsed onto
it (#46) that is now literally one body of code, not two that agree: the stages
below live in **`insights/pipeline.py`**, and both entry points run them. The
non-conversational surfaces enter through `grounded_ask` (`grounded.py`); the coach
enters through `run_coach` (`coach.py`). Each contributes only its message layout
and its turn shape; neither owns a stage. The surfaces held to it: the coach, the
sleep/activity/metric/workout insights, notable shifts, the daily coaching lines, the
one morning generation that feeds both the Telegram briefing and `/api/today`'s action
(§3.2), recs, and challenge/program generation.

```
question/task
  → deterministic safety pre-classifier (refusal domains A–E, §5.5)
  → context: v2-native builders (today snapshot, trends, sleep + overlays,
    manual logs, baselines, anomalies, personal findings) built on
    derived_daily/sample — the legacy zepp_cloud filter bug class is
    impossible by design
  → retrieval: manifest-ranked — top-N FULL notes matched by
    metric/alias/keyword + one-line summaries of the remainder
    (replaces legacy dump-all. It bounds the note COUNT, not the token
    count: measured 2026-08-01, the same "top 6" ran 16k–34k tokens and
    is 65–83% of every prompt the product sends — PRICING §3.1's box.
    A note reaches the prompt through `manifest.prompt_body`, i.e.
    minus its bibliography, which the model cannot cite.
    Signals, strongest first: id named · metric in play · intervention ·
    alias as a WORD and separator-insensitively · content words shared
    with the note's name/aliases/summary, capped below one alias hit.
    The last one is not fuzziness for its own sake: the four above are
    explicit, and when none fires every note scores zero and the
    deterministic id tie-break used to hand the model the
    alphabetically-first six — "should I train hard today?" was grounded
    in alcohol_sleep and cadence_intensity, ~30k tokens chosen by
    spelling. §9 is how that is now measured rather than argued)
  → LLM (tools allowed, §4)
  → hard OUTPUT GUARDRAILS (`insights/output_guard.py`) — BLOCKING, and checked
    BEFORE the validator on purpose: a documented forbidden output (personal
    death-risk projection, advising through a red-flag symptom, sleep
    restriction, bone-stress/REDs) does not ship REGARDLESS of its citations,
    grade or validation result. The pre-classifier guards the QUESTION; this
    guards the ANSWER — a benign question can still produce a forbidden answer,
    perfectly cited. No retry: a forbidden output is not a grounding problem to
    nudge the model out of, it is a floor. Every rule cites the doc/note line
    that forbids it; a rule with no documented origin does not ship.
  → validator v2 — BLOCKING:
      · every interpretive sentence carries [note_id] or an honest escape
        ("no strong evidence in our base…")
      · cited ids must exist in the manifest
      · grade-calibrated language: Established→plain, Probable→hedged,
        Emerging→flagged, Contested→"the science is mixed", Myth→corrected
      · banned-tone check (alarming/reassuring words need a citation)
      · personal findings cited as [personal_finding:…], clearly distinguished
        from population research
      · an unrecognised grade string ranks 0 — the STRICTEST wording rule, the
        same fail-closed default `jobs/recs._provable_grade` and
        `challenges/screen._grade_issue` already used for the same lookup.
        Unreachable today (`gen_manifest.py` pins the vocabulary and aborts on an
        unknown grade); it decides which branch a seventh grade would fall into
      **What this is NOT, said plainly.** Grounding here is CITATION-SHAPED and
      grade-calibrated; it is not entailment-checked. The validator asks whether
      a cited id exists in the manifest and whether the sentence's hedging
      matches that id's grade. Nothing asks whether the note's CONTENT supports
      the claim, and nothing can: there is no entailment step in the design, by
      choice and for cost. `retrieval.evidence_section` embeds the top
      `DEFAULT_TOP_N = 6` notes in full and lists the remaining 72 of 78 as a
      one-line summary each, so most citable ids are cited from a summary plus
      whatever the model already knows about that topic.
      That is a real and unusually strong guarantee — *this claim carries a real
      id, and its wording matches that id's grade* — and it is a DIFFERENT one
      from "the cited note supports this claim". Both sentences are worth having
      written down, because a reader of the first will otherwise go looking for
      a check that was never built.
      The three deterministic surfaces do better and are the contrast: a rec's
      grade is PROVED down to what its citations support
      (`jobs/recs._provable_grade`), a challenge must cite evidence proving at
      least Probable (`challenges/screen._grade_issue`), and a ladder with no
      citable population goal is refused (`challenges/program_screen.py`).
      If an entailment check is ever wanted, the cheap version is to require at
      least one cited id to come from the notes actually EMBEDDED in that prompt
      — `evidence_section` already returns exactly that list as its second
      element, and nothing consumes it today beyond a log line.
  → anti-hallucination: a first-person action claim ("I logged/adopted/created…")
    is an issue unless the tool that can make it true returned ok THIS turn. On a
    tool-less surface the set of successful tools is empty, so every such claim is
    rejected — the strictest reading, not an exemption (`insights/action_claims.py`)
  → answer SHAPE — a surface whose model output has a CONTRACT (today only the
    coach, §4a) reports a broken one HERE, so a malformed payload is nudged and
    then falls back honestly rather than degrading to free text
  → PERSONAL CLAIMS (#129) — every gate above checks claims against the research
    corpus, so a sentence about the OWNER's own data cites nothing and nothing
    checked it: measured 2026-08-03, a model opened "You logged alcohol yesterday
    afternoon" on a fixture with zero alcohol rows and returned `validated=True`,
    because every research sentence in it was correctly cited. The answer contract
    now carries `asserts[]` — the owner-subjects the answer states a VALUE for —
    and asserting one the owner has no stored data for is a retryable issue
    (`insights/personal_claims.py`). Absence is NOT assertion, and that distinction
    is the whole design: "you have 0 logged alcohol entries" declares nothing and
    ships; "you logged alcohol yesterday" declares `alcohol` and does not. A
    textual backstop catches a fabrication that under-declares, for logged event
    kinds only — a metric key is not a word prose uses. It cannot catch a model
    that fabricates AND under-declares a metric, and it says so in its docstring
  → once every allowed attempt has failed: honest fallback ("I can't ground that in
    our evidence base") — unvalidated text NEVER SHIPS (legacy shipped it anyway).
    (section 3a is a named, narrow exception to this sentence for the coach's live DRAFT —
    shown to the owner visibly MUTED as a draft, while this line still governs
    everything that ships as the answer.)
    The retry budget is RESERVED, never shared with tool-gathering: the coach's
    gathering allowance and `pipeline.validation_retries()` are two counters, so an
    answer arrives at its gates with the same tolerance however much data preceded
    it (they were one counter until 2026-08-01, and a 5-tool-round question exited
    having never been asked for an answer at all). The budget is now
    `LLM_VALIDATION_RETRIES`, **default 2**: it was hardcoded to 1, set when a retry
    cost real money on the tier we ran then, and §9.1 measured that ~80% of what the
    product never shipped failed on wording a nudge repairs. It is deliberately ONE
    setting rather than a per-model price table — a table would need model ids in
    git, which `insights/client` keeps out on purpose
  → response metadata: citations[], evidence grade floor, data coverage (§3.1)
```

**Where each stage lives, and why that is now checkable.** The stages above are
`insights/pipeline.py`: `check_question` · `user_context` · `evidence` ·
`complete` · the answer-gate registry (`answer_gates()`: output guard → validator →
anti-hallucination → answer shape → personal claims) · `drive` (nudge, then the
fallback). The gate vocabulary those stages speak (`AnswerContext`, `GateOutcome`, …)
lives in `insights/gate_types.py` and is re-exported, so a gate whose subject matter has
its own module can name it without an import cycle. The two answer
gates that block do so through the **registry**, and the question gate through
`question_gates()` — so **a stage added to a registry reaches every surface by
construction**. `tests/insights/test_pipeline_shared.py` proves it two ways: it
injects a new stage and asserts BOTH surfaces obey it, and an AST guard asserts that
no module outside `pipeline.py` reaches `classify_refusal` / `check_output` /
`validate` / `validate_json` / `evidence_section` / `build_context` at all. The
first proves a registered stage propagates; the second proves a stage cannot be
added *outside* the registry to one surface only. Both are mutation-verified.

### 3a · The coach's live DRAFT — a named, deliberate exception (the owner's 2026-09-19 call)

The owner tested the streamed coach (`api/coach_stream.py`) and it still landed the
whole answer in one piece after a minute of silence. His decision: "make it feel like
claude — stream it as it starts and swap." That is now shipped, and it is a deliberate,
narrow exception to this section's own "unvalidated text NEVER ships" — stated here
plainly rather than left for a reader to discover by diffing the wire contract.

**What is streamed.** A new SSE event, `draft` (`{"round", "text"}`), carries the
coach's answer PROSE while the model is still writing it — rendered from the model's
own partial, mid-write JSON payload by a tolerant scanner
(`insights/coach_draft.draft_prose`, NOT `json.loads`: a half-written answer is not
valid JSON) that extracts the `opening` and each claim's `text`, attaching a claim's
citation only once its `note_ids` array has closed. `text` is the WHOLE draft so far,
not a delta — the client replaces, never appends — emitted at most once every 100ms
per round (`coach_loop._DraftThrottle`) with a final flush when the round's content
ends, so the throttle window can never swallow the round's last word.

**What replaces it.** The terminal `answer` event — the one payload every gate in this
section has judged — always supersedes every `draft` that preceded it, however many
there were and whatever they said. A rewrite (a candidate this section's validator
rejected, nudged, and asked to try again) is not a continuation: the NEXT round's first
`draft` starts from empty text, never from the rejected candidate's tail.

**Why the gates are unchanged.** Nothing about the judged path moved. The draft is
produced by reading the SAME streamed completion the pipeline already makes
(`client.complete`'s new `on_text` hook, forwarded exactly as `reasoning` is — never
part of the `LLMClient` Protocol, so every surface but the coach is byte-identical to
before it existed); it is never fed back into `judge()`, never counted against a
validation retry, and never reaches `answer_gates()` at all. The validator, the hard
output guardrails, anti-hallucination, the answer-shape gate and the personal-claims
gate all still run — unchanged, in the same order — over the FINAL candidate only,
exactly as before this feature existed.

**What makes this safe to ship.** The app renders a `draft` visibly MUTED — the owner's
own words, "shown as a draft" — so what is on screen while the model is still writing
is legible as provisional, not as this product's honest answer. A draft CAN be
reworded or withdrawn in front of the owner: a claim rejected by the validator, or a
rewrite the model produces after a nudge, both happen after the owner has already seen
an earlier, different draft. That is the one place this product now shows the owner
text before every gate has cleared it — narrower than it sounds, because the thing
shown is legible as a draft and the thing that ships is still gated exactly as this
section has always required.

### 3.1 · Data coverage — the definition, and why it is this one (#89)

The metadata line above promised three things from the day the choke point was designed.
`citations[]` and the grade floor shipped. **Data coverage had no definition anywhere and
no surface carried it** — the worst state for a promise: a reader of §3 believes an answer
tells them how much of their data it rests on, and it never did.

> **Data coverage of a metric over a window is the number of days in that window on which
> the metric has a stored daily value, out of the number of days in the window.**

Per metric, published as two integers. `analytics/coverage.py` owns it; `grounded_ask` and
`run_coach` return it; the insight cards, the two warmed coaching lines and `/api/coach`
publish it. The decisions inside that sentence:

- **Per metric, never blended.** One number over a mixed context is a composite score, and
  a composite with no methodology is what CLAUDE.md forbids — sleep and step metrics go
  missing for different reasons and their average describes neither.
- **Counts, not a percentage.** 12/14 carries its own n and cannot be rounded into a lie.
  The same discipline §9 prints every rate under.
- **Counted by `analytics.baselines`, not by a new query.** `Baseline.n` is already "valid
  days for this metric in this window" and already applies the canonical sentinel filter
  (an `rhr_daily` of 0 means *not measured*). A second `COUNT(*)` would be a second
  definition of "has data" and would disagree the first time a sentinel moved.
- **Whose metrics.** The scope is the one each surface already names: `grounded_ask` uses
  its `metrics=` argument over its own `context_days`; the coach names none, and needs
  none — §4's absolute rule is that its numbers come only from tool results, so the
  metrics its tools read this turn ARE the metrics its numbers came from. A turn that read
  none publishes an empty map beside a named window, which says "read no metric directly"
  and is not the same statement as "you have no data".

**It is a quantity and adds no absence vocabulary.** Coverage never says *why* something is
missing; the four existing answers to that keep their jobs and none of them changes:
`derive.freshness` (is the newest row a claim about TODAY — one day, yes/no), `withheld`
(no current value, here is what would restore it), `excluded` (permanently not part of the
definition; no owner action brings it back, §2 of `analytics/biological_age.py`), and
`data_confidence` (`ok` / `insufficient_data` on one derived number). A 13/14 window whose
missing day is *today* is a freshness problem that coverage calls excellent — which is
exactly why both exist. A metric at 0/14 is reported as 0/14 and nothing more; which of the
four states it is in is stated where that metric is served, by the code that knows.

> **The LLM prompt was the one surface where it was NOT stated (#126).** `withheld` reached
> the model as a bare `-` — indistinguishable from "not synced yet" and from "this owner has
> never had it". That is the sharpest possible version of the gap, because COACH_PROMPT.md
> instructs the coach to *"say what you'd need"* and the context structurally could not
> support it: a persona asked for a behaviour its context cannot support is resolved by the
> model, i.e. by invention. `insights/context_withheld.py` now carries the reason id and the
> metric's own restoring sentence for the three gated daily metrics (`vo2max_estimate`,
> `sleep_regularity_index`, `sleep_debt_min`), quoted from the derive modules that own the
> gates rather than restated. It deliberately does NOT carry `last_as_of_date`, `age_days`
> or the last value: putting a withheld metric's number back into the prompt is the
> resurrection the gate exists to prevent. A metric with no stored row at all stays silent,
> so the legend's account of the remaining silence ("anything else absent was never
> recorded") is true. Recovery is the fourth gate and stays where it already speaks, in
> `coach_context._recovery_block`. Cost: **+0 tokens** when nothing is withheld, **+128** on
> the real assembled coach prompt for a stale VO₂max plus a refused SRI (+0.16 % of #105's
> 80,435), bounded by `tests/insights/test_context_withheld.py` and mutation-verified.
>
> **Coverage itself is still not in the prompt, and that is not cheap to change.** #89's
> coverage is computed *after* the coach's tool loop, over the metrics the tools actually
> read — a scope that does not exist at prompt-assembly time, so carrying it would mean
> choosing a different scope, i.e. a second definition. What the context does now do is make
> the count it already had legible: `## Personal baselines` prints `Baseline.n`, which §3.1
> pins as coverage's own counter, and its column is headed `n/30d` so the window is stated
> rather than assumed. A metric with no rows in the window still prints no line at all —
> "0/30" remains invisible, and closing that is its own diff.

### 3.2 · One generation, two surfaces — the morning call (#95)

`BRIEFING_TASK` asked, in its own words, for *"today's single most useful action"*, and
`_DAILY_ACTION_PROMPT` asked for that same line and nothing else. That was **two
full-corpus calls per owner per night where the first already contained the second** — and
the evidence block is ~86 % of either prompt (§3's box), so it was the most expensive
duplication in the product. Both surfaces stay: the briefing goes to Telegram
(`jobs/briefing.py`), the action to `/api/today` via the warm cache (`insights/coaching.py`).

**`insights/morning.py` generates them once and renders them twice**, through the JSON seam
(`grounded_ask(response_format="json")`), with the shape registered in `json_shapes` so
`validate_json` applies the same grounding, grade-calibration, banned-tone and fabricated-id
rules to **both fields** that the prose path applied to the two answers. Nothing regexes an
action line out of a paragraph — a parser against a language model returns the wrong
sentence silently, and the field is the seam that makes that unnecessary.

**Validation binds both, and there is no partial pass.** The two fields are one candidate at
the gates, so an ungrounded sentence in `action` withholds the briefing too. That is the
honest reading — a briefing assembled from a validated body and an unvalidated action is the
half-checked artefact a blocking validator exists to prevent — and it creates the one real
risk in the change: a merged surface can halve availability while saving money.

**So the merge is an optimisation, never a dependency.** If the merged call ships, both
surfaces are filled for one call's price. If it does not, **each surface falls back to
exactly the independent generation it made before #95** — `coaching.warm_daily_action` for
the action, `morning.generate_briefing` for the briefing — so neither can go dark because of
the other's sentence, and each surface's failure MODE is unchanged (the briefing Telegrams
the honest fallback; the action stays `null` and `/api/today` says nothing rather than
guessing). The cost of that guarantee is one extra attempt on a night the model could not
ground itself; the break-even is arithmetic, and the merge is cheaper for any total-failure
rate under 50 % (measured 0 % on current main, 31 % at the 2026-08-01 baseline).

Two parameters had to be chosen rather than split: `context_days` is **30**, the daily
action's window, because the action is calibrated from whole local days and narrowing it
would silently change what a shipped surface can see, while widening the briefing changes
only what it may consider. `metrics` is the **union**, which is nearly free — `metrics`
drives retrieval's ranking, and `evidence_section` embeds a fixed `DEFAULT_TOP_N` notes
however many are named, so the union changes *which* six notes ship in full, not how many.

**Measured, counted-not-billed** (a local dry run over the real assembled prompts, no
provider call): 72,103 → 37,787 input tokens, **−34,316 per owner per shipping night,
−47.6 %**, ~24 % off the nightly chain. `PRICING.md` §3.1 carries the table and the dollar
figures; the billed number is owed after the deploy.

One thing the merge fixed that was not a cost problem: the briefing's action and
`/api/today`'s action were **two independent generations of the same advice** and could
disagree on the same morning. They are now one sentence, rendered on both surfaces —
CLAUDE.md's "ONE canonical definition" applied to a recommendation rather than a metric.

## 4 · Coach loop v2

- **Tools** (all return real JSON the model must echo, never guess) — the seven in
  `COACH_TOOLS` today: `query_metric` (v2-native reads), `compare_event` (keeps
  its honest "observational, single-subject — a hint, not proof" framing),
  `sleep_consistency`, `log_entry` (a write),
  **`get_knowledge(topic|note_id)`** so the model pulls specific notes
  mid-conversation instead of upfront context stuffing, and — from **WP-C5** —
  **`adopt_challenge`** and **`create_challenge`** (`insights/challenge_tools.py`,
  CHALLENGES.md §6/§6a). `adopt_challenge` was DEFERRED for exactly the reason
  the next bullet gives: a tool that can't really adopt anything is the
  hallucination the rule forbids, so it landed only once the subsystem existed.
  `create_challenge` takes an **intent** and calls
  `challenges.generate.generate_challenges(intent=…)` — it does NOT author a
  target or fork a second pipeline, because Gate A and Gate B would then be two
  things to keep in step, which is precisely what the mirror rule below warns
  about. (The legacy five were `query_metric`, `compare_event`, `log_entry`,
  `adopt_challenge`, `sleep_consistency`, §5.3.)
- **Anti-hallucination stays absolute**: never claim logged/adopted/created/started
  unless the tool returned ok:true this turn; numbers only from tool results;
  max tool rounds bounded with an honest failure message — **20 gathering rounds**
  (`coach.GATHERING_ROUNDS`), a ceiling and not a spend: narrow questions were
  measured converging in **2** rounds against a live instance
  (VERIFICATION_2026_08_01 §7), an unused round costs nothing, and the last round
  withdraws
  `tools=` so the model is always *asked* for an answer with what it has rather than
  cut off mid-gather. A round that only repeats a call it already made (same tool,
  same arguments) ends the gathering early — a loop that is not making progress
  should stop on its own, not run out of budget. Worst case per question: 22 LLM
  calls; the **metering charges the question, not the call** (`api/routers/coach.py`).
  WP-C5 made the guard
  **per-tool** (`coach._CLAIM_TOOLS`): with one action tool, "did any action tool
  succeed" was the same question, but with three a successful `log_entry` would
  otherwise have licensed "I started your challenge".
- **The coach is ROUTED THROUGH §3** (#46, done). It used to be *enforced-equivalent*
  instead: `coach.py` drove its own loop and called the choke point's primitives
  itself, so **every rule added to the choke point had to be mirrored in the coach or
  the coach silently missed it** — and that was not hypothetical, the hard output
  guardrail had to be written in **two** places for exactly this reason. That rule is
  gone, and this bullet is the record of why it was worth removing rather than a
  standing instruction.

  What changed: the stages moved to `insights/pipeline.py` and both surfaces run
  them. `coach.py` now contributes exactly two things `grounded_ask` cannot — a
  message layout (persona + context in the system turn, conversation after it) and a
  bounded **tool loop**, expressed as a `pipeline.Loop` whose `next_turn` returns
  `Turn(text=None)` for a round that ran tools instead of answering. The tool loop is
  a *parameter*, not a fork. Every guarantee is unchanged or stronger: refusal before
  any tool runs, the output guard on every text candidate, the blocking validator on
  every final free-text answer, the honest fallback on repeat failure, and the
  anti-hallucination guard — which is now a shared gate, so the *other* surfaces got
  it too (they have no tools, so any action claim from them is rejected outright).

  **The rule that replaced the mirror rule:** a stage enters through
  `pipeline.answer_gates()` / `pipeline.question_gates()`, and
  `tests/insights/test_pipeline_shared.py` fails if a surface stops inheriting one or
  reaches a primitive directly. Nobody has to remember anything.
- **Standing context per turn** (`insights/coach_context.py`): today's
  recovery/readiness block plus a wide (≥30-day) `build_context` — trends,
  baselines, anomalies, sleep sessions, the manual-entry log, and personal
  findings — so the coach reasons over history and routines, not a snapshot
  (COACH_PROMPT.md). **WP-C5 added the third block**
  (`insights/challenge_context.py`): their active + suggested challenges (with the
  ids `adopt_challenge` takes) and the **frozen outcome ledger** — measured personal
  evidence ("last time MVPA rose 20%, HRV followed in 10 days"), cited as
  `[personal_finding:challenge_outcome]`, never dressed as research. The ledger's
  caveats are enforced by **what is in the prompt**, not by asking: an
  `insufficient_data` outcome is listed with **no numbers at all** (there is nothing
  to quote), and a `co_occurring` cross-metric delta is **never rendered**
  (CHALLENGES.md §2.1 — a number you hand over is a number that can be attributed).
  *Still not present:* live progress, which `query_metric` can fetch and which the
  coach may never adapt anyway (CHALLENGES.md §5.2).
- **Roadmap C1/C2 added the fourth and fifth blocks** (`coach_context`): the open
  commitments they made to the coach, and — for the ones they said they kept — what
  the named metric did either side (`insights/commitment_outcome.py`). That completes
  the outcome ledger's three sources: correlations, challenges, commitments, all three
  cited `[personal_finding:…]` and all three using the same estimator and the same
  `ok`/`insufficient_data` words. The commitment source is the weakest claim of the
  three, so it is held to the *strictest* reading: the challenge ledger's own
  `MIN_COMPARISON_DAYS`, plus a gate that publishes nothing until the estimator's
  trailing window clears the commitment date. **Nothing here observes adherence** —
  `kept` is what the person said, and the prompt says so in the block itself so the
  coach cannot infer a commitment was kept because a number moved.
- **The pivot names the INSTRUMENT, not just the number (#120).** `context._recent_daily`'s
  compact per-day table handed the model `vo2max_estimate` as a bare number, so the coach
  could say "your fitness is *measured* at 39.6" about a value the Jurca questionnaire
  estimated — the #108 conflation re-entering through a different door, and the half of
  [[hr_reserve_vo2max]] Directive 4 ("**state which one produced the value**") that #117
  had delivered to `/api/today` but not to the surface that *writes sentences about the
  number*. The pivot now suffixes each VO₂max with one word — `graded` / `reserve` /
  `model` — and emits one legend line saying which of those are measurements and which is
  a questionnaire. `insights/context_provenance.py` owns that vocabulary; the default for
  a pre-#117 row with no stamp is `vo2max_tier.method_of`, so the payload and the prompt
  cannot disagree about what produced a row.
  **The cost was measured, not assumed** (the pivot rides in *every* prompt, and §9.3 is
  why that matters): tiktoken/cl100k over the real assembled coach prompt gives **+0 tokens**
  when the window holds no VO₂max, **+59** at one day, **+88** at thirty — 58 for the legend
  plus exactly one per tagged value, i.e. **+0.11 %** of the 80,435-token coach question
  §9.3 measured. `tests/insights/test_context_provenance.py` asserts the budget.
- **The AGGREGATES over those values could still blend them — closed (#125).** #120 named
  the instrument on each per-day number and left the reductions over them alone: `## Today
  snapshot` reduced `vo2max_estimate` to a z-score, `## Trend summary` to a 7-day **mean**,
  `## Personal baselines` to a 30-day **median**, and the anomaly scan to another z — each
  across whatever instruments the window happened to hold. A mean over two instruments **is**
  the blend D4 forbids, which #117 made impossible *inside* `derive/vo2max_tier.py` and
  nowhere else. On the owner's own pair (graded 39.6, reserve 41.7, three days apart, inside
  all three windows) #117 measured the blend at **40.7** against his single-instrument
  **40.6** — one tenth, invisible to inspection, which is why this is structure and not care.

  **The fix is refusal, not re-selection.** `context_provenance.InstrumentGuard` answers one
  question — which instruments does this metric's reduction window hold — and the four
  sections ask it before reducing. One instrument: reduce as before, and the row NAMES it
  (`vo2max_estimate (model)`), which is D4's other half applied to a statistic. Two or more:
  **no mean, median, z-score or anomaly is emitted at all**, and `guard.section()` says so
  where the numbers would have been, because an omission the model cannot tell from absent
  data is #126 in a second place.

  Two designs were rejected. *Reduce within the winning instrument* (mirroring
  `select_measured_tier`) re-applies a per-DAY precedence across DAYS: a graded session 25
  days old would outrank 28 fresh Jurca days and win the 30-day median, undoing the 14-day
  freshness horizon in the direction that flatters — the #108 failure. *Per-instrument
  aggregates* costs three tables' worth of tokens to publish medians over n = 1 and n = 2.
  Refusal loses nothing the model cannot read: `vo2max_estimate` is in the per-day pivot,
  tagged, for every day of the window.

  The guard reads ONE window — `30 + 14 = 44` days, the widest span any single statistic
  above can rest on — because two windows would be two answers to "does this metric mix
  instruments" and the sections could disagree on the same page. Erring wide withholds a
  statistic; it never invents one. Cost: **+71 cl100k tokens** when a window actually mixes
  (0 otherwise) and **+3 per labelled aggregate row**; `tests/insights/test_context_no_blend.py`
  asserts the budget and is mutation-verified four ways.

  *Registered today: `vo2max_estimate` only.* `steps_total` and `distance_m_daily` also carry
  two instruments each since #121 (`derive/device_totals.py`) but stamp them in `flags.source`
  rather than `flags.method`, and blocking them is a product decision rather than a directive —
  see that module and the #125 report.

### 4a · The coach's answers are STRUCTURED — claims as data, prose rendered by us (#128)

The coach used to answer in free prose carrying an inline `[note_id]` convention, and the
blocking validator checked whether the model had remembered it. §9.5 measured what that
convention costs on a cheaper model: **knowledge answers 6/6 → 3/6**, DeepSeek's failures
almost all *"Interpretive sentence lacks a citation"*, while every surface whose output was
already STRUCTURED matched or beat the expensive tier (`surface` 10/12 → 12/12). Nothing
incorrect ever shipped — the validator caught all of it and served the honest fallback — so
what the convention costs is **availability**, and it costs it for instruction-following on
a formatting rule rather than for health knowledge.

So the coach now returns its answer as data and `insights/coach_answer.py` renders the
prose:

```json
{"coach_answer": {
  "opening": "<one plain line reporting the owner's own numbers — description only>",
  "claims": [{"text": "<one sentence>", "note_ids": ["…"], "grade": "Probable"}]}}
```

- **A claim cannot reach the owner without what grounds it.** The renderer attaches the
  ids to *every sentence* of every claim; a claim the model marks uncitable (`note_ids:
  []`) ships carrying `prompts.SYSTEM_PROMPT`'s own escape inside the same sentence, which
  is what the validator already accepts. There is no third branch, and there is no
  "degrade to prose" branch either — a malformed payload is an issue, nudged and then
  fallen back on, because degrading would reinstate the uncited path on exactly the turns
  where the model was already ignoring instructions.
- **Interpretation cannot hide in the frame.** `opening` is free text, so it is checked for
  the one thing that would reopen the hole, using `calibration`'s own vocabulary and
  `validator`'s own two exemptions: a descriptive line naming real numbers is legal, an
  interpretive one is redirected into `claims`. Stricter than the validator on that field
  by design — there an interpretive sentence needs a citation, here it needs to *be a
  claim*.
- **The declared `grade` is checked, not trusted** — §5.6's recs hole, closed on the coach.
  An **overclaim** (declared stronger than the strictest cited note) is refused;
  under-claiming is allowed, because failing it would spend a retry to make an answer less
  careful. It never rewrites the sentence: inserting a hedge would be the product asserting
  something nobody wrote, and `_grade_issue`'s calibration rule still runs on the rendered
  text unchanged.
- **Nothing was weakened to buy it.** The rendered prose faces every answer gate exactly as
  before; the shape check is an *additional* stage, and it enters through
  `pipeline.answer_gates()` like any other, so it inherits the same nudge-then-fallback
  policy and the same propagation proof. Seven mutations of the guarantee were verified to
  turn `tests/insights/test_coach_answer.py` red.
- **JSON mode is requested only on a round that offers no tools.** The two are not reliably
  combinable across the providers behind OpenRouter, and a round that answers is a round
  that stopped calling tools; the shape otherwise arrives by instruction, and the parser
  tolerates a code fence or a word of preamble.
- **`docs/COACH_PROMPT.md` is untouched.** It is pinned byte-for-byte and it is the voice;
  the contract is appended to the system turn exactly as the context and evidence blocks
  are, and it lives beside the parser that enforces it so the two cannot drift.

---

## 5 · AUDIT — how the legacy system actually grounds (preserved findings)

All references are to `~/projects/healthee-legacy`.

### 5.1 Corpus & retrieval
- Loader `src/healthee/research.py`: parses `research/*.md` YAML frontmatter
  (`id, topic, evidence_grade 3/2/1, applies_to_metrics,
  applies_to_interventions, tags, last_reviewed`) into EvidenceNote; notes
  without frontmatter are silently dropped; **no caching** — the whole tree
  re-parses on every call.
- Retrieval is NOT semantic: `rank_notes_by_relevance` (context.py:468) is a
  keyword→metric/intervention regex ranker (+100 direct id hit, +10 per
  metric/intervention match) that only REORDERS; **all ★★★ notes are always
  included in full** (`_research_notes_md`, context.py:558). ★★ notes reach
  only the recs engine (grade≥2 whitelist, recs.py:450).

### 5.2 Validator contract (`llm/validator.py`)
- Citation = `[snake_case_id]` (regex `\[([a-z0-9_]+…)\]`) — comma-separable.
  Hyphenated ids can never match (why sports-science docs are uncitable, §7).
- Three rules: cited ids must exist in the loaded base (set-membership);
  banned-tone words (concerning/alarming/dangerous/great/excellent) require a
  citation in-sentence; interpretive sentences (likely/suggests/associated
  with/…) require a citation or an escape phrase ("no strong evidence…").
- Hard refusals bypass validation (template-fragment match).
- **Advisory only**: one retry with a nudge listing issues; after that the
  response is returned anyway with `validation_ok=False`.

### 5.3 Coach endpoint (`api/app.py:4330 POST /api/coach`)
- Context: last 12 messages, build_context(days=14), active+suggested
  challenges, today's recovery block; `_COACH_SYSTEM_PROMPT` (app.py:3712).
- Loop: max 4 rounds of `chat_raw(tools=_COACH_TOOLS)`; fixed apology on
  overflow.
- Tools (exactly 5): query_metric (metric_sample; avg/series/latest/min/max/
  sum/trend), compare_event (on/off-day averages + "hint, not proof" caveat),
  log_entry (caffeine/alcohol/water/meditation/exercise/weight/fast_start/
  fast_end), adopt_challenge (by title match), sleep_consistency (median
  bedtime, SDs, SRI, irregular nights).
- Anti-hallucination: prompt rule "NEVER say you logged/adopted unless the
  tool returned ok:true this turn"; metric namespace constrained by
  `_COACH_METRICS_HINT`; tool results returned as JSON.
- **`/api/coach` never runs the validator** — citation discipline and refusal
  domains are prompt-only on the flagship surface.

### 5.4 Context builders & the v2 breakage
- Sections: safety scan (SpO2<90, sustained RHR>baseline+10, <4h nights),
  today snapshot (value vs 30d baseline, z-scores), 7d-vs-30d trends, recent
  daily metrics table, sleep sessions + overnight overlays, manual entries,
  baselines, anomalies, personal findings (FDR-significant correlations,
  explicitly "not citations"), evidence notes.
- **Broken on v2 data**: `source='zepp_cloud'` filters at context.py:108, 240,
  267 return empty (v2 emits gadgetbridge/derived); metric keys are stale v1
  names (`distance_m`, `calories`, `hrv_rmssd_ms`, `sleep_score` vs v2's
  `distance_m_daily`, `total_calories`, `hrv_sleep_avg`,
  `sleep_health_score_4dim`) — today-snapshot/trend/anomaly sections silently
  under-report. The rebuild's v2-native builders fix this by design.

### 5.5 Refusal domains & calibration (`llm/prompts.py:23-56`)
- A emergency/red-flag · B diagnosis/clinical evaluation · C medication/
  treatment changes · D pregnancy/lactation/pediatric · E mental-health
  distress — each with an exact refusal template. KEEP ALL FIVE.
- Language calibration is hedge-verb based ("consistent with" / "may be
  related to" / "associated with in [population]" / "no strong evidence");
  bans "is caused by/definitely/always/never" and population thresholds.
  The star grade has no automatic tone mapping — binary gate only (≥3 coach,
  ≥2 recs). Validator v2 upgrades this to per-grade calibration (§3).

### 5.6 Recs engine (separate grounding path)
- Own context builder; grade≥2 citation whitelist; JSON-shape validation;
  drops recs citing unknown ids; each rec self-declares evidence_grade 2|3
  and carries raw prompt/response audit fields.
- ⚠ "self-declares" was the hole, in legacy AND in the rebuild's first cut: the
  declared grade was checked for being 2|3 but never compared against the cited
  notes, so a rec citing a Contested note could ship labelled *Established*.
  → rebuild: `jobs/recs.py::_provable_grade` resolves the shipped grade from the
  strictest cited note (`manifest.grade_of`) — overclaims corrected down, below
  Probable dropped. The grade≥2 whitelist lives THERE, on the provable floor; it
  is not a retrieval filter (weaker notes stay retrievable so the coach can still
  discuss — or correct — them).

## 6 · AUDIT — the four structural holes the rebuild closes

1. **Coach skips validation** (§5.3) → **closed, and now closed structurally**: the
   coach was first made *enforced-equivalent* (it called the blocking primitives
   itself), and #46 collapsed it onto the shared pipeline (§4). Unvalidated coach
   text cannot ship, and no new choke-point rule has to be mirrored by hand.
2. **Validation is advisory** (§5.2) → §3: blocking, with an honest fallback.
3. **Retrieval is dump-all** (§5.1) → §3: manifest-ranked top-N + summaries.
4. **Sports-science docs uncitable** (hyphen ids, no frontmatter) → §7
   migration.

## 7 · Knowledgebase coverage & gaps (full audit matrix)

### 7.1 Coverage matrix (metric → legacy derivation → backing notes)

N = packages/knowledge/notes, SS = packages/knowledge/sports-science.

| Metric | Legacy derivation | Backing notes |
|---|---|---|
| RHR (`rhr_daily`) | derive.py:53 | N resting_hr_health_marker, wearable_hr_validity; SS resting-heart-rate |
| HRV overnight (`hrv_sleep_avg`) | derive.py:170 | N hrv_recovery_marker, hrv_improvement, recovery_readiness; SS heart-rate-variability |
| VO2max (Jurca `vo2max_estimate`) | derive.py:399 | N non_exercise_vo2max, vo2max_estimate_plan, vo2max_fitness_mortality, vo2max_training_program; SS vo2max |
| VO2max submax (`vo2max_submax`) | derive.py:426; vo2max_submax.py | N submaximal_vo2max |
| MVPA (`mvpa_min`) | derive.py:372 | N mvpa_minutes_mortality, mvpa_weekly_plan, cadence_intensity |
| Steps (`steps_total`) | derive.py:310 | N steps_mortality, sedentary_mortality, exercise_mortality |
| Cardio load / TRIMP (`cardio_load`, zones) | derive.py:629 | N cardio_load_trimp; SS training-stress-score, heart-rate-zones |
| **Strain (0–21)** | app.py:1636 | **NONE dedicated** (implicit via cardio_load_trimp) |
| Sleep score (4-dim) | derive.py:131 | N sleep_health_score_multidim, sleep_score_implementation_plan, no_validated_sleep_score, wearable_sleep_stage_validity |
| Sleep need/debt | derive.py:683 | N sleep_need_debt |
| SRI / consistency | derive.py:154; app.py:3907 | N sleep_regularity_index, sleep_consistency, sleep_timing_chronotype |
| Recovery score | derive.py:748 | N recovery_readiness; SS sleep-and-recovery |
| **Readiness (live intraday decay)** | app.py:3077 | recovery_readiness loosely; **formula self-admittedly unvalidated** |
| Biological age | analytics/biological_age.py:30 | N biological_age_estimate |
| Respiratory rate (sleep) | derive.py:182 | N respiratory_rate_normal, illness_flag_plan |
| SpO2 (overnight/min) | derive.py:173-180 | N wearable_spo2_validity |
| Skin temp | ingested; app.py:1475 | N skin_temp_signals, illness_flag_plan |
| Illness flag | app.py:1475 | N illness_flag_plan |
| **Stress (Zepp 0–100)** | ingested; app.py:1773 | **NONE** |
| Calories / TEE | derive.py:350 | N energy_expenditure_derivation |
| Distance | derive.py:329 | N distance_from_steps |
| PAI | app.py:1281 | ~~pai_activity_score~~ — note removed 2026-07-16 (PAI not derived in v2; owner decision) |
| ACWR | app.py:2593 | SS training-load-acwr |
| HRmax (Tanaka) | derive.py:230; vo2max_submax.py | SS maximum-heart-rate; N wearable_hr_validity (partial) |
| **Weight (`weight_kg`)** | weight_log; feeds BMI/VO2max/calories derive.py:204 | N weight_bmi_body_composition |
| Strength minutes | app.py:1382 | N strength_adherence_plan, strength_training_mortality; SS strength-training-for-runners |

### 7.2 Missing knowledge docs — the writing backlog

**Priority A — metrics we already surface with NO backing (live honesty
violations):**
1. `wearable_stress_scores` — validity/interpretation of Zepp-style 0–100
   stress; we show a stress card with zero evidence behind it.
2. ~~`weight_bmi_body_composition`~~ — **WRITTEN 2026-08-01** (#11,
   `notes/metrics/`). It backs the weight card and names what weight costs the
   Jurca VO₂max and Mifflin-St Jeor models. Two implementation gaps it
   documents remain OPEN: `_weight_as_of` has no staleness bound (a year-old
   weight anchors today's BMR/BMI silently), and `_weight_card` surfaces a bare
   latest weigh-in with no baseline, trend or date.
3. `strain_scale` (or extend `cardio_load_trimp`) — document our 0–21 scaling
   honestly.
4. `napping` — the app gives strategic nap guidance with no napping note.
5. `intraday_readiness_decay` — find evidence for the live-decay formula, or
   the card must label it "our heuristic, unvalidated" (the honesty contract
   applied to ourselves).

**Priority B — user-loggable / coach-reasoned topics with no note:**
6. `fasting_time_restricted_eating` — fasting is loggable + comparable; zero
   notes (legacy code comments literally say "no notes yet").
7. `hydration_general` — water logging exists; only athletic fueling (SS) is
   covered.
8. `nutrition_protein_basics` — or an explicit policy note that nutrition
   stays out-of-base (an honest refusal needs a documented reason).

**Priority C — computable-metric candidates that would activate orphaned SS
docs** (we already record GPS workouts): aerobic decoupling, grade-adjusted
pace (Minetti is already implemented in the VO2max estimator), pace zones,
race prediction, critical speed, cadence/stride from per-minute data.
Each new derived metric makes its SS doc citable.

**Promotions:** `mvpa_min_weekly` and `strength_min_weekly` to first-class
derived metrics (their notes already exist; legacy computed them ad-hoc in
API payloads).

### 7.3 Migration task — make sports-science citable
Add frontmatter to all 29 SS docs: snake_case `id` (e.g. `heart_rate_zones`),
aliases (the hyphenated original name), category, grade mapped from their
Established/Probable/Emerging/Contested scale (already matches the unified
scale), `applies_to_metrics`. Without this they cannot be cited at all
(§5.2 regex). Generalize runner-specific directives on import — flag with
`population: runners` where they shouldn't apply blindly.

### 7.4 Orphans (exist, back no computed metric — fine, tracked)
- Protocol/engineering docs in notes/protocol/ (no frontmatter, never loaded —
  correct; they're engineering references, move out of the citable corpus
  eventually).
- Meta/process notes: recommendations_engine_plan, llm_health_advice_safety,
  behavior_change_and_personalization (back the recs engine, not metrics —
  keep).
- 12 SS running-performance docs + 5 SS principles + 2 SS wellness — orphaned
  until Priority C metrics exist; principles docs ground *plan design*
  (challenges/programs), wire them into the challenges generator context.

## 8 · Phase mapping & acceptance

| Work | Phase | Done when |
|---|---|---|
| Manifest + SS frontmatter migration + validator v2 + choke point + coach v2 | 1 | Coach answer with a fabricated citation is blocked in test; SS note citable end-to-end |
| Card anatomy + bundled summaries + ⓘ-renders-the-note | 2 | Every metric card shows confidence + grounded why; ⓘ sheet is the note |
| Sync-down reconcile + offline stale-stamping | 3 | Airplane-mode card shows provisional tag + dated cached insight |
| Device analytics + confidence chips | 4 | Parity suite green |
| Priority A/B notes | parallel, start now | Each merged note passes template check (Honesty + Directives + verified primary sources) |
| Priority C metrics + SS activation | 5+ | New derived metric ↔ its SS doc citable |
| Outcome-ledger coach memory + weekly review | 5 | First weekly review cites only real notes + personal findings |

---

## 9 · Measuring grounding — the eval harness

Every stage above is enforced by a test. Whether the answers are actually any *good*
was, until 2026-08-01, unmeasured — and that gap stopped real work twice: the cost work
could not test whether four evidence notes ground an answer as well as six (the biggest
remaining lever), and a retrieval change could only be reported as "58% → 53% at n=59,
≈0.5σ apart", which is neither a win nor a regression.

`apps/server/tests/grounding_eval` closes it. A fixed question set — knowledge, data,
compound, out-of-domain, safety, plus the four shipped insight prompts imported from the
modules that send them — runs against the REAL model through `run_coach` /
`grounded_ask` with a metered client injected.

**The headline metric is the SHIP RATE**: of the answers we paid for, how many reached
the owner. A candidate that fails its gates twice costs a full-context call *and* its
nudged retry and then ships the honest fallback — measured, ~40% of nightly generations
ended that way, so answer quality is a cost lever roughly the size of the prompt itself.
Also reported: refusal correctness (a floor, never pooled into the ship rate), citations
per shipped answer, LLM calls, tool rounds, and provider-counted input/output/reasoning
tokens (`ChatResponse.usage`).

Rules it enforces on itself:

- every rate prints with its **n and a 95% Wilson interval**; two arms are compared with
  a **paired McNemar test** (exact binomial) and a sentence that says in words when a
  difference is *not* significant — "not measurably worse" is not "the same";
- transport/DB errors are excluded from the denominator and counted separately, never
  folded in as failures;
- every record carries the WARNING/ERROR lines the pipeline logged while answering it, and
  the summary prints a **census of issue CAUSES** grouped by cause rather than by
  sentence. Without it an arm could say a third of its answers never shipped but not why,
  and #99's whole diagnosis had to be grepped out of a console log the next run would
  overwrite — a number with no cause attached, which is this harness's own complaint one
  level up;
- the two arms are two runs of the same code at two commits, not a flag inside it.

It costs real money and hits the network, so it never runs in the normal suite; only its
offline arithmetic tests do (Wilson checked against its own defining equation, McNemar
against exact binomial values, and the premise that every safety question refuses
pre-LLM). Measured: 16 questions × 3 repeats = 48 runs, ~5M input tokens, **~$3.00 per
arm** and ~30 minutes. *(#95 added a 17th — the merged morning prompt, §3.2, which is the
most expensive thing the product sends nightly and was previously unmeasurable here
because the harness had no JSON arm. Budget ~1/16 more, and note that an arm taken across
that commit is not comparable: the question set moved, and the fingerprint says so.)*

    uv run python -m tests.grounding_eval run --repeats 3 --out before.json
    uv run python -m tests.grounding_eval compare before.json after.json

### 9.1 · First results (2026-08-01, three arms, n = 42 answer-expecting runs each)

**Baseline ship rate: 29/42 = 69.0% [95% CI 54.0–80.9].** Nearly a third of what the
product pays for never reaches the owner, and the cost of a failure is two calls.

**The retrieval fix (§3's signal list) is a NULL RESULT on the ship rate.** 29/42 both
arms; the paired test found 6 flips each way (p = 1.0). It is not nothing —
deterministically, **14 of 14** answer-expecting questions now retrieve a different
top-6, `resting_heart_rate` ranks first for "what is my resting heart rate" instead of
scoring zero, and `recovery_readiness` ranks first for "should I train hard today"
instead of `alcohol_sleep` — but *changing every note on every question did not move the
rate*, which is the useful finding. The evidence block got 2.6% **larger** in characters;
end-to-end input tokens fell 15.6% per question on fewer tool rounds, sign not
established (95% CI −43,049 to +5,255).

**Where the failures actually are** (13 per arm, both arms):

| cause | before | after |
|---|---|---|
| "Probable claim stated without a hedge" (grade calibration) | 7 | 11 |
| "Interpretive sentence lacks a citation" | 4 | 2 |
| hard output guardrail (personal death-risk number, `activity_insight`) | 2 | 0 |

So **~80% of the waste is language calibration, not retrieval** — and at least two of
those are arguably validator false positives worth their own measured PR: a markdown
**heading** ("**What the data shows**") counts as an uncited interpretive sentence
because it contains "shows", and a sentence stating the owner's own measured number
beside a cited range counts as an unhedged Probable claim.

**Can the evidence block be trimmed? Provisionally yes.** top-6 → top-4, same questions,
same code: ship rate 29/42 → 29/42 (4 flips each way, p = 1.0) with input tokens
**−19,128 per question, −18.8%, 95% CI −35,173 to −3,083 — sign established**, $3.04 →
$2.56 per arm. That is the first evidence the biggest remaining cost lever is safe to
pull. It is NOT proof of equivalence: n = 42 pairs can only exclude differences larger
than roughly ±20 points, so the honest reading is "no loss detectable at the resolution
we bought". Before shipping the trim, either accept that bounded risk deliberately or
run ~200 pairs per arm (~$15/arm). `DEFAULT_TOP_N` is unchanged at 6 — the measurement
was run as a throwaway arm, not as a landed change.

> **⛔ CLOSED BY OWNER DECISION, 2026-08-02 — do not re-propose this as an open
> question.** The ~200-pair confirmation arm above was scoped, costed (~$30) and then
> **cancelled before a cent was spent**. The owner's instruction was *"don't run"* and
> *"don't change top-N if the previous was working"*. So the state of this lever is:
> **measured (−18.8% input tokens, sign established, ship rate flat) and deliberately
> unspent.** `DEFAULT_TOP_N` stays at **6**; retrieval is not to be touched.
>
> It is recorded here rather than deleted because it is still the one priced item on the
> board: it is what would buy the coach cap back from **20 to 30 questions at the same
> $6.99** (`PRICING.md` §0's arithmetic — 30 × $0.179 = $6.98 today, ~$5.85 after the
> trim). If raising the cap ever becomes worth doing, this is the measurement to finish;
> until then the cap is 20 and the price is $6.99, both unchanged.
>
> For anyone who does finish it: the power arithmetic was done before the cancellation
> and is worth keeping. The quantity is the **95% half-width on the paired ship-rate
> difference** when the arms come out level — i.e. the regression size the run could
> *exclude* — computed conditionally on the discordant pairs (Clopper–Pearson on `b`/`m`,
> scaled by `m`/`n`), which is the same exact-binomial footing `stats.mcnemar` stands on:
>
> | discordance | n | excludes a regression bigger than |
> |---|---|---|
> | 2/14 — what #105 actually got | 14 | **±13.9 points** |
> | 19% — §9.1's own top-N pilot (8/42) | 200 | **±6.3 points** |
> | ~6% — the near-ceiling rate current `main` shows (§9.3, §9.4) | 200 | **±3.5 points** |
> | 0 discordant pairs | 200 | **≤1.5 points** (rule of three) |
>
> So ~200 pairs buys a **2–4× sharper bound than #105 managed**, and lands inside single
> digits under every discordance rate this pipeline has actually produced — enough to
> exclude a regression small enough to matter. (Note this is a different metric from
> §9.3's "±25 points", which is a *detectability* threshold — what a test would reject —
> not a CI half-width; the two are not comparable and are stated separately on purpose.)
> **The n was never the problem**; the decision was that a working retrieval path is not
> worth re-opening.

### 9.2 · #99 — four of those causes were the validator, and the arm that could not be run

The two false positives §9.1 flagged as "worth their own measured PR" turned out to be
four, and together they account for **19 of the 39 recorded issues** and **6 of the 13
fallbacks in EACH of the two arms above**: the hedge vocabulary had no entry for
*probably* (17 issues), a section heading counted as an uncited interpretive sentence, a
sentence reporting the owner's own measured numbers counted as an unhedged claim, and a
sentence that *declined* to claim ("the data does not support a confident call") was
rejected for insufficient hedging. All four are fixed in `insights/calibration.py` +
`validator.py`, each pinned on both sides, and `_ACTIVITY_PROMPT` no longer asks for the
healthspan framing that was tripping the death-risk guardrail.

**None of it is defended by a ship rate, because the arm could not be run.** The
OpenRouter account exhausted its credits ($200.27 of $200) 16 questions into the before
arm on 2026-08-01: every call from there on returned HTTP 402, so the arm scored
**8/12 = 66.7% [95% CI 39.1–86.2]** on its surviving repeat — consistent with the 69.0%
baseline and useless as a comparison — and no after arm exists. What replaced it is a
deterministic replay: every failure sentence recorded in the two arms above, run through
the new rules, holding the model's outputs fixed. That is a lower bound on the fallbacks
converted (the log records only the SECOND candidate's issues, so a first candidate that
would now pass is not counted) and it is **not a ship rate** — the model is stochastic and
a real after-arm would generate different text. **The measurement is still owed.** Run it
when the account has credits; it is one `run --repeats 3` per side.

> **The owed number arrived incidentally on 2026-08-02.** §9.3's *before* arm is the same
> question set on current `main` (`cdde686`), and it shipped **14/14 = 100.0%** where the
> 2026-08-01 baseline shipped 29/42 = 69.0%. That is one repeat, not three, and it is not
> the paired arm #99 asked for — but the four validator fixes are the only thing between
> the two runs, and nothing else moved in that direction. Treat it as strong corroboration
> and a weak measurement. The paired arm is still the honest way to close #99.

### 9.3 · #105 — moving the corpus off the gathering rounds, measured and REVERTED

**The plan.** A coach question is ~3 model calls and the EVIDENCE NOTES block rides on
every one of them (§3's box: 65–83% of every prompt). Only the last call writes prose or
cites anything. So: give the gathering rounds the corpus **index** (every note as one
line — id, grade, summary) and send the note **bodies** once, on the round that answers,
with the tools withdrawn. Projected ~40% off the most expensive item in the product.

**The result: it saved nothing and it cost grounding.** One repeat per arm, 16 questions,
14 answer-expecting, `before` = `cdde686`, `after` = `95beae6` (the implementation, kept
in history for anyone re-measuring it):

| | before | after |
|---|---|---|
| ship rate | **14/14 = 100.0%** [95% CI 78.5–100.0] | **12/14 = 85.7%** [95% CI 60.1–96.0] |
| paired (McNemar, exact) | — | 2 worse, 0 better, **p = 0.500** |
| citations / shipped answer | 2.7 [1.8–3.6] | 2.4 [1.3–3.5] (paired −23.7%, CI spans 0) |
| input tokens / question | 82,824 | 80,435 — **paired −2,389 (−2.9%), 95% CI −28,883 to +24,104, sign NOT established** |
| llm calls / question | 2.1 | 2.8 (paired +29.4%, CI spans 0) |
| spend | **$0.77** | **$0.77** |

**Why, measured deterministically** (this part needs no repeats — it is prompt
arithmetic). Over the 10 answer-expecting coach questions: persona **2,660** tokens ·
context **2,676** · full notes **32,506** · **index 7,578**. So a gathering round really
did fall from 37,842 to 12,914 tokens — a 66% cut, the mechanism worked. Two things ate
it:

- **The round that ENDS gathering is a whole extra call.** The loop cannot know which
  round is the answering one, so it learns by watching the model stop calling tools — and
  that round's text was written without the notes it would have to cite, so it must be
  discarded. Modelled against the measured block sizes, break-even sits at **one tool
  round**, and the measured mean is **1.2**. A question needing no tools at all (3 of 10
  in the before arm) costs **+54%**.

  | tool rounds | 0 | 1 | 2 | 3 | 4 |
  |---|---|---|---|---|---|
  | input tokens vs before | **+54%** | −6% | −26% | −36% | −42% |

- **The model fetched back what was removed.** `get_knowledge` invocations rose **7 → 18**
  across the arm. `retrieval.py`'s own docstring had predicted exactly this ("the coach
  then spent a whole extra round on `get_knowledge` fetching the note retrieval should
  have supplied"). It is the risk the brief named, in its cheaper disguise: not "it looks
  up the wrong metric" but "it looks up the notes, one full-price round at a time".

**What n = 14 pairs can and cannot say.** It cannot establish that the shape is worse:
2-worse/0-better is p = 0.500, and a 14-point drop is well inside what this resolution
produces by chance. It equally cannot show equivalence — at n = 14 only differences larger
than roughly ±25 points are detectable at all, so a real regression of 10 points would be
invisible here. What it *can* do is settle the trade: **there is no measured saving to
weigh the risk against**, in tokens or in dollars, so the honest move is to revert rather
than to buy an unquantified grounding risk with an unquantified win. The two failures were
both `compound` questions and both were grade-calibration/citation issues — the same class
§9.1 measured as ~80% of all failures, which is one more reason not to read them as proof
of anything about retrieval.

**What this leaves standing.** The measured, unspent cost lever is still §9.1's:
`DEFAULT_TOP_N` **6 → 4**, −18,128 input tokens per question (−18.8%, **sign
established**) with the ship rate flat. The notes block is ~86% of a coach prompt;
shrinking it beats moving it. `PRICING.md` §0 now carries the consequence: a coach
question costs $0.179 and the 30-question cap is a pricing decision, not a pending
experiment.


### 9.4 · #95 — the merged morning generation, measured against the pair it replaced

**What was owed.** §3.2's merge (`insights/morning.py`, shipped `0ff6a33`) had a
**counted** saving — 72,103 → 37,787 input tokens, −47.6%, tiktoken over the real
assembled prompts, no provider call — and **no measured quality number at all**. Its own
docstring names the risk plainly: a merged surface that halves availability to save money
is not a win. And because the merge falls back to exactly the pre-#95 independent
generation when it fails validation, a regression could never appear as *worse answers*.
It could only appear as **more fallbacks** — the merged candidate failing its gates, both
surfaces paying for the merged attempt and then paying the old price anyway.

**The design, and how it works inside the fingerprint.** The pre-#95 night sent two
prompts; the post-#95 night sends one. A cross-commit arm is impossible here on purpose —
the question set moved when `g_morning` was added, and `records.question_set_fingerprint`
refuses the comparison. Nothing needed disabling: **all three prompts exist at HEAD**, and
the two standalone ones are not archaeology, they are the shipped fallback path
(`morning.generate_briefing`, `coaching.warm_daily_action`). So both arms come from **one
run at one commit with one fingerprint**, and the unit of pairing is the **night**:

    pre-#95 night  = g_briefing AND g_daily_action both ship at repeat r
    post-#95 night = g_morning ships at repeat r

Pairing on the repeat index is exactly as strong as the harness's own cross-arm pairing
and no stronger — `stats.paired`'s docstring already says what it buys.

Two harness gaps had to be closed first, both now permanent:

- **`g_briefing` was missing.** The set carried the merge and *one* of the two prompts it
  replaced, so it could measure `g_morning` against `g_daily_action` and never against the
  pair a night actually ran. It is now the 18th question, imported from `BRIEFING_TASK`
  like every other shipped prompt.
- **`--only-id`.** Kind was too coarse to aim a paid run: the five shipped surfaces are
  one kind, so measuring three of them bought all five. An unknown id raises rather than
  narrowing silently — a typo that spends real money and reports a rate over a set nobody
  chose is this package's own complaint one level up.

**The arm.** Commit `006df42`, question set `7fe9b7cc12a6` (the three ids), **35 repeats ×
3 questions = 105 paid runs**, 0 errors, 0 unmetered calls, 0 tool rounds. `grounded_ask`
is called directly, so no repeat is served from the per-day `kv` cache.

| | pre-#95 (the pair) | post-#95 (merged) |
|---|---|---|
| **night ships** | **35/35 = 100.0%** [95% CI 90.1–100.0] | **35/35 = 100.0%** [95% CI 90.1–100.0] |
| paired (McNemar, exact) | — | 0 worse, 0 better, **p = 1.000** |
| *F* — merged fails both attempts | — | **0/35 = 0.0%** [95% CI 0.0–9.9] |
| first-pass gate rate | **13/35 = 37.1%** [23.2–53.7] | **28/35 = 80.0%** [64.1–90.0] |
| paired (McNemar, exact) | — | 5 worse, 20 better, **p = 0.004 — significant** |
| input tokens / night (provider-counted) | 109,557 | 48,763 — paired **−60,794 (−55.5%), 95% CI −73,277 to −48,310, sign ESTABLISHED** |
| model calls / night | 2.80 | 1.20 — paired **−1.60, 95% CI −1.91 to −1.29, sign established** |
| citations / shipped night | 3.83 | 3.37 — paired −0.46, **95% CI −1.13 to +0.21, sign NOT established** |
| spend / night (PRICING §6 *assumed* rates) | $0.0556 | $0.0249 (−55.2%) |

**Availability: a null, and the honest size of that null.** Not one generation of the 105
fell back — no `fallback`, no `refused`, no gate WARNING logged anywhere in the run. With
zero discordant pairs at n = 35 nights, the exact one-sided 95% bound on the merge's
availability regression is **≤ 8.2 points**. So this does not prove equivalence; it says a
regression bigger than about eight points is excluded, and none was seen. Note also that
availability *cannot* be worse than the pair by construction — a failed merge falls back to
the pair — so what n = 35 is really bounding is the **wasted merged attempt**, i.e. *F*.

**And *F* is the number #95 actually needs.** The docstring derives break-even at **F =
0.5**: the merge is cheaper whenever the merged candidate's total-failure rate is under
half. Measured **F = 0/35, upper bound 9.9%** — a factor of five inside the line. Its cost
model, evaluated on the measured rates (*a* = 0.800, *s* = 0.600), predicts **2.80 calls
before and 1.20 after**; the arm observed **2.80 and 1.20**. The model was right.

**The merged prompt clears the gates MORE often, and part of that is arithmetic.** 80.0%
vs the pair's 37.1% is significant (p = 0.004), but a pair has two candidates and therefore
two chances to fail: 48.6% × 71.4% = 34.7% against 37.1% observed, so the pair's joint rate
is very nearly just the product. That is a real property of merging — one judged candidate
instead of two — and not a claim that the prose got better. The like-for-like comparison,
one candidate against one candidate, is **merged 80.0% vs briefing 48.6% (5 worse, 16
better, p = 0.027 — significant)** and **merged 80.0% vs action 71.4% (6 worse, 9 better,
p = 0.607 — not significant)**. The briefing prompt is the one the merge improves on; the
action prompt it merely matches.

**#95 UNDERSTATED its own saving.** The shipped claim is −47.6%; the billed traffic says
**−55.5% per night, sign established**. The gap is not measurement error, it is what the
counted figure could not see: tiktoken compared *prompts*, one call each, but a night does
not cost one call each. The pair costs **2.80** calls and the merged call **1.20**, because
every nudged retry re-sends the whole prompt. Removing a call removes its retries too.

**Nulls, stated as nulls.** Citations per shipped night moved −0.46 with a 95% interval of
−1.13 to +0.21 — **sign not established**. One merged answer cites about as much as two
separate answers between them; this arm cannot say it cites less.

**What this does not cover.** One seeded owner (the contract dataset), one model tier, one
commit, one day of data repeated 35 times — the between-DAY variance is not inside any
interval here, and the same limitation applies to §9.1 and §9.3. The rates are conditional
on a pipeline whose ship rate currently sits at the ceiling; if the ship rate ever falls
again, *F* is the number to re-measure, because it is the only one the merge's economics
depend on.

**Verdict: the merge holds.** It ships as reliably as the two prompts it replaced (null,
bounded at ≤8.2 points), it wastes nothing (F = 0/35, break-even 0.5), it is significantly
more likely to clear the gates on the first attempt, and it saves **more** than it claimed.
Nothing changes as a result — which is the correct outcome for a measurement that was owed
on something already shipped.

**Spend.** Two runs (a 3-run calibration pilot and the 105-run arm). Harness figure, tokens
**counted** × `PRICING.md` §6's **assumed** default-tier rates: **$2.90**. Actually
**billed**, from the account's own `total_usage` across the window that contained both runs:
**$0.568** ($204.568 → $205.136) — an upper bound, because the account is shared and other
traffic lands in the same delta. The two differ by ~5× because §6's $0.50/$3.00 is the
default-tier assumption, not the batch model's real price; every dollar figure in this
section and in §9.1–9.3 is tokens × that assumption and should be read as one.
