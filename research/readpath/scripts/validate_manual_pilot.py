#!/usr/bin/env python3
"""Strict gate: only permit larger P&R studies if cloud 8x16 reproduces WSL."""
import json
import pathlib
import sys

# Values measured in the manual 2026-11-04 OpenROAD Nangate45 runs.
MANUAL = {
    "baseline": {
        "synthesis_cell_area_um2": 1332.128,
        "final_cell_area_rounded_um2": 1356.0,
        "worst_overall_setup_slack_ns": 1.2864,
        "worst_hold_slack_ns": 0.09,
        "routing_wire_length_um": 5738,
        "routing_vias": 3917,
        "read_path": {
            "arrival_including_clock_ns": 0.7751,
            "launch_clock_insertion_ns": 0.1000,
            "clock_to_data_ns": 0.6751,
            "setup_slack_ns": 1.2864,
        },
    },
    "decoder": {
        "synthesis_cell_area_um2": 1286.642,
        "final_cell_area_rounded_um2": 1322.0,
        "worst_overall_setup_slack_ns": 1.3430,
        "worst_hold_slack_ns": 0.11,
        "routing_wire_length_um": 6724,
        "routing_vias": 4257,
        "read_path": {
            "arrival_including_clock_ns": 0.6057,
            "launch_clock_insertion_ns": 0.1024,
            "clock_to_data_ns": 0.5033,
            "setup_slack_ns": 1.4629,
        },
    },
}
# Explicit numerical reproducibility tolerances, not statistical confidence.
TOLERANCE = {
    "synthesis_cell_area_um2": 0.01, # exact mapped area to 0.01 um^2
    "final_cell_area_rounded_um2": 5.0,
    "worst_overall_setup_slack_ns": 0.010,
    "worst_hold_slack_ns": 0.020,
    "routing_wire_length_um": 100,
    "routing_vias": 100,
    "arrival_including_clock_ns": 0.010,
    "launch_clock_insertion_ns": 0.010,
    "clock_to_data_ns": 0.010,
    "setup_slack_ns": 0.010,
}


def main(folder):
    root=pathlib.Path(folder)
    results=[]
    ok=True
    for arch, expected in MANUAL.items():
        data=json.loads((root/f"{arch}_summary.json").read_text())
        if data.get("routing_drc_final") != 0:
            results.append({"arch":arch,"metric":"routing_drc_final","status":"FAIL"})
            ok=False
        for key, ref in expected.items():
            observed = data.get(key)
            if key=="read_path":
                for sub, ref_value in ref.items():
                    measured = observed.get(sub) if isinstance(observed,dict) else None
                    passed = isinstance(measured,(int,float)) and abs(measured-ref_value)<=TOLERANCE[sub]
                    results.append({"arch":arch,"metric":"read_path."+sub,
                                    "manual":ref_value,"cloud":measured,
                                    "tolerance":TOLERANCE[sub],"status":"PASS" if passed else "FAIL"})
                    ok &= passed
            else:
                passed = isinstance(observed,(int,float)) and abs(observed-ref)<=TOLERANCE[key]
                results.append({"arch":arch,"metric":key,
                                "manual":ref,"cloud":observed,
                                "tolerance":TOLERANCE[key],"status":"PASS" if passed else "FAIL"})
                ok &= passed
    compare=json.loads((root/"comparison.json").read_text())
    got=compare["decoder_minus_baseline"].get("readpath_improvement_pct")
    manual_pct=(.6751-.5033)/.6751*100
    pct_ok=isinstance(got,(float,int)) and abs(got-manual_pct)<=2.0
    results.append({"arch":"paired","metric":"readpath_improvement_pct","manual":round(manual_pct,4),
                    "cloud":got,"tolerance":2.0,"status":"PASS" if pct_ok else "FAIL"})
    ok &= pct_ok
    report={"status":"PASS" if ok else "FAIL",
            "message":("Cloud result reproduces manual 8x16 evidence within defined tolerances."
                      if ok else "Cloud does NOT reproduce the manual 8x16 result. Block expansion and investigate versions, constraints, mapping, and physical seed."),
            "manual_reference":"WSL manual experiment, 2026-11-04; Nangate45 typical, 2ns clock",
            "checks":results}
    (root/"manual-validation.json").write_text(json.dumps(report,indent=2)+"\n")
    with (root/"manual-validation.md").open("w") as f:
        f.write("# 8x16 cloud versus manual reproducibility gate\n\n")
        f.write("**"+report["status"]+"** — "+report["message"]+"\n\n")
        f.write("|Design|Metric|Manual|Cloud|Tolerance|Status|\n|---|---|---:|---:|---:|---|\n")
        for item in results:
            f.write(f"|{item['arch']}|{item['metric']}|{item.get('manual','')}|{item.get('cloud','')}|{item.get('tolerance','')}|{item['status']}|\n")
        f.write("\nDo not interpret a failed gate as a null architectural effect. Compare tool versions, synthesis mapping, SDC, floorplan, OpenROAD options and placement seeds.\n")
    print(report["message"])
    for r in results:
        print(r["status"],r["arch"],r["metric"],"manual=",r.get("manual"),
              "cloud=",r.get("cloud"))
    return 0 if ok else 1


if __name__=="__main__":
    if len(sys.argv)!=2:
        sys.exit("Usage: validate_manual_pilot.py DIR")
    sys.exit(main(sys.argv[1]))
