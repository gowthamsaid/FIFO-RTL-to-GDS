#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for cmd in iverilog vvp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: $cmd is required. Install Icarus Verilog." >&2
    exit 127
  fi
done

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_case() {
  local top="$1" width="$2" depth="$3"
  local out="$tmp_dir/${top}_${width}x${depth}.vvp"
  echo "=== ${top}, ${width}-bit x ${depth}-entry ==="

  if [[ "$top" == "fifo_sync_tb" ]]; then
    iverilog -g2012 -s "$top" -o "$out" "rtl/fifo_sync.v" "tb/${top}.v"
  else
    iverilog -g2012 -s "$top" -P "${top}.DATA_WIDTH=${width}" -P "${top}.DEPTH=${depth}" \
      -o "$out" "rtl/fifo_sync.v" "tb/${top}.v"
  fi
  vvp "$out"
}

run_case fifo_sync_tb 8 16
for cfg in "8 16" "32 32"; do
  read -r width depth <<< "$cfg"
  run_case fifo_boundary_tb "$width" "$depth"
  run_case fifo_corner_tb "$width" "$depth"
done

echo "All five directed RTL test cases passed."
