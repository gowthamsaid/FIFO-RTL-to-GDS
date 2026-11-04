# Routed read-path experiment — stage-by-stage operating guide

This research work lives on `research/readpath-pilot-nov2026`, **not** the main
recruiter portfolio branch.

## Study design

| Size | Baseline | Decoder | Purpose |
|---|---|---|---|
| 8×16 | Run 1 | Run 2 | First matched pilot |
| 32×32 | Run 3 | Run 4 | Test whether trends extend to larger design |

**Independent variable:** read-selection architecture (indexed read vs
shared decoded read). **Controls:** architecture-independent FIFO semantics,
RTL parameter values, Nangate45 platform, ORFS revision and tool binaries,
same SDC, placement density, utilization target and stage ordering.

The existing October 2026 routed FIFO results are historical evidence,
**not** the matched baseline for the new decoder design.

## One-time WSL preparation

Open a WSL/Linux shell. Obtain the current branch:

```bash
git clone https://github.com/gowthamsaid/FIFO-RTL-to-GDS.git
cd FIFO-RTL-to-GDS
git fetch origin
git switch --track origin/research/readpath-pilot-nov2026
```

If already cloned, use `git fetch origin` and
`git switch research/readpath-pilot-nov2026` (or create the tracking branch
as above if absent). Do not overwrite unsaved local changes.

Set the ORFS checkout path to your **existing, working** installation.
`OPENROAD_FLOW_ROOT` must be the parent directory that contains `flow/`.
Example (change the path for your machine):

```bash
export OPENROAD_FLOW_ROOT="$HOME/OpenROAD-flow-scripts"
test -f "$OPENROAD_FLOW_ROOT/flow/Makefile"
```

Verify that the environment actually supports `make` synthesis in the ORFS
flow directory; if binaries aren't installed, follow the instructions for
the *specific ORFS version in your checkout*. Record your ORFS Git revision.

If old working directories use an earlier ORFS revision, **do not compare
results from different revisions**. The mapped-synthesis pilot's pinned
Nangate45 Liberty file alone does not pin the complete backend flow.

## Run 1: original 8×16

From the **FIFO-RTL-to-GDS repository root**, execute one stage at a time:

```bash
bash research/readpath/scripts/run_orfs_stage.sh 8x16 baseline preflight
bash research/readpath/scripts/run_orfs_stage.sh 8x16 baseline synth
bash research/readpath/scripts/run_orfs_stage.sh 8x16 baseline floorplan
bash research/readpath/scripts/run_orfs_stage.sh 8x16 baseline place
bash research/readpath/scripts/run_orfs_stage.sh 8x16 baseline cts
bash research/readpath/scripts/run_orfs_stage.sh 8x16 baseline grt
bash research/readpath/scripts/run_orfs_stage.sh 8x16 baseline route
bash research/readpath/scripts/run_orfs_stage.sh 8x16 baseline finish
```

**Stop on any error.** Do not skip a failed stage or change settings mid-run.

## Run 2: shared decoder 8×16

```bash
bash research/readpath/scripts/run_orfs_stage.sh 8x16 decoder preflight
bash research/readpath/scripts/run_orfs_stage.sh 8x16 decoder synth
bash research/readpath/scripts/run_orfs_stage.sh 8x16 decoder floorplan
bash research/readpath/scripts/run_orfs_stage.sh 8x16 decoder place
bash research/readpath/scripts/run_orfs_stage.sh 8x16 decoder cts
bash research/readpath/scripts/run_orfs_stage.sh 8x16 decoder grt
bash research/readpath/scripts/run_orfs_stage.sh 8x16 decoder route
bash research/readpath/scripts/run_orfs_stage.sh 8x16 decoder finish
```

The runs use isolated `DESIGN_NICKNAME`s and a shared
`FLOW_VARIANT=readpath-v1`, so baseline and decoder ORFS results are not
overwritten by each other.

## Runs 3 and 4: 32×32, only after reviewing 8×16

Use the exact same stage sequence, substituting
`32x32 baseline` and `32x32 decoder`.

## Where stage evidence is stored

Each experiment has its own local archive:

```text
research/readpath/runs/
  8x16/
    baseline/
      manifest.txt
      synth_console.log
      place_console.log
      ...
      stages/
        synth/reports/ + logs/
        floorplan/reports/ + logs/
        place/reports/ + logs/
        cts/reports/ + logs/
        grt/reports/ + logs/
        route/reports/ + logs/
        finish/reports/ + logs/
    decoder/
      ...
  32x32/
    baseline/
    decoder/
```

The original checkpoint files, including ODB and final GDS, remain in
`$OPENROAD_FLOW_ROOT/flow/results/nangate45/fifo_readpath_<size>_<architecture>/readpath-v1/`.
These may be large. Run archives are kept out of Git using `.gitignore`;
after verifying the comparison, selectively copy small final reports and
summaries to `research/readpath/evidence/` for a future reviewed commit.

## Stage-by-stage investigation

| Stage | Most relevant questions | Important caveat |
|---|---|---|
| Synthesis | Mapping, cells, hierarchy, area, buffering | No physical wires/CTS |
| Floorplan | Die/core area, same utilization target, initial timing | The core sizes may differ due to different cell areas |
| Placement | Setup critical path, pointer fanout and estimated RC | Wire parasitics are estimated |
| CTS | Clock buffers, propagated clock delays, setup **and** hold | Clock skew may change critical-path slack |
| Global route | Estimated routed parasitics, congestion, setup path | Route not detailed yet |
| Detailed route | Wire parasitics, read path, detours, DRC | Extraction/detail depends on flow setup |
| Finish | Final STA, cell area, buffers, violations, final GDS | Still not independent silicon signoff |

Compare **same stage vs same stage** between baseline and decoder. Prefer
the detailed report of `read_ptr[*]` → `data_out[*]` paths in addition
to the *overall worst* setup path: a successful optimization may move
the critical path elsewhere. Also distinguish arrival time, data-path delay,
required time, and setup slack. Reconfirm both designs still meet hold.

## Research rigor requirements

- Same 2.0 ns core clock; same simplified I/O delays and same corner.
- Record exact ORFS, Yosys, OpenROAD versions and raw implementation settings.
- Run both designs at their natural floorplan size first, then use a matched
  die/core size as a follow-up to separate architecture effects from density.
- Never compare a new decoder run directly with the archived original routed
  timing as proof of improvement.
- Recheck any interesting gain across repeated, controlled implementations.
- Null result = legitimate outcome; never claim improved timing before routed STA.
- Do not change the degree paper's completed 8×16/32×32 evidence.

## Completion checklist

- [ ] 8×16 baseline preflight
- [ ] 8×16 baseline all stages through finish
- [ ] 8×16 decoder preflight
- [ ] 8×16 decoder all stages through finish
- [ ] Review area, critical paths and routing evidence
- [ ] 32×32 paired implementations
- [ ] Controlled repeat runs / sensitivity analysis if effect is promising
- [ ] Written interpretation with a clear rejection/acceptance criterion
