#!/usr/bin/env bash
# Cloud paired experiment: same ORFS/PDK/SDC/density; sequential flow stages.
# Usage: run_openroad_comparison.sh WIDTH DEPTH natural|matched
set -euo pipefail

if [[ $# -ne 3 || ! "$1" =~ ^[0-9]+$ || ! "$2" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 WIDTH DEPTH natural|matched" >&2
  exit 2
fi
width="$1"; depth="$2"; geometry="$3"
if (( width < 1 || depth < 2 || (depth & (depth - 1)) != 0 )); then
  echo "Width must be positive and depth a power of two >= 2" >&2; exit 2
fi
case "$geometry" in natural|matched) ;; *) echo "Invalid geometry: $geometry" >&2; exit 2 ;; esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
orfs_root="${ORFS_ROOT:?Provide pinned ORFS checkout as ORFS_ROOT}"
image="${ORFS_IMAGE:?Provide digest-pinned Docker image as ORFS_IMAGE}"
case "$image" in *@sha256:*) ;; *) echo "ORFS_IMAGE must use a sha256 digest" >&2; exit 2 ;; esac
flow="$orfs_root/flow"
test -f "$flow/Makefile"
out="$repo_root/research-pilot-reports/openroad_${width}x${depth}_${geometry}"
variant="readpath-${geometry}-v1"
mkdir -p "$out"
src="$flow/designs/src/research_readpath"
mkdir -p "$src"
cp "$repo_root/rtl/fifo_sync.v" "$src/baseline.v"
cp "$repo_root/research/readpath/rtl/fifo_sync_onehot.v" "$src/decoder.v"
cp "$repo_root/research/readpath/scripts/readpath_sta.tcl" "$flow/scripts/research_readpath_sta.tcl"

git -C "$repo_root" rev-parse HEAD > "$out/research-commit.txt"
git -C "$orfs_root" rev-parse HEAD > "$out/orfs-commit.txt"
printf '%s\n' "$image" > "$out/docker-image.txt"
sha256sum "$src/baseline.v" "$src/decoder.v" > "$out/rtl-sha256.txt"
sha256sum "$repo_root/research/readpath/orfs/constraint.sdc" > "$out/constraint-sha256.txt"


# Preserve ALL stage reports, logs, intermediate results, and metadata,
# including partial evidence when a tool or validation step fails.
archive_stage_evidence() {
  for arch in baseline decoder; do
    local nickname="readpath_${width}x${depth}_${arch}"
    local base="nangate45/$nickname/$variant"
    local dest="$out/$arch"
    mkdir -p "$dest/stages"
    for kind in reports logs results objects; do
      local origin="$flow/$kind/$base"
      [[ -d "$origin" ]] || continue
      find "$origin" -maxdepth 1 -type f -print0 | while IFS= read -r -d '' file; do
        local name="$(basename "$file")" stage
        case "$name" in
          1_*|synth_*) stage=synth ;;
          2_*) stage=floorplan ;;
          3_*) stage=place ;;
          4_*) stage=cts ;;
          5_1_*|*congestion*) stage=global_route ;;
          5_2_*|5_3_*|5_route*|maze.log) stage=detailed_route ;;
          6_*|readpath-*) stage=finish ;;
          *) stage=miscellaneous ;;
        esac
        mkdir -p "$dest/stages/$stage/$kind"
        cp -p "$file" "$dest/stages/$stage/$kind/$name"
      done
    done
  done
}
trap archive_stage_evidence EXIT

run_stage() {
  local arch="$1" stage="$2" nickname="readpath_${width}x${depth}_${1}"
  local log="$out/${arch}_${stage}.console.log"
  echo "=== ${width}x${depth} $geometry / $arch / $stage ==="
  if ! docker run --rm --user "$(id -u):$(id -g)" \
    -v "$flow:/OpenROAD-flow-scripts/flow" \
    -w /OpenROAD-flow-scripts/flow \
    "$image" bash -lc "source ../env.sh && make -j1 DESIGN_CONFIG=./designs/nangate45/$nickname/config.mk FLOW_VARIANT=$variant $stage" \
    > "$log" 2>&1; then
    echo "FAILED: $arch $stage" >&2
    tail -n 100 "$log" >&2
    return 1
  fi
  tail -n 6 "$log"
}

for arch in baseline decoder; do
  if [[ "$arch" == baseline ]]; then top=fifo_sync; else top=fifo_sync_onehot; fi
  nickname="readpath_${width}x${depth}_${arch}"
  cfg_dir="$flow/designs/nangate45/$nickname"
  mkdir -p "$cfg_dir"
  cp "$repo_root/research/readpath/orfs/constraint.sdc" "$cfg_dir/constraint.sdc"
  cat > "$cfg_dir/config.mk" <<EOF
