# Lightweight 500 MHz gate-level MaxCut test

This directory provides a shorter end-to-end replacement for the full
448-node UART regression. It uses the same 20x20/3200-pbit 500 MHz netlist and
the same external PLL/core UART paths, but configures one Chimera K4,4 cell.

## Coverage

- Configure the PLL for 500 MHz (`0x0228`).
- Write and read back the 200-sweep, majority-five run configuration.
- Write and read back the active annealing stage.
- Configure eight nodes one at a time through the external UART.
- Configure four LFSR seeds one at a time and read each seed back.
- Configure and read back all 16 internal K4,4 MaxCut edges.
- Read page zero before the run and confirm the programmed initial state.
- Start the hardware and wait for `RUN_DONE` after 200 sweeps.
- Read all ten snapshot pages (3200 physical spin bits) after the run.
- Require the deterministic K4,4 solution: bits `[3:0]=1`, bits `[7:4]=0`,
  score 16/16, no unknown snapshot bits and no hardware error flags.

The four left-shore nodes are clamped high. The four right-shore nodes start
high and are free; all 16 cross-shore edges use the tested MaxCut encoding.
This gives an exact expected result while still exercising the annealing
pipeline rather than only checking register storage.

## Run

Upload this directory beside the existing `gate_sim_500MHz` directory, then:

```bash
cd /public3/home/t6s011227/pbit_chimera_pipeline_20260920/gate_sim_500MHz_maxcut_lite
bash submit_gate_pipeline_500_maxcut_lite.sh sdf
```

For a zero-delay diagnostic run:

```bash
bash submit_gate_pipeline_500_maxcut_lite.sh zero
```

The result directory is:

```text
sim_runs/gate_pipeline_500_maxcut_lite_<mode>_<jobid>/
```

The main outputs are `MAXCUT_LITE_GATE_PASS.txt`,
`gate_maxcut_lite_result.txt`, `sim_gate_pipeline_maxcut_lite_<mode>.log`, and
`sdf_annotate_maxcut_lite.log` in SDF mode.
