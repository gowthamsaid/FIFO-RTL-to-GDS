#!/usr/bin/env python3
"""Summarize verified OpenROAD finish-stage metrics (no third-party packages)."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESIGNS = ("fifo_8x16", "fifo_32x32")

KEYS = {
    "standard_cells": "finish__design__instance__count__stdcell",
    "standard_cell_area_um2": "finish__design__instance__area__stdcell",
    "core_utilization": "finish__design__instance__utilization__stdcell",
    "setup_slack_ns": "finish__timing__setup__ws",
    "hold_slack_ns": "finish__timing__hold__ws",
    "setup_tns_ns": "finish__timing__setup__tns",
    "hold_tns_ns": "finish__timing__hold__tns",
    "setup_violations": "finish__timing__drv__setup_violation_count",
    "hold_violations": "finish__timing__drv__hold_violation_count",
    "estimated_fmax_hz": "finish__timing__fmax",
    "clock_buffers": "finish__design__instance__count__class:clock_buffer",
}


def load_metrics(design):
    path = ROOT / "reports" / design / "6_report.json"
    values = json.loads(path.read_text(encoding="utf-8"))
    result = {name: values[key] for name, key in KEYS.items()}
    assert 0 < result["core_utilization"] < 1
    assert result["standard_cells"] > 0
    assert result["standard_cell_area_um2"] > 0
    assert result["setup_slack_ns"] >= 0
    assert result["hold_slack_ns"] >= 0
    assert result["setup_violations"] == result["hold_violations"] == 0
    assert result["setup_tns_ns"] == result["hold_tns_ns"] == 0
    return result


def main():
    print("Metric                         8x16             32x32")
    print("-" * 61)
    a, b = (load_metrics(name) for name in DESIGNS)
    for key in KEYS:
        print(f"{key:29} {a[key]:>12.6g} {b[key]:>16.6g}")
    print("\nAll checked timing-closure invariants pass.")
    print("STA and power metrics are tool reports, not silicon signoff.")


if __name__ == "__main__":
    main()
