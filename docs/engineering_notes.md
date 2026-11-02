# Engineering notes

## Design and parameter conventions

**Naming convention: width × depth**. Thus `8x16` is an 8-bit word with 16 entries (128 storage bits); `32x32` is a 32-bit word with 32 entries (1,024 bits). This matches the parameter defaults in [`fifo_sync.v`](../rtl/fifo_sync.v) and the explicit OpenROAD top-parameter override in [the 32×32 config](../openroad/fifo_32x32/config.mk).

The top-level interface consists of `clk`, `rst`, `wr_en`, `rd_en`, `data_in`, `data_out`, `full`, and `empty`. A single active-high synchronous reset clears the pointers, count and output data register; it does not clear every storage-array word. Output data changes on accepted reads, not combinationally on the read-address port.

Implementation details:

- `read_accept = rd_en && !empty`.
- `write_accept = wr_en && (!full || read_accept)`.
- Occupancy increases for write-only, decreases for read-only, and holds for concurrent accepted transfers.
- A read from an empty FIFO is not accepted even if `wr_en` is asserted concurrently (no first-word fall-through/bypass).
- At full occupancy, a concurrent accepted read permits a write in the same cycle, maintaining full occupancy.
- Pointer increment uses natural binary overflow with `$clog2(DEPTH)`; **supported intended depths are powers of two**. Non-power-of-two depths need explicit wrap logic before being claimed as supported.
- Storage is a RTL `reg` array synthesized into flip-flops (the project does not instantiate an SRAM macro).

## Verification and interface semantics

| Testbench | Coverage | Configuration |
|---|---|---|
| [`fifo_sync_tb.v`](../tb/fifo_sync_tb.v) | Basic reset, two writes, read ordering | 8-bit × 16-entry |
| [`fifo_boundary_tb.v`](../tb/fifo_boundary_tb.v) | Fill/drain, full/empty, overflow/underflow prevention | 8×16 and 32×32 |
| [`fifo_corner_tb.v`](../tb/fifo_corner_tb.v) | Reference-model checking; concurrent operation at full/empty, pointer wraps and partially full traffic | 8×16 and 32×32 |

Execute the regression with `bash scripts/run_rtl_tests.sh` from the repository root. The script compiles testbenches with Icarus Verilog using isolated temporary outputs. The testbench sources use `$fatal` to signal mismatches. The GitHub Actions workflow uses the same script.

These are directed/self-checking RTL tests. They are not formal verification, gate-level timing simulation, or complete coverage closure.

## Physical-design methodology

```text
RTL -> directed simulation -> generic synthesis (Yosys)
    -> Nangate45 standard-cell implementation (OpenROAD)
    -> floorplan -> placement -> CTS -> global + detailed routing
    -> GDSII -> post-route static-timing reports
```

The archived project used an OpenROAD-flow-scripts style configuration. Both configurations use a **2.0 ns** clock period, a **0.2 ns input delay**, and a **0.2 ns output delay**. See the actual [8×16 SDC](../openroad/fifo_8x16/constraint.sdc) and [32×32 SDC](../openroad/fifo_32x32/constraint.sdc) for the exact constraints. The project configurations request **40% target core utilization** and **0.60 placement density**; these *settings* are not the same as the final realized core-utilization percentages.

The `config.mk` files retain an original machine-specific RTL path under `$(HOME)/projects/fifo-rtl-to-gds`. A fresh OpenROAD-flow-scripts checkout needs the local source path and design home configured before reproducing the physical results. Do not assume `make` will work without integration; follow [reproduction guide](reproducibility.md).

## Measurement provenance

The **original** OpenROAD finish-stage [8×16 `6_report.json`](../reports/fifo_8x16/6_report.json) and [32×32 `6_report.json`](../reports/fifo_32x32/6_report.json) were recovered from the October 11, 2026 WSL run directories and compared with the uploaded archive. Both files have been restored **byte-for-byte**. The GDSII and STA report Git blob checksums also matched the original repository versions, so previously committed physical results have not been modified.

