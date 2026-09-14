"""The CLI: ``run`` one arm (paid, networked), ``compare`` two saved arms (free),
``score`` re-checks one arm's answers for citation support (free, offline).

    uv run python -m tests.grounding_eval run --repeats 3 --out before.json
    uv run python -m tests.grounding_eval compare before.json after.json
    uv run python -m tests.grounding_eval score before.json --out before.scored.json

``run`` TRUNCATES and re-seeds the database it is pointed at — never point it at data
anyone needs. It is deliberately noisy per question: a paid run must be interruptible the
moment its answers start coming back as errors.

⛔ **Use a SEPARATE OpenRouter key, with its own small credit limit.** An arm costs ~$3
and this harness is what emptied the shared account on 2026-08-01 — after which every
production LLM call 402'd for hours behind a green ``/healthz``. A drained eval key must
cost you an eval run, never the live AI layer.

``run`` reads that key from **``EVAL_OPENROUTER_API_KEY``** in ``apps/server/.env``. It is
not a gate: with the variable unset the arm still runs on the production
``OPENROUTER_API_KEY``, after printing a warning to stderr that names the risk. So nothing
breaks the day this lands, and nobody spends production's credit on a 105-run arm without
having been told. Creating the key is an account action and therefore the owner's —
openrouter.ai → Keys → new key with a small credit limit; ``infra/DEPLOY.md`` §E2 has the
steps and the reasoning. ``compare`` spends nothing and says nothing.
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import replace
from pathlib import Path
from typing import TYPE_CHECKING

from tests.grounding_eval import records, report, spend
from tests.grounding_eval.questions import EvalQuestion, by_ids, by_kind
from tests.grounding_eval.records import RunRecord
from tests.grounding_eval.runner import run_questions

from healthee.core.db import close_pool

if TYPE_CHECKING:
    from tests.grounding_eval.support import ClaimSupport


def _select(args: argparse.Namespace) -> tuple[EvalQuestion, ...]:
    """The questions this run will pay for — by id if named, else by kind.

    ``--only-id`` exists because kind is too coarse to aim a paid run: the five shipped
    surfaces are one kind, so measuring three of them would buy all five.
    """
    if args.only_id:
        return by_ids(args.only_id)
    return by_kind(set(args.only) if args.only else None)


def _run(args: argparse.Namespace) -> int:
    questions = _select(args)
    if not questions:
        print(f"no questions match --only {args.only}", file=sys.stderr)
        return 2
    spend.select_api_key()  # before any paid call: whose credit this arm is about to spend
    run = records.new_run(args.label, questions, args.repeats)
    total = len(questions) * args.repeats
    print(f"{args.label}: {len(questions)} question(s) × {args.repeats} = {total} paid runs\n")
    for index, record in enumerate(run_questions(run, questions, args.repeats), start=1):
        print(
            f"[{index:>3}/{total}] {record.question_id:<20} {record.outcome:<9} "
            f"calls={record.llm_calls} tools={record.tool_rounds} "
            f"in={record.prompt_tokens:>6} cites={len(record.citations)} "
            f"{record.latency_ms:>6} ms {record.error}",
            flush=True,  # a redirected run must still be watchable line by line
        )
    records.save(run, Path(args.out))
    print("\n" + report.summary(run))
    print(f"\nwritten: {args.out}")
    close_pool()  # the pool's worker threads outlive main() otherwise, and say so loudly
    return 0


def _score(args: argparse.Namespace) -> int:
    """Re-score one saved arm's ``answer`` text for citation SUPPORT — free, offline.

    Never overwrites ``arm``: the scored copy is always a NEW file at ``--out``, so a
    scoring run can be re-tried with a different ``--threshold`` without losing the
    unscored original. A record whose question never shipped an answer (``outcome !=
    grounded``) has no claims to support and is carried through untouched — its support
    fields stay at their zero default, not an error. A grounded record with an empty
    ``answer`` predates answer capture; it is counted and reported, never guessed at.
    """
    from tests.grounding_eval import support  # lazy: optional until the real scorer lands

    run = records.load(Path(args.arm))
    scored: list[RunRecord] = []
    no_answer = 0
    for record in run.records:
        if record.outcome != records.GROUNDED or not record.answer:
            if record.outcome == records.GROUNDED and not record.answer:
                no_answer += 1
            scored.append(record)
            continue
        result = support.score_answer(record.answer, threshold=args.threshold)
        scored.append(
            replace(
                record,
                support_claims=result.claims,
                support_cited=result.cited_claims,
                support_supported=result.supported,
                support_threshold=result.threshold,
                support_unsupported=[c.sentence for c in result.details if not c.supported],
                support_model=os.environ.get("HEALTHEE_SUPPORT_MODEL") or support.DEFAULT_MODEL,
                support_details=[_claim_detail(c) for c in result.details],
                support_unscorable=result.unscorable,
            )
        )
    if no_answer:
        print(f"{no_answer} records have no answer text (arm predates answer capture)")
    records.save(replace(run, records=scored), Path(args.out))
    print(f"written: {args.out}")
    return 0


def _claim_detail(claim: ClaimSupport) -> dict:
    """One ``support.ClaimSupport`` as the plain dict ``RunRecord.support_details`` stores
    — so an "unsupported" verdict can be audited from the saved arm alone, offline."""
    return {
        "sentence": claim.sentence,
        "fragments": list(claim.fragments),
        "cited": list(claim.cited),
        "best_ref": claim.best_ref,
        "best_fragment": claim.best_fragment,
        "entailment": claim.entailment,
        "contradiction": claim.contradiction,
        "supported": claim.supported,
        "interpretive": claim.interpretive,
        "scorable": claim.scorable,
    }


def _calibrate(args: argparse.Namespace) -> int:
    """Sample a labelling sheet from a scored arm, or report precision/recall/F1 from one.

    Two disjoint modes, chosen by ``--report``: sampling reads a v2-scored arm's
    ``support_details`` and writes ``--out`` for a human to fill in; reporting reads
    those filled-in ``--labels`` back and scores the scorer against them, optionally at
    a second checkpoint (``--model``) with no re-run of the paid arm at all.
    """
    if args.report:
        return _calibrate_report(args)
    if not args.arm or not args.out:
        print(
            "calibrate: sampling needs an arm AND --out, or --labels ... --report",
            file=sys.stderr,
        )
        return 2
    from tests.grounding_eval import calibrate  # lazy: same reason as `support` in `_score`

    run = records.load(Path(args.arm))
    sheet = calibrate.sample(run, n=args.sample, seed=args.seed)
    calibrate.write_sheet(sheet, Path(args.out))
    print(f"written: {args.out} ({len(sheet)} claims)")
    return 0


def _calibrate_report(args: argparse.Namespace) -> int:
    if not args.labels:
        print("calibrate --report needs --labels sheet.json", file=sys.stderr)
        return 2
    from tests.grounding_eval import calibrate

    labels = calibrate.load_sheet(Path(args.labels))
    model = os.environ.get("HEALTHEE_SUPPORT_MODEL") or "the arm's as-scored model"
    print(f"-- {model} (as scored) --")
    print(calibrate.report(labels))
    if args.model:
        from tests.grounding_eval import support

        nli = support._load_nli_for(args.model)
        print(f"\n-- {args.model} (re-scored) --")
        print(calibrate.report(labels, nli=nli))
    return 0


def _compare(args: argparse.Namespace) -> int:
    first, second = records.load(Path(args.before)), records.load(Path(args.after))
    print(report.summary(first) + "\n\n" + report.summary(second) + "\n")
    print(report.comparison(first, second))
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="tests.grounding_eval", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    run_cmd = sub.add_parser("run", help="run the set against the REAL model (costs money)")
    run_cmd.add_argument("--repeats", type=int, default=3, help="runs per question (default 3)")
    run_cmd.add_argument("--out", required=True, help="where to write the arm's JSON")
    run_cmd.add_argument("--label", default="arm", help="a name for this arm")
    narrowing = run_cmd.add_mutually_exclusive_group()
    narrowing.add_argument("--only", nargs="*", help="restrict to these question kinds")
    narrowing.add_argument(
        "--only-id",
        nargs="+",
        help="restrict to these exact question ids (an unknown id is an error, not a smaller run)",
    )
    run_cmd.set_defaults(func=_run)

    cmp_cmd = sub.add_parser("compare", help="paired comparison of two saved arms (free)")
    cmp_cmd.add_argument("before")
    cmp_cmd.add_argument("after")
    cmp_cmd.set_defaults(func=_compare)

    score_cmd = sub.add_parser(
        "score", help="re-score a saved arm's answers for citation support (free, offline)"
    )
    score_cmd.add_argument("arm", help="the arm JSON to score — never modified")
    score_cmd.add_argument("--out", required=True, help="where to write the SCORED arm's JSON")
    score_cmd.add_argument(
        "--threshold",
        type=float,
        default=0.5,
        help="entailment threshold for 'supported' (default 0.5)",
    )
    score_cmd.set_defaults(func=_score)

    calib_cmd = sub.add_parser(
        "calibrate", help="sample a labelling sheet from a v2-scored arm, or report on one"
    )
    calib_cmd.add_argument("arm", nargs="?", help="a v2-scored arm JSON to sample claims from")
    calib_cmd.add_argument("--sample", type=int, default=40, help="claims to sample (default 40)")
    calib_cmd.add_argument("--out", help="where to write the labelling sheet")
    calib_cmd.add_argument("--seed", type=int, default=1, help="RNG seed (same seed, same sample)")
    calib_cmd.add_argument("--labels", help="a hand-labelled sheet to score, with --report")
    calib_cmd.add_argument(
        "--report", action="store_true", help="print precision/recall/F1 from --labels"
    )
    calib_cmd.add_argument("--model", help="also re-score --labels at this NLI checkpoint")
    calib_cmd.set_defaults(func=_calibrate)

    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
