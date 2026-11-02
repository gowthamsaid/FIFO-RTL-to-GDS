# Physical implementation evidence

The October 11, 2026 WSL/OpenROAD finish-stage outputs were recovered from the original project environment. Original GDSII files and timing reports matched existing Git blob checksums; original `6_report.json` files were recovered and committed byte-for-byte.

| Artifact | 8×16 | 32×32 | Purpose |
|---|---|---|---|
| OpenROAD finish JSON | [8×16](fifo_8x16/6_report.json) | [32×32](fifo_32x32/6_report.json) | Raw area, cell-count, utilization, slack, and related metrics |
| Final STA report | [8×16](fifo_8x16/final_timing.rpt) | [32×32](fifo_32x32/final_timing.rpt) | Detailed worst timing paths and violation counts |
| Final GDSII | [8×16](../layout/fifo_8x16/fifo_8x16.gds) | [32×32](../layout/fifo_32x32/fifo_32x32.gds) | Physical-layout output (open with KLayout) |
| Generic netlist | [8×16](fifo_8x16_generic.v) | [32×32](fifo_32x32_generic.v) | Yosys logic-synthesis evidence |

Additional documentation: [comparison CSV](comparison_summary.csv), [engineering notes](../docs/engineering_notes.md), and [reproduction guide](../docs/reproducibility.md).

To validate key original JSON values: `python3 scripts/summarize_finish_metrics.py` from the repository root.

**Data notes:** OpenROAD finish reports contain duplicate generic JSON keys and estimated single-corner power-grid/power fields. For area and cell count, use the explicit `__stdcell` keys, not generic duplicated keys. These artifacts do **not** establish foundry-level DRC/LVS or EM/IR signoff. Final DEF/OpenDB outputs were also recovered from WSL but are omitted from GitHub to avoid duplicating large generated databases already represented by GDSII and metrics.
