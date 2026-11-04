#!/usr/bin/env bash
# Matched, stage-by-stage OpenROAD Flow Scripts (ORFS) experiment.
# Usage: bash research/readpath/scripts/run_orfs_stage.sh 8x16 baseline synth
# Prerequisites: WSL/Linux, a working ORFS flow checkout, OPENROAD_FLOW_ROOT=/path/to/OpenROAD-flow-scripts
set -euo pipefail

if [[ $# != 3 ]]; then
  echo "usage: $0 {8x16|32x32} {baseline|decoder} {preflight|synth|floorplan|place|cts|grt|route|finish}" >&2
  exit 2
fi

size="$1"; mode="$2"; stage="$3"
case "$size" in 8x16|32x32) ;; *) echo "Unsupported size: $size" >&2; exit 2;; esac
case "$mode" in baseline|decoder) ;; *) echo "Unsupported architecture: $mode" >&2; exit 2;; esac
case "$stage" in preflight|synth|floorplan|place|cts|grt|route|finish) ;; *) echo "Unsupported stage: $stage" >&2; exit 2;; esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
orfs="${OPENROAD_FLOW_ROOT:-}"
if [[ -z "$orfs" || ! -f "$orfs/flow/Makefile" ]]; then
  echo "Set OPENROAD_FLOW_ROOT to an existing OpenROAD-flow-scripts checkout (parent directory of flow/)" >&2
  exit 2
fi
orfs="$(cd "$orfs" && pwd)"
config="$root/research/readpath/orfs/${size}_${mode}.mk"
export READPATH_REPO_ROOT="$root"
variant="readpath-v1"
nickname="fifo_readpath_${size}_${mode}"
flow="$orfs/flow"
local_root="$root/research/readpath/runs/$size/$mode"
mkdir -p "$local_root"

# Ensure experiment metadata is tracked independent of the route reports.
{
  echo "size=$size"
  echo "architecture=$mode"
  echo "stage=$stage"
  echo "design_config=$config"
  echo "flow_variant=$variant"
  echo "openroad_flow_root=$orfs"
  echo "readpath_repo_revision=$(git -C "$root" rev-parse HEAD)"
  echo "readpath_repo_dirty=$(if [[ -n "$(git -C "$root" status --porcelain)" ]]; then echo yes; else echo no; fi)"
  echo "orfs_revision=$(git -C "$orfs" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "orfs_dirty=$(if [[ -n "$(git -C "$orfs" status --porcelain 2>/dev/null || true)" ]]; then echo yes; else echo no; fi)"
  echo "recorded_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "sdc_sha256=$(sha256sum "$root/research/readpath/orfs/constraint.sdc" | awk '{print $1}')"
  echo "rtl_sha256=$(sha256sum "$root/$(if [[ "$mode" == baseline ]]; then echo rtl/fifo_sync.v; else echo research/readpath/rtl/fifo_sync_onehot.v; fi)" | awk '{print $1}')"
} > "$local_root/manifest.txt"

make_args=( "-C" "$flow" "DESIGN_CONFIG=$config" "FLOW_VARIANT=$variant" )
if [[ "$stage" == preflight ]]; then
  echo "Preflight: make will report intended synthesis commands; no implementation will run."
  make "${make_args[@]}" -n synth > "$local_root/make_dry_run.txt"
  grep -m 5 -E 'yosys|openroad|synth.sh' "$local_root/make_dry_run.txt" || true
  echo "PASS: ORFS Makefile parsed and a synthesis recipe was generated."
  exit 0
fi

echo "=== Running $size $mode through $stage on ORFS ==="
echo "ORFS revision: $(git -C "$orfs" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "Repo RTL revision: $(git -C "$root" rev-parse --short HEAD)"
echo "Config: $config"
echo "Stage: $stage"

# No cleaning between stages: each make goal reuses earlier artifacts
# from this design nickname/variant, and must not share directories
# with the other architecture.
make "${make_args[@]}" "$stage" 2>&1 | tee "$local_root/${stage}_console.log"

# This folder naming follows ORFS Makefile + variables.mk defaults.
base="nangate45/$nickname/$variant"
report_src="$flow/reports/$base"
log_src="$flow/logs/$base"
result_src="$flow/results/$base"

stage_dir="$local_root/stages/$stage"
mkdir -p "$stage_dir/reports" "$stage_dir/logs"
case "$stage" in
  synth) prefix="1_" ;;
  floorplan) prefix="2_" ;;
  place) prefix="3_" ;;
  cts) prefix="4_" ;;
  grt) prefix="5_1_" ;;
  route) prefix="5_" ;;
  finish) prefix="6_" ;;
esac

# Checkpoints are copied, never moved; original ORFS artifacts are retained.
# Stage-specific reports/logs are curated for later comparison. Checkpoints
# (ODB/DEF/GDS) stay in ORFS results and are not committed to GitHub.
for spec in "reports:$report_src" "logs:$log_src"; do
  kind="${spec%%:*}"; src="${spec#*:}"
  [[ -d "$src" ]] || continue
  find "$src" -maxdepth 1 -type f -name "$prefix*" -print0 |
    while IFS= read -r -d '' file; do
      cp -p "$file" "$stage_dir/$kind/"
    done
done

{
  echo "stage=$stage"
  echo "completed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "orfs_report_dir=$report_src"
  echo "orfs_log_dir=$log_src"
  echo "orfs_result_dir=$result_src"
  echo "files_copied=$(find "$stage_dir" -type f | wc -l)"
} > "$stage_dir/stage_manifest.txt"

echo "Saved local stage evidence: $stage_dir"
echo "Original ORFS checkpoint database: $result_src"
echo "Run the next stage only after inspecting this stage's reports."
