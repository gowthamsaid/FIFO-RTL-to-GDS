#!/usr/bin/env python3
"""Extract audit-friendly OpenROAD metrics without equating WNS and path delay."""
import json
import pathlib
import re
import sys


def number_field(report, *keys):
    for key in keys:
        val = report.get(key)
        if isinstance(val, (int, float)):
            return val
    return None


def path_report(path):
    text = pathlib.Path(path).read_text()
    start = re.search(r"(?m)^Startpoint:\s*(.+)$", text)
    end = re.search(r"(?m)^Endpoint:\s*(.+)$", text)
    arrival = re.search(r"(?m)^\s*([-+]?\d+(?:\.\d+)?)\s+data arrival time\s*$", text)
    slack = re.search(r"(?m)^\s*([-+]?\d+(?:\.\d+)?)\s+slack\s*\((?:MET|VIOLATED)\)", text)
    if not (start and end and arrival and slack):
        raise ValueError("No auditable timed register path in " + str(path))
    return {
        "startpoint": start.group(1).strip(),
        "endpoint": end.group(1).strip(),
        "arrival_time_ns_including_launch_clock": float(arrival.group(1)),
        "setup_slack_ns": float(slack.group(1)),
        "path_report": pathlib.Path(path).name,
    }


def summarize(metrics_path, target_path, global_path, out_path):
    r = json.loads(pathlib.Path(metrics_path).read_text())
    info = {
        "units": {"time": "ns", "standard_cell_area": "um^2"},
        "stdcell_area_um2": number_field(
            r, "finish__design__instance__area__stdcell",
            "finish__design__instance__area"),
        "stdcell_count": number_field(
            r, "finish__design__instance__count__stdcell"),
        "setup_wns_ns": number_field(r, "finish__timing__setup__ws"),
        "setup_tns_ns": number_field(r, "finish__timing__setup__tns"),
        "hold_wns_ns": number_field(r, "finish__timing__hold__ws"),
        "timing_repair_buffers": number_field(
            r, "finish__design__instance__count__class:timing_repair_buffer"),
        "clock_buffers": number_field(
            r, "finish__design__instance__count__class:clock_buffer"),
        "nets": number_field(r, "finish__design__nets"),
        "target_readptr_to_dataout": path_report(target_path),
        "global_worst_path": path_report(global_path),
    }
    pathlib.Path(out_path).write_text(json.dumps(info, indent=2) + "\n")


def compare(base_file, alt_file, out_file):
    b = json.loads(pathlib.Path(base_file).read_text())
    a = json.loads(pathlib.Path(alt_file).read_text())
    result = {"baseline": b, "shared_decoder": a, "delta_decoder_minus_baseline": {}}
    for field in ("stdcell_area_um2", "stdcell_count", "setup_wns_ns",
                  "setup_tns_ns", "hold_wns_ns", "timing_repair_buffers",
                  "clock_buffers", "nets"):
        if b[field] is not None and a[field] is not None:
            result["delta_decoder_minus_baseline"][field] = a[field] - b[field]
    result["delta_decoder_minus_baseline"]["target_readpath_setup_slack_ns"] = (
        a["target_readptr_to_dataout"]["setup_slack_ns"]
        - b["target_readptr_to_dataout"]["setup_slack_ns"])
    # Arrival time contains clock insertion delay: never mislabel it as pure
    # combinational propagation delay or equate it to global clock period.
    result["delta_decoder_minus_baseline"]["target_readpath_arrival_ns"] = (
        a["target_readptr_to_dataout"]["arrival_time_ns_including_launch_clock"]
        - b["target_readptr_to_dataout"]["arrival_time_ns_including_launch_clock"])
    pathlib.Path(out_file).write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] != "--compare":
        summarize(*sys.argv[1:])
    elif len(sys.argv) == 5 and sys.argv[1] == "--compare":
        compare(*sys.argv[2:])
    else:
        raise SystemExit(
            "usage: summarize_openroad.py metrics.json targeted.rpt global.rpt output.json\n"
            "or: summarize_openroad.py --compare baseline.json decoder.json output.json"
        )
