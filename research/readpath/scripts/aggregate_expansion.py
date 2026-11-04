#!/usr/bin/env python3
"""Consolidate independent paired OpenROAD experiments without inventing missing results.

Usage: python3 research/readpath/scripts/aggregate_expansion.py ARTIFACT_ROOT OUTPUT_ROOT
Artifact name convention: expansion-WIDTHxDEPTH-GEOMETRY-RUNID.
"""
import csv
import json
from pathlib import Path
import sys

EXPECTED = (
    ("32x32", "natural"),
    ("8x64", "natural"),
    ("16x32", "natural"),
    ("32x16", "natural"),
    ("64x8", "natural"),
    ("8x16", "matched"),
    ("32x32", "matched"),
)
REFERENCE = {
    "configuration": "8x16",
    "geometry": "natural",
    "baseline_delay_ns": 0.6826,
    "decoder_delay_ns": 0.5084,
    "improvement_pct": 25.5201,
    "source": "prior cloud run 41891664640 (2026-11-04), NOT this expansion run",
    "url": "https://github.com/gowthamsaid/FIFO-RTL-to-GDS/actions/runs/41891664640",
}


def numeric(v):
    return isinstance(v, (float, int)) and not isinstance(v, bool)


def metric_pair(base, alt):
    if numeric(base) and numeric(alt):
        return base, alt, round(alt - base, 6)
    return base, alt, None


def one_row(comp, source):
    cfg, geom = comp["configuration"], comp["geometry"]
    b, d = comp["baseline"], comp["decoder"]
    bp, dp = b["read_path"], d["read_path"]
    if not all(numeric(x) for x in [bp["clock_to_data_ns"], dp["clock_to_data_ns"]]):
        raise ValueError("Missing read-path delay for " + cfg)
    if bp["clock_to_data_ns"] <= 0:
        raise ValueError("Invalid baseline read-path delay for " + cfg)
    if b["routing_drc_final"] != 0 or d["routing_drc_final"] != 0:
        raise ValueError("Routing violation in " + cfg)
    area_b, area_d, area_delta = metric_pair(
        b["final_cell_area_rounded_um2"], d["final_cell_area_rounded_um2"])
    wire_b, wire_d, wire_delta = metric_pair(
        b["routing_wire_length_um"], d["routing_wire_length_um"])
    via_b, via_d, via_delta = metric_pair(b["routing_vias"], d["routing_vias"])
    return {
        "configuration": cfg,
        "geometry": geom,
        "status": "complete",
        "source": source,
        "baseline_readpath_ns": bp["clock_to_data_ns"],
        "decoder_readpath_ns": dp["clock_to_data_ns"],
        "readpath_improvement_pct": round(
            100 * (bp["clock_to_data_ns"] - dp["clock_to_data_ns"])
            / bp["clock_to_data_ns"], 4),
        "baseline_area_um2": area_b, "decoder_area_um2": area_d,
        "cell_area_change_pct": (round(100 * (area_d - area_b) / area_b, 3)
                                 if numeric(area_b) and area_b else None),
        "baseline_wire_um": wire_b, "decoder_wire_um": wire_d,
        "wire_change_pct": (round(100 * wire_delta / wire_b, 3)
                            if numeric(wire_b) and wire_b else None),
        "baseline_vias": via_b, "decoder_vias": via_d,
        "vias_change_pct": (round(100 * via_delta / via_b, 3)
                            if numeric(via_b) and via_b else None),
        "baseline_setup_slack_ns": b["worst_overall_setup_slack_ns"],
        "decoder_setup_slack_ns": d["worst_overall_setup_slack_ns"],
        "baseline_hold_slack_ns": b["worst_hold_slack_ns"],
        "decoder_hold_slack_ns": d["worst_hold_slack_ns"],
        "baseline_startpoint": bp["startpoint"],
        "baseline_endpoint": bp["endpoint"],
        "decoder_startpoint": dp["startpoint"],
        "decoder_endpoint": dp["endpoint"],
    }


