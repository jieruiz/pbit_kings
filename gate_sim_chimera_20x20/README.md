# Chimera gate-level smoke test

This directory tests the synthesized `pbit_io_wrapper` only through chip pins.
It does not depend on RTL hierarchy names and therefore remains valid after
Design Compiler ungrouping and net renaming.

The test covers the 25 MHz PLL configuration UART, PLL APPLY/status readback,
core reset release, and 1 Mbps core-UART read/write of `A_GLOBAL_CFG` plus an
`A_ERROR_STATUS == 0` check. By default it uses the vendor `PLL_TOP.v` model,
but performs only a power-on start in normal PLL mode. It does not switch to
bypass or reconfigure a running PLL, so it avoids the two known model defects.

Upload this directory to:

```text
/public3/home/t6s011227/gate_sim_chimera_20x20
```

The script defaults to the existing 20x20, 350 MHz SS125 DC result directory
and automatically locates its unique non-PG gate netlist and SDF. Therefore,
the default zero-delay run only needs:

```bash
cd /public3/home/t6s011227/gate_sim_chimera_20x20
sbatch --export=ALL,MODE=zero run_gate_sim_sbatch.sh
```

To use another DC result, export its directory before submission:

```bash
export DC_RUN=/absolute/path/to/another/DC/result/directory
export PLL_CFG_HEX=021c
sbatch --export=ALL,MODE=zero run_gate_sim_sbatch.sh
```

After it passes, run maximum-delay SDF simulation:

```bash
sbatch --export=ALL,MODE=sdf run_gate_sim_sbatch.sh
```

To isolate a failure from the vendor PLL model, rerun with the included ideal
digital model:

```bash
export PLL_MODEL="$PWD/pll_functional_model.sv"
sbatch --export=ALL,MODE=zero run_gate_sim_sbatch.sh
```

Each job writes to its own directory under `sim_runs/gate_zero_<jobid>` or
`sim_runs/gate_sdf_<jobid>`. Success is marked by `[TB_GATE_WRAPPER] PASS`.

The runner deliberately loads only `ICsprout55_9TSVT_basic.v` with the
non-PG gate netlist. Do not load `ICsprout55_9TSVT_basic_pg.v` at the same
time: both files define the same module names, and the PG definitions require
the additional `VDD`, `VSS`, `VNW`, and `VPW` ports.

For a different frequency netlist, set `PLL_CFG_HEX` to the exact PLL default
used when that netlist was synthesized. For the current 20x20 350 MHz variant,
the value is `021c` (`N=28`, `SELECT=0`, `OD=1`, `BP=0`).

## Concrete problem test

`tb_gate_chimera_problem.sv` goes beyond the register smoke test by solving a
two-node MaxCut problem entirely through package pins. Node 0 is clamped high,
node 4 starts high, and a maximum-probability antiferromagnetic edge connects
them. After one sweep with five-vote majority, node 4 must be low, changing the
edge score from zero to one.

Run the dedicated zero-delay job with:

```bash
cd /public3/home/t6s011227/gate_sim_chimera_20x20
sbatch run_gate_problem_zero_sbatch.sh
```

The job creates `sim_runs/gate_problem_zero_<jobid>` and succeeds only when
`sim_gate_problem_zero.log` contains `[TB_GATE_CHIMERA_PROBLEM] PASS`.

## PLL bypass comparison

`tb_gate_pll_bypass.sv` applies the sequence normal PLL, 25 MHz bypass, then
normal PLL again to the same synthesized wrapper. It measures the internal
core clock because that clock is not exported as a package pin; all control
and core-register checks still use the two physical UART interfaces.

Run the vendor model first, then the ideal model as a control experiment:

```bash
cd /public3/home/t6s011227/gate_sim_chimera_20x20
sbatch --export=ALL,PLL_MODEL_KIND=vendor run_gate_pll_bypass_zero_sbatch.sh
sbatch --export=ALL,PLL_MODEL_KIND=ideal  run_gate_pll_bypass_zero_sbatch.sh
```

Results are written below `sim_runs/gate_pll_bypass_vendor_<jobid>` and
`sim_runs/gate_pll_bypass_ideal_<jobid>`. A vendor-only failure reproduces a
vendor behavioral-model issue; failure with both models points instead to the
synthesized wrapper, PLL configuration controller, reset sequence, or test.
