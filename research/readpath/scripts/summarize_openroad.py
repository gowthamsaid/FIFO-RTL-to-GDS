#!/usr/bin/env python3
"""Audit-friendly paired post-route metrics. Never infer absent measurements."""
import csv
import json
import pathlib
import re
import sys


def require_match(pattern, text, label, flags=0):
    matches = list(re.finditer(pattern, text, flags))
    if not matches:
        raise ValueError(f"Missing {label}; refusing an unsupported comparison")
    return matches[0]


def read_target(path):
    text = pathlib.Path(path).read_text()
    first = text.split("Startpoint:", 2)
    if len(first) < 2:
        raise ValueError(f"No constrained paths in {path}")
    part = "Startpoint:" + first[1]
    start = require_match(r"(?m)^Startpoint:\s*(.+)$", part, "startpoint").group(1)
    end = require_match(r"(?m)^Endpoint:\s*(.+)$", part, "endpoint").group(1)
    arrival = float(require_match(r"(?m)^\s*([-+]?\d+\.\d+)\s+data arrival time\s*$",
                                  part, "data arrival").group(1))
    slack = float(require_match(r"(?m)^\s*([-+]?\d+\.\d+)\s+slack\s+\((?:MET|VIOLATED)\)",
                                part, "setup slack").group(1))
    # Full-clock-expanded line at launch FF /CK precedes launch FF /Q.
    # Extract the Time column, not the incremental delay column.
    launch = re.search(
        r"(?m)^\s*(?:\d+\s+[\d.]+\s+[\d.]+\s+)?[\d.]+\s+([\d.]+)\s+\^\s+read_ptr\[[^\n]+/CK",
        part)
    if launch is None:
        # Conservative fallback: locate launch CK line and take the last
        # numeric token before the edge marker.
        launch_line = next((line for line in part.splitlines()
                            if "read_ptr[" in line and "/CK" in line), None)
        if launch_line is None:
            raise ValueError("Cannot find launch FF clock pin")
        tokens = launch_line.split(" ^ ")[0].split()
        try:
            clock_insertion = float(tokens[-1])
        except (ValueError, IndexError):
            raise ValueError("Cannot parse launch clock insertion") from None
    else:
        clock_insertion = float(launch.group(1))
    if not (0 <= clock_insertion < arrival):
        raise ValueError("Unreasonable clock insertion; inspect raw STA report")
    return {
        "startpoint": start, "endpoint": end,
        "arrival_including_clock_ns": arrival,
        "launch_clock_insertion_ns": clock_insertion,
        "clock_to_data_ns": round(arrival - clock_insertion, 6),
        "setup_slack_ns": slack,
        "report": pathlib.Path(path).name,
    }


def maybe_number(d, *keys):
    for key in keys:
        if isinstance(d.get(key), (float, int)):
            return d[key]
    return None


def summarize(directory, arch, width, depth, geometry):
    p = pathlib.Path(directory)
    finish = (p / f"{arch}_6_finish.rpt").read_text()
    stat = (p / f"{arch}_synth_stat.txt").read_text()
    route = (p / f"{arch}_5_2_route.log").read_text()
    metric_path = p / f"{arch}_6_report.json"
    metrics = json.loads(metric_path.read_text()) if metric_path.exists() else {}
    area_synth = float(require_match(r"Chip area for module.*?:\s*([\d.]+)",stat,"synthesis area").group(1))
    finish_slack = float(require_match(r"(?m)^worst slack max\s+([-+]?\d+(?:\.\d+)?)",finish,"worst setup slack").group(1))
    hold = float(require_match(r"(?s)finish report_checks -path_delay min.*?([-+]?\d+\.\d+)\s+slack\s+\(MET\)",finish,"worst hold slack").group(1))
    final_area_matches = list(re.finditer(r"Design area\s+([\d.]+)\s+um\^2",route))
    area_final = float(final_area_matches[-1].group(1)) if final_area_matches else None
    viols = [int(x) for x in re.findall(r"Number of violations\s*=\s*(\d+)",route)]
    if not viols or viols[-1] != 0:
        raise ValueError(f"{arch}: detailed router did not finish with 0 violations")
    lengths = re.findall(r"Total wire length\s*=\s*(\d+)\s*um",route)
    vias = re.findall(r"Total number of vias\s*=\s*(\d+)",route)
    if not lengths or not vias:
        raise ValueError(f"{arch}: missing detailed routing length / vias")
    target = read_target(p / f"{arch}_readpath-targeted.rpt")
    summary = {
        "config": f"{width}x{depth}", "architecture": arch, "geometry": geometry,
        "units": {"time": "ns", "area": "um^2", "wire_length": "um"},
        "synthesis_cell_area_um2": area_synth,
        "final_cell_area_rounded_um2": area_final,
        "worst_overall_setup_slack_ns": finish_slack,
        "worst_hold_slack_ns": hold,
        "routing_drc_final": viols[-1],
        "routing_wire_length_um": int(lengths[-1]),
        "routing_vias": int(vias[-1]),
        "read_path": target,
        "finish_area_from_json": maybe_number(metrics,"finish__design__instance__area__stdcell",
                                              "finish__design__instance__area"),
        "source_report": f"{arch}_6_finish.rpt",
    }
    (p / f"{arch}_summary.json").write_text(json.dumps(summary,indent=2)+"\n")


