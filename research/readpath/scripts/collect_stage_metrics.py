#!/usr/bin/env python3
"""Export OpenROAD per-stage raw metrics from research/readpath/runs.

This script reports exactly what the stored tool JSON contains. It does not
guess unavailable timing values, conflate setup worst slack with WNS, or
equate place estimates with post-route extracted delay.
"""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / "runs"
OUTPUT = ROOT / "runs" / "stage_metrics_long.csv"
FIELDS = ("size", "architecture", "stage", "source", "metric", "value")
STAGES = ["synth", "floorplan", "place", "cts", "grt", "route", "finish"]
FILTERS = (
    "__timing__",
    "__design__instance__",
    "__route__",
    "__power__",
    "__clock__",
    "__congestion__",
)


def flatten(obj, prefix=""):
    if isinstance(obj, dict):
        for k, value in obj.items():
            yield from flatten(value, f"{prefix}.{k}" if prefix else str(k))
    elif isinstance(obj, (int, float, bool, str)):
        yield prefix, obj


def main():
    rows = []
    for size in ("8x16", "32x32"):
        for arch in ("baseline", "decoder"):
            for stage in STAGES:
                path = RUNS / size / arch / "stages" / stage
                if not path.is_dir():
                    continue
                for metric_file in sorted(path.rglob("*.json")):
                    try:
                        data = json.loads(metric_file.read_text(encoding="utf-8"))
                    except (ValueError, UnicodeDecodeError):
                        continue
                    if not isinstance(data, dict):
                        continue
                    for metric, value in flatten(data):
                        if any(fragment in metric for fragment in FILTERS):
                            rows.append({
                                "size": size,
                                "architecture": arch,
                                "stage": stage,
                                "source": str(metric_file.relative_to(RUNS)),
                                "metric": metric,
                                "value": value,
                            })
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} source-attributed metric values to {OUTPUT}")
    if not rows:
        print("No stage JSON metrics found yet. Run stages or inspect tool report files.")


if __name__ == "__main__":
    main()
