# 500 MHz pipeline gate-level regression

This directory runs zero-delay functional simulation on the synthesized
20x20/3200-pbit pipeline netlist from DC job `37408821`.

## Tests

- `basic`: configures the PLL for 500 MHz (`0x0228`) and checks core UART
  register write/read plus a clean error register.
- `small`: configures and runs a deterministic two-node MaxCut problem. It
  verifies configuration readback, seed/edge programming, RUN status, the
  clamped node and the expected free-node flip.
- `large`: places two clamped markers in each of the ten 320-bit pages, runs
  the full 3200-pbit array, reads all 100 snapshot words twice through the
  external 1-Mbps UART, and checks page/word/bit mapping and post-RUN stability.

The three simulations share one VCS compilation when `all` is selected.

## Run

```bash
cd /public3/home/t6s011227/pbit_chimera_pipeline_20260920/gate_sim_500MHz
bash submit_gate_pipeline_500.sh --dry-run
bash submit_gate_pipeline_500.sh all
```

Run one case only with `basic`, `small`, or `large` in place of `all`.

Use the submit helper rather than submitting the runner by absolute path from
another directory. The helper passes the source directory explicitly because
Slurm executes a copied script under `/var/spool/slurmd`.

Results are created under:

```text
gate_sim_500MHz/sim_runs/gate_pipeline_500_<test>_<jobid>/
```

`SUITE_PASS.txt` is written only after every selected case passes. The default
netlist and model paths can be overridden with `DC_RUN`, `NETLIST`,
`PLL_MODEL`, `IO_MODEL`, and `STD_MODEL` environment variables.

## SDF delay simulation

After the zero-delay suite passes, run the same tests with the DC-generated
SDF maximum delays and standard-cell timing checks enabled:

```bash
bash submit_gate_pipeline_500_sdf.sh --dry-run
bash submit_gate_pipeline_500_sdf.sh all
```

SDF results are written below
`sim_runs/gate_pipeline_500_sdf_<test>_<jobid>/`. Each test preserves its own
`sdf_annotate_<test>.log`; `SDF_SUITE_PASS.txt` appears only when all selected
tests pass. Override the automatically discovered SDF with `SDF=/abs/file.sdf`
when needed.

The VCS build uses `+allmtm`, and each simulation selects `+maxdelays`. This
keeps all min/typ/max values during compilation and prevents VCS from silently
falling back to typical specify delays at runtime.

This is a pre-layout SDF regression. It includes synthesized cell/path delays,
but it is not a replacement for post-route SDF or PrimeTime/MMMC signoff.

## Full large MaxCut through UART

The long-form regression uses `native_cut_n0448_s201`: 448 logical nodes,
1406 weighted MaxCut edges embedded into 512 of the 3200 physical p-bits. It
still configures and snapshots the complete 3200-pbit array. It generates one
deterministic 200-sweep program and sends every node, 1600 LFSR seeds, every
physical edge and all schedule registers one transaction at a time through the
external 1-Mbps UART. Configuration readback is also performed transaction by
transaction. The final 3200-bit state is reconstructed through ten snapshot
pages and scored against the original logical graph.

Run the SS maximum-delay SDF mode (default):

```bash
bash submit_gate_pipeline_500_maxcut.sh --dry-run
bash submit_gate_pipeline_500_maxcut.sh sdf
```

For a faster functional baseline without delays:

```bash
bash submit_gate_pipeline_500_maxcut.sh zero
```

Results are under
`sim_runs/gate_pipeline_500_maxcut_<mode>_<jobid>/`. The key files are
`sim_gate_pipeline_maxcut_<mode>.log`, `gate_maxcut_result.txt`, the generated
problem manifest/program and `MAXCUT_GATE_PASS.txt`. Reaching the known optimum
5847 is reported but is not a functional PASS requirement for one stochastic
run.