def main(source_root, output_root):
    source_root, output_root = Path(source_root), Path(output_root)
    output_root.mkdir(parents=True, exist_ok=True)
    rows, failures, inventory = [], [], []
    fields = [
        "configuration", "geometry", "status", "source",
        "baseline_readpath_ns", "decoder_readpath_ns", "readpath_improvement_pct",
        "baseline_area_um2", "decoder_area_um2", "cell_area_change_pct",
        "baseline_wire_um", "decoder_wire_um", "wire_change_pct",
        "baseline_vias", "decoder_vias", "vias_change_pct",
        "baseline_setup_slack_ns", "decoder_setup_slack_ns",
        "baseline_hold_slack_ns", "decoder_hold_slack_ns",
        "baseline_startpoint", "baseline_endpoint",
        "decoder_startpoint", "decoder_endpoint",
    ]
    for config, geom in EXPECTED:
        dirs = sorted(source_root.glob("expansion-" + config + "-" + geom + "-*"))
        if len(dirs) != 1:
            failures.append(f"{config} {geom}: expected 1 artifact, found {len(dirs)}")
            inventory.append({"configuration": config, "geometry": geom,
                              "status": "missing/ambiguous", "artifacts": [x.name for x in dirs]})
            continue
        folder = dirs[0]
        manifest = folder / "comparison.json"
        inventory.append({"configuration":config, "geometry":geom,
                          "artifact":folder.name,
                          "file_count":sum(1 for x in folder.rglob("*") if x.is_file()),
                          "comparison_exists":manifest.is_file()})
        if not manifest.exists():
            failures.append(f"{config} {geom}: no comparison.json — see preserved stage logs")
            continue
        try:
            comp = json.loads(manifest.read_text())
            if comp["configuration"] != config or comp["geometry"] != geom:
                raise ValueError("comparison identity mismatched")
            rows.append(one_row(comp, folder.name))
        except (KeyError, ValueError, TypeError, ZeroDivisionError) as exc:
            failures.append(f"{config} {geom}: invalid comparison: {exc}")
    with (output_root / "configuration-comparison.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fields)
        writer.writeheader()
        writer.writerows(rows)
    (output_root / "artifact-inventory.json").write_text(
        json.dumps(inventory, indent=2) + "\n")
    (output_root / "failures.json").write_text(json.dumps(failures, indent=2) + "\n")
    md = [
        "# FIFO read-path expansion — paired routed comparison",
        "",
        "Exploratory cloud experiments. Manual 8x16 cloud-to-WSL wire-length validation",
        "previously failed; this run is **not** proof of numerical reproducibility.",
        "Both architectures within each completed row share the same pinned ORFS revision,",
        "Nangate45 Liberty, 2ns SDC, docker digest and physical-flow configuration.",
        "",
        "## Completed pairs",
        "",
        "| FIFO | Geometry | Baseline read delay (ns) | Decoder read delay (ns) | Improvement | Cell area change | Routed wire change |",
        "|---|---|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        def pct(x):
            return f"{x:+.2f}%" if numeric(x) else "n/a"
        md.append(
            f"| {r['configuration']} | {r['geometry']} | {r['baseline_readpath_ns']:.4f} | "
            f"{r['decoder_readpath_ns']:.4f} | {r['readpath_improvement_pct']:+.2f}% | "
            f"{pct(r['cell_area_change_pct'])} | {pct(r['wire_change_pct'])} |")
    md += [
        "",
        "## Independent earlier cloud reference",
        "",
        f"8x16 natural: baseline **{REFERENCE['baseline_delay_ns']} ns**, decoder "
        f"**{REFERENCE['decoder_delay_ns']} ns**, improvement "
        f"**{REFERENCE['improvement_pct']}%**. "
        f"[Source run]({REFERENCE['url']}); not rerun here.",
        "",
        "## Failures or incomplete pairs",
        "",
    ]
    md += ["- " + f for f in failures] if failures else ["None."]
    md += [
        "",
        "## Interpretation constraints",
        "",
        "- Positive read-path improvement means decoder delay is shorter.",
        "- Negative cell-area/wire change means decoder consumes less.",
        "- These are one-shot implementation results, not a distribution over placement seeds.",
        "- Matched-core and natural-core runs must be analyzed separately.",
        "- Failed or incomplete jobs are excluded, never treated as zero improvement.",
        "- Detailed tool reports and all stage checkpoints reside in each job's artifact.",
    ]
    (output_root / "configuration-comparison.md").write_text("\n".join(md) + "\n")
    print(f"Aggregated {len(rows)}/{len(EXPECTED)} complete paired experiments")
    print("\n".join(md))
    return 0 if not failures else 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: aggregate_expansion.py ARTIFACT_ROOT OUTPUT_ROOT")
    sys.exit(main(*sys.argv[1:]))
