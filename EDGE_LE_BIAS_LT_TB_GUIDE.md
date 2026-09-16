# Edge <= and bias < validation

This variant uses two complementary checks.

## 1. Exhaustive probability semantics

`tb_probability_modes.sv` checks every 7-bit probability code and every 7-bit random value:

- a valid edge accepts exactly `code + 1` of 128 random values;
- an invalid edge never accepts;
- bias accepts exactly `code` of 128 random values;
- bias code 0 never contributes;
- directed checks also verify the registered MAC output for boundary values.

Run on the remote server:

```bash
cd /public3/home/t6s011227/pbit_kings_chimera_edge_le_bias_lt
sbatch run_chimera_extra_tb_sbatch.sh probability_modes
```

The result is stored under:

`sim_chimera_extra/probability_modes/<job-id>/rtl/`

The required final marker is:

`[TB_PROBABILITY_MODES] PASS`

## 2. Representative problem-level regression

The selected case is `random_sat3_n0024_s401`, which contains 118 nonzero physical biases and 793 physical couplings. It therefore exercises both comparison modes through the complete configuration, run, snapshot, decoding and scoring path.

```bash
cd /public3/home/t6s011227/pbit_kings_chimera_edge_le_bias_lt
sbatch --job-name=ch_elbl_sat3 run_chimera_problem_sbatch.sh \
    random_sat3_n0024_s401 --runs 1 --sweeps 128 --majority 5
```

The result is stored under:

`sim_chimera/random_sat3_n0024_s401/<job-id>/rtl/`

The required functional marker is:

`[TB_CHIMERA_PROBLEM] PASS`

Reaching the SAT certificate target is an optimization-quality result, not a requirement for functional PASS.

## Submit both

```bash
cd /public3/home/t6s011227/pbit_kings_chimera_edge_le_bias_lt
sed -i 's/\r$//' run_chimera_extra_tb_sbatch.sh run_chimera_problem_sbatch.sh \
    submit_edge_le_bias_lt_validation.sh
bash submit_edge_le_bias_lt_validation.sh
```

Each Slurm job copies the RTL into its own job directory before compiling, so these tests do not modify or interfere with running DC jobs.

## Previous-problem comparison suite

`submit_edge_le_bias_lt_problem_regression.sh` repeats three previously run
cases with the original fixed settings: 3 runs, 500 sweeps, majority 5,
master seed 2461 and initial-state seed 314592.

| Case | Purpose | Nonzero bias | Couplings |
|---|---|---:|---:|
| `random_cut_n0096_s401` | Small weighted MaxCut control | 0 | 414 |
| `native_cut_n0448_s201` | Larger native Chimera MaxCut | 0 | 1470 |
| `random_sat3_n0024_s401` | Bias-sensitive SAT mapping | 118 | 793 |

Submit the comparison suite:

```bash
bash submit_edge_le_bias_lt_problem_regression.sh
```

After all three jobs complete, compare their job output files with the saved
baseline results:

```bash
python3 rtl/tb/chimera_problem_gen/compare_edge_le_bias_lt_results.py \
    chimera-<cut-job>.out chimera-<native-job>.out chimera-<sat-job>.out
```

The comparison checks `runs=3`, `sweeps=500`, `majority=5`, the target score,
all run records, the SystemVerilog PASS marker and the independent Python score
PASS marker. It prints old/new `final` and `best` scores with signed deltas.
Those score deltas are informational: changing zero-bias acceptance from
1/128 to zero intentionally changes the random trajectory.
