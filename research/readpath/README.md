# Read-path research pilot (separate from the M.S. technical paper)

## Motivation: direct evidence from October 11, 2026 routed results

- At 8-bit x 16-entry: worst **setup** path `read_ptr[2]` to `data_out[3]`,
  arrival 0.78 ns, setup slack +1.28643 ns.
- At 32-bit x 32-entry: worst **setup** path `read_ptr[2]` to `data_out[6]`,
  arrival 0.92 ns, setup slack +1.20585 ns.
- Both contain buffered high-fanout read-pointer logic and read-selection cells.
- **Neither baseline violates the 2 ns constraint.** We are investigating the
  cost and performance of the read path, not repairing an existing violation.

Source: `reports/fifo_8x16/final_timing.rpt` and
`reports/fifo_32x32/final_timing.rpt`.

## Proposed falsifiable question

For a flip-flop-based synchronous FIFO using the same interface, write
semantics, technology library, and constraints, **when does shared read-address
decoding (one-hot/AND-OR) outperform an indexed memory read (synthesis inferred
mux) in post-route critical-path delay, and what area/routing/fanout cost
does it impose?**

### H1 (not yet established)
The shared decoder may reduce the fanout-driven read-pointer delay for some
(width, depth) combinations by sharing comparisons across data bits.

### Competing hypothesis H0
Technology mapping may collapse the two RTL variants into comparable or
identical gate structures, or added one-hot fanout/routing may cancel timing
benefits. The alternative could be slower and larger.

## First-stage gate: avoid wasting weeks

1. Verify cycle-accurate equivalence against an independent queue model.
   This is a deterministic **simulation check, not formal proof**.
2. Generic synthesize both with exactly the same Yosys version, options,
   configuration, and stimulus-independent assumptions.
3. Inspect mapped/structural logic: mux, comparators, AND/OR elements,
   fanout and logic depth. Generic cell count is **not** standard-cell area.
4. **Only if structurally distinct**, advance to matched Nangate45 technology
   mapping and matched OpenROAD placement/routing. The original ORFS
   environment must be reproducibly reconstructed or documented.
5. Confirm read selection is the critical path in each new run. Compare
   the *actual routed path delay*, per-instance STA path detail, buffering,
   area, congestion, and routing metrics—not simply an Fmax headline.
6. Perform matched repeat runs if tool placement differs, report all results,
   including failures, without cherry-picking best-case layouts.

## Primary controlled configurations

- 8x16 and 32x32: historical anchors.
- Equal-storage family: 8x64, 16x32, 32x16, 64x8 (512 bits each).
- Compare **architecture A vs B within each identical size**.
  Different widths have different I/O widths, so equal storage capacity alone
  is not a fair architecture comparison *between* configurations.

## Interpretation and stop criteria

- If Yosys makes essentially the same netlist, **stop and change the question**:
  architecture names alone do not establish different hardware.
- If distinctive netlists exist but post-route measurements are inconsistent
  or improvements fall within run-to-run variability, report a null result and
  do not claim superiority.
- If one architecture improves read-path delay, quantify the tradeoff in
  cell area, wiring, buffering, power assumptions, and setup/hold margins.
- Literature and prior-art review are required **before publication claims**.
  One-hot decoders, mux structures, and FIFO optimizations are established
  concepts. This pilot does not claim to invent any of them.
- This pilot is separate from the already-complete 8x16 vs 32x32 technical
  paper, so an inconclusive hypothesis must not delay degree completion.

## Running the pilot

GitHub Actions `Research pilot — FIFO read-path architecture` performs
six-config differential RTL simulation and Yosys generic synthesis.
To run locally, install `iverilog`, `vvp`, and `yosys`, then use the
commands in `.github/workflows/readpath-pilot.yml`.

Artifacts from the workflow are generic synthesis logs; there is **no claim
that physical design, routed timing, formal equivalence, or publication-level
novelty has been established by these jobs**.

## Stage 2: Nangate45 mapped-synthesis pilot

A separate GitHub Actions workflow, `Research pilot — Nangate45 mapped synthesis`,
runs `research/readpath/scripts/run_mapped_synthesis.sh` on 8x16, 32x32,
8x64, and 32x16. It downloads a Nangate45 **typical-corner** Liberty file
from pinned upstream ORFS commit
`d056a2b304182bf76ff10653531165b1dd9848d4`.
The workflow records the library SHA-256 hash and Yosys version, then performs
identical synthesis, standard-cell flip-flop mapping and ABC logic mapping
for both architectures. Netlists, complete logs, and `stat -liberty`
area statistics are retained as CI artifacts.

**This cannot establish timing benefit.** It evaluates mapped gate types
and estimated library cell area before any floorplan, clock tree, wire
parasitics, or timing constraints. We will proceed to a controlled OpenROAD
run only after the mapped outputs are inspected and the research hypothesis
remains worth testing.

## Initial mapped-synthesis result — 2026-11-04

[GitHub Actions mapped-synthesis run](https://github.com/gowthamsaid/FIFO-RTL-to-GDS/actions/runs/41872480609)
completed successfully on all four configurations. Using the same
pinned Nangate45 typical-corner Liberty and Yosys mapping commands:

| FIFO | Baseline mapped cells | Decoder mapped cells | Baseline library area (µm²) | Decoder library area (µm²) | Area change |
|---|---:|---:|---:|---:|---:|
| 8×16 | 495 | 503 | 1197.000 | 1164.282 | −2.7% |
| 32×16 | 1961 | 1537 | 4479.440 | 4100.124 | −8.5% |
| 8×64 | 2030 | 1717 | 4514.020 | 4144.546 | −8.2% |
| 32×32 | 3797 | 2980 | 8702.190 | 7907.648 | −9.1% |

These `stat -liberty` estimates are **mapped-cell areas only**, not
placed/routed design area, and no path-delay comparison has yet been run.
They are not directly comparable with previously archived post-route
OpenROAD results, which reflect the separate original implementation
flow. Both variants must undergo consistent backend implementation
and STA before timing conclusions or an area/timing tradeoff can be made.

**Interpretation:** Even though decoder generic synthesis contained
more primitive logic cells, technology mapping reduced library cell area
at all four tested sizes. This supports progressing to a controlled
physical-design pilot; it does **not** establish H1, H2, or post-route
timing benefit. Keep power, delay, and congestion claims provisional.