| Measurement | 8×16 | 32×32 | Source |
|---|---:|---:|---|
| Storage bits | 128 | 1,024 | RTL parameters |
| Generic Yosys cells | 355 | 2,206 | [synthesis summary](../reports/generic_synthesis_summary.md) |
| Generic flip-flops | 149 | 1,072 | [synthesis summary](../reports/generic_synthesis_summary.md) |
| **Mapped standard cells** | **658** | **3,988** | JSON: `finish__design__instance__count__stdcell` |
| Standard-cell area (µm²) | 1,355.8 | 9,216.1 | JSON: `finish__design__instance__area__stdcell` |
| Final std-cell utilization | 42.0545% | 40.6789% | JSON: `finish__design__instance__utilization__stdcell` |
| Total placed instances (incl. fillers) | 1,452 | 9,500 | JSON: `finish__design__instance__count` |
| Filler-cell instances | 794 | 5,512 | JSON: `finish__design__instance__count__class:fill_cell` |
| Clock-buffer instances | 20 | 239 | JSON: `finish__design__instance__count__class:clock_buffer` |
| Worst setup-path slack (ns) | +1.28643 | +1.20585 | JSON: `finish__timing__setup__ws` |
| Worst hold-path slack (ns) | +0.0920368 | +0.0909872 | JSON: `finish__timing__hold__ws` |
| Setup / hold violation count | 0 / 0 | 0 / 0 | JSON: `finish__timing__drv__*violation_count` |
| Setup / hold TNS (ns) | 0 / 0 | 0 / 0 | JSON: `finish__timing__*__tns` |
| STA-estimated Fmax (MHz) | 1,401.40 | 1,259.22 | JSON: `finish__timing__fmax` |
| Worst VDD drop (mV), default corner | 4.726 | 4.692 | JSON power-grid default-corner fields; **not signoff** |

**Why do cell counts differ?** The larger total instance count includes filler instances, while `__stdcell` reports the metric convention used for the cell-area comparison. Clock buffers are included in the class accounting; do not add all class counters as though disjoint.

**Original JSON caveat:** The untouched OpenROAD finish JSON contains repeated generic keys such as `finish__design__instance__area` with different values. This is a tool-output formatting issue: use the explicit unique `__stdcell`, `__core__area`, and `__die__area` metric keys instead of ambiguous generic keys.

**Timing convention:** The text STA reports print `wns max 0.00` when all paths meet setup timing, but also print a positive `worst slack max`. The table reports the latter. A 2.00 ns clock constraint was used; `period_min`/Fmax are **estimated by STA**, not validated silicon operating points.

The JSON also contains tool-reported power estimates and power-grid voltage-drop outputs. Switching activity assumptions and model accuracy were not independently documented; these are **preliminary single-corner tool outputs**, not proven measured power, EM/IR signoff, or full physical signoff.

Use `python3 scripts/summarize_finish_metrics.py` from the repository root to summarize key values and check zero recorded timing violations. See [the report index](../reports/README.md) for source navigation.

### Interpretation

Increasing storage from 128 to 1,024 bits (8×) increased mapped area by ~6.8× and cell count by ~6.1×. The estimated Fmax decreased from ~1.401 to ~1.259 GHz (~10.1%). Both depth and width changed, so a controlled one-variable-at-a-time experiment would be needed to attribute effects to either dimension alone.

## Scope and limitations

- Nangate45 open standard-cell platform; not a modern production-node tapeout.
- Setup and hold results apply to the recorded single analysis corner and simplified input/output timing constraints.
- No multi-mode/multi-corner signoff; no independent full DRC/LVS, antenna, or EM/IR signoff evidence is checked in.
- No SRAM macro insertion, independently validated power/activity analysis, manufacturing or silicon validation. The finish JSON contains preliminary tool power/voltage-drop estimates, not signoff.
- The repository contains the resulting GDSII files, but not a fully portable, pinned end-to-end OpenROAD build environment.
- Timing and area numbers describe these two specific physical runs; they are not universal FIFO scaling laws.
