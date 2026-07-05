#!/usr/bin/env python3
"""Aggregate per-run grading.json + timing.json into a single benchmark.json
that the eval-viewer can consume.

Usage:
    python build_benchmark.py <iteration_dir> --skill-name linear-code-leader

Assumes layout:
    <iteration_dir>/
      eval-<id>-<name>/
        eval_metadata.json     (optional, used to fill eval_id/eval_name)
        with_skill/
          outputs/
          grading.json
          timing.json
        without_skill/
          outputs/
          grading.json
          timing.json
"""

import argparse
import json
import math
from datetime import datetime, timezone
from pathlib import Path


def stats(values):
    if not values:
        return {"mean": 0.0, "stddev": 0.0, "min": 0.0, "max": 0.0}
    n = len(values)
    mean = sum(values) / n
    if n > 1:
        var = sum((x - mean) ** 2 for x in values) / (n - 1)
        sd = math.sqrt(var)
    else:
        sd = 0.0
    return {
        "mean": round(mean, 4),
        "stddev": round(sd, 4),
        "min": round(min(values), 4),
        "max": round(max(values), 4),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("iteration_dir", type=Path)
    ap.add_argument("--skill-name", default="linear-code-leader")
    args = ap.parse_args()

    iteration_dir: Path = args.iteration_dir.resolve()
    assert iteration_dir.is_dir(), iteration_dir

    runs = []
    by_config = {}

    eval_dirs = sorted([p for p in iteration_dir.iterdir() if p.is_dir() and p.name.startswith("eval-")])
    eval_ids = []
    for eval_dir in eval_dirs:
        meta_path = eval_dir / "eval_metadata.json"
        if meta_path.exists():
            meta = json.loads(meta_path.read_text())
            eval_id = meta.get("eval_id")
            eval_name = meta.get("eval_name", eval_dir.name)
        else:
            try:
                eval_id = int(eval_dir.name.split("-")[1])
            except ValueError:
                eval_id = None
            eval_name = eval_dir.name
        if eval_id is not None:
            eval_ids.append(eval_id)

        for config_dir in sorted(eval_dir.iterdir()):
            if not config_dir.is_dir():
                continue
            if config_dir.name not in ("with_skill", "without_skill"):
                continue
            grading_path = config_dir / "grading.json"
            if not grading_path.exists():
                print(f"missing grading.json: {grading_path}")
                continue
            grading = json.loads(grading_path.read_text())
            summary = grading.get("summary", {})
            timing_path = config_dir / "timing.json"
            timing = {}
            if timing_path.exists():
                try:
                    timing = json.loads(timing_path.read_text())
                except Exception:
                    timing = {}
            run = {
                "eval_id": eval_id if eval_id is not None else 0,
                "eval_name": eval_name,
                "configuration": config_dir.name,
                "run_number": 1,
                "result": {
                    "pass_rate": summary.get("pass_rate", 0.0),
                    "passed": summary.get("passed", 0),
                    "failed": summary.get("failed", 0),
                    "total": summary.get("total", 0),
                    "time_seconds": round(timing.get("total_duration_seconds", 0.0), 2),
                    "tokens": timing.get("total_tokens", 0),
                },
                "expectations": grading.get("expectations", []),
            }
            runs.append(run)
            by_config.setdefault(config_dir.name, []).append(run["result"])

    # Aggregate run_summary
    run_summary = {}
    for config, results in by_config.items():
        run_summary[config] = {
            "pass_rate": stats([r["pass_rate"] for r in results]),
            "time_seconds": stats([r["time_seconds"] for r in results]),
            "tokens": stats([float(r["tokens"]) for r in results]),
        }

    # Delta (with_skill - without_skill where present)
    delta = {}
    if "with_skill" in run_summary and "without_skill" in run_summary:
        for metric in ("pass_rate", "time_seconds", "tokens"):
            w = run_summary["with_skill"][metric]["mean"]
            b = run_summary["without_skill"][metric]["mean"]
            diff = w - b
            sign = "+" if diff >= 0 else ""
            delta[metric] = f"{sign}{round(diff, 4)}"
    if delta:
        run_summary["delta"] = delta

    # Order: with_skill first, then without_skill (per skill-creator guidance)
    runs.sort(key=lambda r: (r["eval_id"], 0 if r["configuration"] == "with_skill" else 1))

    benchmark = {
        "metadata": {
            "skill_name": args.skill_name,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "evals_run": eval_ids,
            "runs_per_configuration": 1,
        },
        "runs": runs,
        "run_summary": run_summary,
        "notes": [],
    }

    out_json = iteration_dir / "benchmark.json"
    out_json.write_text(json.dumps(benchmark, ensure_ascii=False, indent=2))

    # Also write a simple benchmark.md summary
    lines = [f"# Benchmark: {args.skill_name}", "",
             f"Generated: {benchmark['metadata']['timestamp']}", ""]
    lines.append("## Configuration summary")
    lines.append("")
    lines.append("| Config | pass_rate (mean ± sd) | time_s (mean) | tokens (mean) |")
    lines.append("|---|---|---|---|")
    for cfg in ("with_skill", "without_skill"):
        if cfg not in run_summary:
            continue
        s = run_summary[cfg]
        lines.append(
            f"| {cfg} | {s['pass_rate']['mean']} ± {s['pass_rate']['stddev']} | "
            f"{s['time_seconds']['mean']} | {int(s['tokens']['mean'])} |"
        )
    if "delta" in run_summary:
        lines.append("")
        lines.append("## Delta (with_skill − without_skill)")
        d = run_summary["delta"]
        lines.append(f"- pass_rate: {d['pass_rate']}")
        lines.append(f"- time_seconds: {d['time_seconds']}")
        lines.append(f"- tokens: {d['tokens']}")
    lines.append("")
    lines.append("## Per-run pass rates")
    lines.append("")
    lines.append("| eval | config | pass | total | pass_rate | time_s | tokens |")
    lines.append("|---|---|---|---|---|---|---|")
    for r in runs:
        rr = r["result"]
        lines.append(
            f"| {r['eval_name']} | {r['configuration']} | {rr['passed']} | {rr['total']} | "
            f"{rr['pass_rate']} | {rr['time_seconds']} | {rr['tokens']} |"
        )
    out_md = iteration_dir / "benchmark.md"
    out_md.write_text("\n".join(lines))

    print(f"Wrote {out_json}")
    print(f"Wrote {out_md}")


if __name__ == "__main__":
    main()