def compare(a_file, b_file, output):
    a = json.loads(pathlib.Path(a_file).read_text())
    b = json.loads(pathlib.Path(b_file).read_text())
    if a["config"] != b["config"] or a["geometry"] != b["geometry"]:
        raise ValueError("Mismatched comparison dimensions or geometry")
    delta = {}
    for field in ("synthesis_cell_area_um2", "final_cell_area_rounded_um2",
                  "worst_overall_setup_slack_ns", "worst_hold_slack_ns",
                  "routing_wire_length_um", "routing_vias"):
        if isinstance(a[field], (int,float)) and isinstance(b[field],(int,float)):
            delta[field] = b[field]-a[field]
    read_a = a["read_path"]["clock_to_data_ns"]
    read_b = b["read_path"]["clock_to_data_ns"]
    delta["readpath_clock_to_data_ns"] = round(read_b-read_a,6)
    delta["readpath_improvement_pct"] = round((read_a-read_b)/read_a*100,4)
    delta["readpath_setup_slack_ns"] = round(
        b["read_path"]["setup_slack_ns"]-a["read_path"]["setup_slack_ns"],6)
    result = {"configuration":a["config"],"geometry":a["geometry"],
              "baseline":a, "decoder":b,"decoder_minus_baseline":delta}
    pathlib.Path(output).write_text(json.dumps(result,indent=2)+"\n")


def write_csv(comp_file, out_file):
    data=json.loads(pathlib.Path(comp_file).read_text())
    a,b,d=data["baseline"],data["decoder"],data["decoder_minus_baseline"]
    rows=[
        ("synthesis_cell_area_um2",a["synthesis_cell_area_um2"],b["synthesis_cell_area_um2"]),
        ("final_cell_area_rounded_um2",a["final_cell_area_rounded_um2"],b["final_cell_area_rounded_um2"]),
        ("readpath_clock_to_data_ns",a["read_path"]["clock_to_data_ns"],b["read_path"]["clock_to_data_ns"]),
        ("readpath_setup_slack_ns",a["read_path"]["setup_slack_ns"],b["read_path"]["setup_slack_ns"]),
        ("overall_worst_setup_slack_ns",a["worst_overall_setup_slack_ns"],b["worst_overall_setup_slack_ns"]),
        ("worst_hold_slack_ns",a["worst_hold_slack_ns"],b["worst_hold_slack_ns"]),
        ("routed_wire_length_um",a["routing_wire_length_um"],b["routing_wire_length_um"]),
        ("routing_vias",a["routing_vias"],b["routing_vias"]),
    ]
    with pathlib.Path(out_file).open("w",newline="") as f:
        w=csv.writer(f)
        w.writerow(["configuration","geometry","metric","baseline","decoder","decoder_minus_baseline"])
        for metric,base,alt in rows:
            w.writerow([data["configuration"],data["geometry"],metric,base,alt,
                        "" if base is None or alt is None else round(alt-base,6)])
        w.writerow([data["configuration"],data["geometry"],"readpath_improvement_pct","", "",
                    d["readpath_improvement_pct"]])


if __name__=="__main__":
    if len(sys.argv)>=2 and sys.argv[1]=="summarize" and len(sys.argv)==7:
        summarize(*sys.argv[2:])
    elif len(sys.argv)==5 and sys.argv[1]=="compare":
        compare(*sys.argv[2:])
    elif len(sys.argv)==4 and sys.argv[1]=="csv":
        write_csv(*sys.argv[2:])
    else:
        sys.exit("Usage: summarize DIR ARCH WIDTH DEPTH GEOMETRY | compare BASE DEC OUT | csv COMPARISON OUT")
