#!/usr/bin/env bash
# Technology-mapped research pilot. Requires: yosys, curl, sha256sum.
# Run from repository root: bash research/readpath/scripts/run_mapped_synthesis.sh WIDTH DEPTH
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 DATA_WIDTH DEPTH" >&2
  exit 2
fi

width="$1"
depth="$2"
if ! [[ "$width" =~ ^[0-9]+$ && "$depth" =~ ^[0-9]+$ ]] || (( width < 1 || depth < 2 || (depth & (depth - 1)) != 0 )); then
  echo "WIDTH must be positive; DEPTH must be a power of two >= 2" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$repo_root"

# Pin the ORFS revision so the same Nangate45 liberty snapshot is used.
orfs_sha="d056a2b304182bf76ff10653531165b1dd9848d4"
liburl="https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD-flow-scripts/${orfs_sha}/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib"
outdir="research-pilot-reports/mapped_${width}x${depth}"
mkdir -p "$outdir"
lib="$outdir/NangateOpenCellLibrary_typical.lib"

echo "Nangate45 typical liberty from ORFS commit: $orfs_sha"
curl --fail --location --retry 3 --silent --show-error "$liburl" --output "$lib"
test -s "$lib"
sha256sum "$lib" | tee "$outdir/liberty.sha256"
yosys -V | tee "$outdir/yosys-version.txt"

for mode in baseline decoder; do
  if [[ "$mode" == baseline ]]; then
    source="rtl/fifo_sync.v"
    top="fifo_sync"
  else
    source="research/readpath/rtl/fifo_sync_onehot.v"
    top="fifo_sync_onehot"
  fi

  # Both use exactly the same technology mapping commands and library.
  yosys -Q -T -l "$outdir/${mode}.log" -p "
    read_verilog $source
    chparam -set DATA_WIDTH $width -set DEPTH $depth $top
    hierarchy -check -top $top
    synth -flatten -top $top
    dfflibmap -liberty $lib
    abc -liberty $lib
    clean -purge
    tee -o $outdir/${mode}_stat.txt stat -liberty $lib
    write_verilog -noattr $outdir/${mode}_mapped.v
  " > /dev/null

  echo "=== $mode ${width}x${depth} mapped Nangate45 ==="
  cat "$outdir/${mode}_stat.txt"
done

echo "Mapped synthesis finished: ${width}x${depth}; compare standard-cell area and gate classes."
echo "WARNING: This is NOT post-route timing or place-and-route."
