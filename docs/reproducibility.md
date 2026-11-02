# Reproduction and inspection guide

## 1. RTL simulation (repeatable with Icarus Verilog)

From the repository root on Linux/macOS (or a Bash environment with Icarus installed):

```bash
bash scripts/run_rtl_tests.sh
```

This runs five test cases: the basic 8×16 smoke test, plus the boundary and corner testbenches for both 8×16 and 32×32. The tests fail non-zero if a `$fatal` assertion is reached.

The repository also includes a lightweight CI workflow at [`.github/workflows/rtl-regression.yml`](../.github/workflows/rtl-regression.yml). A workflow execution is evidence for **RTL simulation only**, not for a completed OpenROAD backend run.

## 2. Generic Yosys synthesis

With Yosys available and while in the repository root:

```bash
yosys -s scripts/fifo_8x16.ys
yosys -s scripts/fifo_32x32.ys
```

The scripts apply `chparam` to select the intended parameters, run generic synthesis, perform `check -assert`, and write generated netlists under `reports/`. The generated `*_script.v` outputs are ignored by Git.

Historical generic netlists already committed under `reports/fifo_8x16_generic.v` and `reports/fifo_32x32_generic.v` are kept unmodified as project evidence.

## 3. OpenROAD implementation

The `openroad/fifo_8x16` and `openroad/fifo_32x32` directories contain **OpenROAD-flow-scripts style** `config.mk` and `constraint.sdc` files. They are not standalone Tcl flow scripts.

To reproduce a physical implementation:

1. Install and verify a compatible [OpenROAD-flow-scripts](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts) environment with Nangate45 available.
2. Register the designs in that ORFS checkout and point `VERILOG_FILES` at this repository's `rtl/fifo_sync.v` rather than the original author's `$(HOME)/projects/fifo-rtl-to-gds` path.
3. Ensure `SDC_FILE` resolves to the respective `constraint.sdc`. The 32×32 config has an explicit width/depth parameter override; the 8×16 design uses RTL defaults.
4. Run synthesis and the physical-design stages using the chosen ORFS version's documented invocation method.
5. Compare the resulting timing and layout metrics with the archived reports, allowing for version/platform/seed differences.

**Why no single `make` command here?** The exact original ORFS revision, dependency versions and environment paths were not preserved in the repository. Giving a guessed one-liner would be misleading. The checked-in OpenROAD configs are project-specific settings, not a validated portable build kit.

## 4. Review final results

- [8×16 final STA report](../reports/fifo_8x16/final_timing.rpt)
- [32×32 final STA report](../reports/fifo_32x32/final_timing.rpt)
- [Generic synthesis summary](../reports/generic_synthesis_summary.md)
- [8×16 final GDSII](../layout/fifo_8x16/fifo_8x16.gds)
- [32×32 final GDSII](../layout/fifo_32x32/fifo_32x32.gds)

GDSII files are binary layout databases. Download and view them with a GDSII viewer such as KLayout; the GitHub web UI cannot render their physical layers. See [engineering notes](engineering_notes.md) for measurement provenance and the signoff boundary.
