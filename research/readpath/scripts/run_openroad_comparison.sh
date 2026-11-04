#!/usr/bin/env bash
# Controlled Nangate45 post-route comparison: identical PDK, SDC, utilization,
# placement density and OpenROAD version, with only read-selection RTL changed.
# Usage: ORFS_ROOT=/path/to/pinned/orfs bash .../run_openroad_comparison.sh 8 16
set -euo pipefail

if [[ "$#" -ne 2 ]] || ! [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]]; then
  echo "usage: $0 DATA_WIDTH DEPTH" >&2
  exit 2
fi
width="$1"
depth="$2"
if (( width < 1 || depth < 2 || (depth & (depth - 1)) != 0 )); then
  echo "WIDTH must be positive; DEPTH must be a power of two >= 2" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
orfs_root="${ORFS_ROOT:?Set ORFS_ROOT to the pinned OpenROAD-flow-scripts checkout}"
flow="$orfs_root/flow"
test -f "$flow/Makefile"

out="$repo_root/research-pilot-reports/openroad_${width}x${depth}"
mkdir -p "$out"
src="$flow/designs/src/research_readpath"
mkdir -p "$src"
cp "$repo_root/rtl/fifo_sync.v" "$src/baseline.v"
cp "$repo_root/research/readpath/rtl/fifo_sync_onehot.v" "$src/decoder.v"

git -C "$orfs_root" rev-parse HEAD > "$out/orfs-commit.txt"
sha256sum "$src/baseline.v" "$src/decoder.v" > "$out/rtl-sha256.txt"
docker image inspect openroad/orfs:latest --format '{{.Id}} {{json .RepoDigests}}' > "$out/docker-image.txt"

for mode in baseline decoder; do
  if [[ "$mode" == baseline ]]; then top=fifo_sync; else top=fifo_sync_onehot; fi
  nickname="readpath_${width}x${depth}_${mode}"
  config_dir="$flow/designs/nangate45/$nickname"
  mkdir -p "$config_dir"
  cat > "$config_dir/config.mk" <<EOF
export DESIGN_NAME = $top
export DESIGN_NICKNAME = $nickname
export PLATFORM = nangate45
export VERILOG_FILES = \$(DESIGN_HOME)/src/research_readpath/$mode.v
export VERILOG_TOP_PARAMS = DATA_WIDTH $width DEPTH $depth
export SDC_FILE = \$(DESIGN_HOME)/nangate45/$nickname/constraint.sdc
export CORE_UTILIZATION = 40
export PLACE_DENSITY = 0.60
export TNS_END_PERCENT = 100
export SYNTH_REPEATABLE_BUILD = 1
EOF
  # Reuse the historical 2.0 ns setup and 0.2 ns I/O delays exactly.
  sed "s/^current_design fifo_sync$/current_design $top/" \
    "$repo_root/openroad/fifo_8x16/constraint.sdc" > "$config_dir/constraint.sdc"
  cp "$config_dir/config.mk" "$out/${mode}_config.mk"
  cp "$config_dir/constraint.sdc" "$out/${mode}_constraint.sdc"

  echo "Running $nickname through full OpenROAD flow..."
  if ! docker run --rm --user "$(id -u):$(id -g)" \
    -v "$flow:/OpenROAD-flow-scripts/flow" \
    -w /OpenROAD-flow-scripts/flow \
    openroad/orfs:latest bash -lc \
    "source ../env.sh && make -j2 DESIGN_CONFIG=./designs/nangate45/$nickname/config.mk" \
    > "$out/${mode}_flow.log" 2>&1; then
      tail -n 140 "$out/${mode}_flow.log" >&2
      exit 1
  fi

  result_dir="$flow/results/nangate45/$nickname/base"
  report_dir="$flow/reports/nangate45/$nickname/base"
  test -s "$result_dir/6_final.odb"
  test -s "$report_dir/6_report.json"
  cp "$report_dir/6_report.json" "$out/${mode}_6_report.json"
  find "$report_dir" -maxdepth 1 -type f -name '6_*.rpt' \
    -exec cp {} "$out/" \;
  # Give generic reports mode-qualified names to avoid overwrites.
  for rpt in "$report_dir"/6_*.rpt; do
    [[ -f "$rpt" ]] || continue
    cp "$rpt" "$out/${mode}_$(basename "$rpt")"
  done

  cp "$repo_root/research/readpath/scripts/readpath_sta.tcl" \
    "$flow/scripts/research_readpath_sta.tcl"
  if ! docker run --rm --user "$(id -u):$(id -g)" \
    -v "$flow:/OpenROAD-flow-scripts/flow" \
    -w /OpenROAD-flow-scripts/flow \
    openroad/orfs:latest bash -lc \
    "source ../env.sh && make DESIGN_CONFIG=./designs/nangate45/$nickname/config.mk RUN_SCRIPT=./scripts/research_readpath_sta.tcl run" \
    > "$out/${mode}_sta.log" 2>&1; then
      tail -n 140 "$out/${mode}_sta.log" >&2
      exit 1
  fi
  cp "$report_dir/readpath-targeted.rpt" "$out/${mode}_readpath-targeted.rpt"
  cp "$report_dir/readpath-global.rpt" "$out/${mode}_readpath-global.rpt"
  python3 "$repo_root/research/readpath/scripts/summarize_openroad.py" \
    "$out/${mode}_6_report.json" "$out/${mode}_readpath-targeted.rpt" \
    "$out/${mode}_readpath-global.rpt" "$out/${mode}_summary.json"
done
python3 "$repo_root/research/readpath/scripts/summarize_openroad.py" \
  --compare "$out/baseline_summary.json" "$out/decoder_summary.json" \
  "$out/comparison.json"
echo "Post-route comparison complete: $out"