export DESIGN_NAME = $top
export DESIGN_NICKNAME = $nickname
export PLATFORM = nangate45
export VERILOG_FILES = \$(DESIGN_HOME)/src/research_readpath/$arch.v
export VERILOG_TOP_PARAMS = DATA_WIDTH $width DEPTH $depth
export SDC_FILE = \$(DESIGN_HOME)/nangate45/$nickname/constraint.sdc
export CORE_UTILIZATION = 40
export PLACE_DENSITY = 0.60
export SYNTH_REPEATABLE_BUILD = 1
EOF
  for dir in results logs reports objects; do
    mkdir -p "$flow/$dir/nangate45/$nickname/$variant"
  done
  run_stage "$arch" synth
done

# The matched experiment derives one common die/core from the larger
# synthesized architecture. Both designs receive precisely the same bounds.
if [[ "$geometry" == matched ]]; then
  b="$flow/reports/nangate45/readpath_${width}x${depth}_baseline/$variant/synth_stat.txt"
  d="$flow/reports/nangate45/readpath_${width}x${depth}_decoder/$variant/synth_stat.txt"
  test -s "$b"; test -s "$d"
  max_area="$(python3 - "$b" "$d" <<'PY'
import pathlib, re, sys
areas = []
for p in sys.argv[1:]:
    text = pathlib.Path(p).read_text()
    matches = re.findall(r"Chip area for module.*?:\s*([\d.]+)", text)
    if not matches:
        raise SystemExit("No mapped area in " + p)
    areas.append(float(matches[-1]))
print(max(areas))
PY
)"
  read -r die core_x core_y < <(python3 - "$max_area" <<'PY'
import math, sys
side = math.ceil((math.sqrt(float(sys.argv[1]) / .40) + 2.5) * 2) / 2
print(f"{side:.3f} {side-1.14:.3f} {side-1.40:.3f}")
PY
)
  echo "DIE_AREA=0 0 $die $die; CORE_AREA=1.140 1.400 $core_x $core_y" | tee "$out/matched-geometry.txt"
  for arch in baseline decoder; do
    cfg="$flow/designs/nangate45/readpath_${width}x${depth}_${arch}/config.mk"
    printf 'export DIE_AREA = 0 0 %s %s\nexport CORE_AREA = 1.140 1.400 %s %s\n' \
      "$die" "$die" "$core_x" "$core_y" >> "$cfg"
  done
fi

for arch in baseline decoder; do
  nickname="readpath_${width}x${depth}_${arch}"
  base="nangate45/$nickname/$variant"
  for stage in floorplan place cts grt route finish; do
    run_stage "$arch" "$stage"
  done

  rpt="$flow/reports/$base"
  logs="$flow/logs/$base"
  res="$flow/results/$base"
  test -s "$res/6_final.odb"
  test -s "$res/6_final.spef"
  test -s "$rpt/6_finish.rpt"
  test -f "$rpt/5_route_drc.rpt"
  if [[ -s "$rpt/5_route_drc.rpt" ]]; then
    echo "Detailed routing DRC report is nonempty: $rpt/5_route_drc.rpt" >&2
    exit 1
  fi
  cp "$flow/designs/nangate45/$nickname/config.mk" "$out/${arch}_config.mk"
  cp "$flow/designs/nangate45/$nickname/constraint.sdc" "$out/${arch}_constraint.sdc"
  for p in "$rpt/synth_stat.txt" "$rpt/synth_check.txt" "$rpt/5_route_drc.rpt" "$rpt/6_finish.rpt" \
           "$logs/6_report.json" "$logs/5_2_route.log" ; do
    [[ ! -f "$p" ]] || cp "$p" "$out/${arch}_$(basename "$p")"
  done
  for suffix in sdc spef odb gds def v; do
    cp "$res/6_final.$suffix" "$out/${arch}_6_final.$suffix"
  done

  echo "=== Extracted-SPEF STA: $arch ==="
  if ! docker run --rm --user "$(id -u):$(id -g)" \
    -v "$flow:/OpenROAD-flow-scripts/flow" \
    -w /OpenROAD-flow-scripts/flow \
    -e READPATH_DESIGN_DIR="/OpenROAD-flow-scripts/flow/results/$base" \
    -e READPATH_REPORT_DIR="/OpenROAD-flow-scripts/flow/reports/$base" \
    "$image" bash -lc 'source ../env.sh && openroad -exit ./scripts/research_readpath_sta.tcl' \
    > "$out/${arch}_sta.console.log" 2>&1; then
    tail -n 100 "$out/${arch}_sta.console.log" >&2
    exit 1
  fi
  test -s "$rpt/readpath-targeted.rpt"
  cp "$rpt/readpath-targeted.rpt" "$out/${arch}_readpath-targeted.rpt"

  python3 "$repo_root/research/readpath/scripts/summarize_openroad.py" summarize \
    "$out" "$arch" "$width" "$depth" "$geometry"
done

python3 "$repo_root/research/readpath/scripts/summarize_openroad.py" compare \
  "$out/baseline_summary.json" "$out/decoder_summary.json" "$out/comparison.json"
python3 "$repo_root/research/readpath/scripts/summarize_openroad.py" csv \
  "$out/comparison.json" "$out/comparison.csv"
cat "$out/comparison.csv"
echo "SUCCESS: $width x $depth / $geometry: $out"
