# Pipeline RTL regression

Tests use the latest contribution/MAC pipeline and strict bias comparison.
The source package is not edited. Each job copies RTL and changes only ROWS/COLS
to 3: 9 Chimera units, 72 p-bits, inside a partial 5x5 bank. Clock remains 400MHz,
UART remains 1Mbps. This is RTL simulation of pbit_top, not PLL/pad/gate simulation.

From the uploaded project root:

```bash
cd /public3/home/t6s011227/pbit_chimera_pipeline_20260920
sbatch --export=ALL,TEST=rw pipeline_tb/run_sbatch.sh
sbatch --export=ALL,TEST=run3x3 pipeline_tb/run_sbatch.sh
```

Default resources: 4 CPUs, 8GiB per job. No compilation on login nodes.
The job copies sources at start; do not edit files while queued.
No existing DC source, scripts or job folders are changed.

## Coverage

- rw: original 52-register UART regression, adjusted for 3x3 address widths and
  snapshot padding. Masks, address aliasing, RO/WO, W1C/RC, configuration readback,
  seeds, six edge types, invalid addresses/boundaries and one run. The inherited
  runtime-write rejection test forces run_busy only for that error-injection
  section, not for functional operation.
- run3x3: UART writes and reads all 72 node configurations and 36 seeds. One
  clamped run, then zero-coupling/zero-bias runs with actual N=1,2,5,32 samples.
  Nonclamped results are predicted by an independent LFSR/16-bit extraction and
  majority reference model, never copied from DUT values. Check all 72 spins at
  every phase commit, prohibit early spin changes, check UART snapshots/padding
  and all final RNG states. Opposite bias signs at zero magnitude are included.
- Each phase accepts at E0: contributions E1..EN, MAC E2..E(N+1), samples
  E3..E(N+2), commit/done after E(N+3). RNG advances N+3 times. First proposal
  uses R2. Run latency from run-start acceptance is 2*sweeps*(N+5) clocks,
  including registered launch and completion-consumption edges.
- Completion spin stability and run_done clear are exercised. This basic test
  does not validate nonzero coupling optimization quality or all LUT entries,
  cross-bank routing, PLL, pads, or post-route timing.

## Results

`sim_pipeline/<rw|run3x3>_<job-id>/rtl/` contains compile.log, sim.log and simv.
The run test also writes run_summary.csv (case, N, sweeps, clocks, phases, spins).
`manifest.json` one directory above records original/simulation RTL hashes.
Require `PASS rw_basic:` or `[TB_RUN3X3] PASS`, not just successful compilation.
Global simulation watchdog is one simulated second.

## Directed regressions

Seven additional tests preserve and extend the directed coverage from the previous
edge-`<=`/bias-`<` Chimera version and run it against the pipeline RTL:

- `uart_end_to_end`: serialized UART configuration, readback, RUN and snapshot.
- `uart_full_snapshot`: after a real RUN, serializes all ten snapshot pages and
  all 100 data words over the production 1-Mbps UART, checking all 3200 bits.
- `config_boundaries`: encoded counts, all majority boundaries, anneal stages,
  registered LUT thresholds and exact `2*sweeps*(N+5)` run latency.
- `error_paths`: busy conflicts, sticky errors, reset recovery, malformed UART,
  two runs without a global reset and asynchronous reset during a run.
- `probability_modes`: exhaustive 7-bit edge/bias comparisons, valid gating and
  a black-box check through both registered MAC stages.
- `mac_signed_lanes`: all six physical MAC lanes, four sign/spin combinations,
  valid gating, concurrent balanced-tree sums and stage-1 input isolation.
- `topology_routing`: all K4,4 edge types plus right/down routing across the
  `5x5` BANK boundary, neighbor-spin directionality and outer boundary rejection.

Submit one test with:

```bash
sbatch --export=ALL,TEST=probability_modes pipeline_tb/run_extra_sbatch.sh
```

## Optimization problems

`chimera_problem/` runs all seven previously established Chimera embeddings:
four weighted MaxCut cases and three SAT cases. Every case checks full
configuration/readback, exact pipeline cycles and independent per-sweep Python
scoring. Submit one case with:

```bash
sbatch --export=ALL,CASE_NAME=random_sat3_n0024_s401 \
  pipeline_tb/run_chimera_problem_sbatch.sh
```

Submit the complete 16-job regression (two basic tests, seven directed tests and
seven optimization problems) with:

```bash
bash pipeline_tb/submit_full_regression.sh
```

Override problem effort with `RUNS=... SWEEPS=... MAJORITY=...`. Outputs are
isolated under `sim_pipeline/{rw,run3x3,extra,problems}` and include source
hashes, compile logs and simulation logs. See `chimera_problem/README.md` for
score outputs and optional controls.

Preview all 16 `sbatch` commands without submitting with:

```bash
DRY_RUN=1 bash pipeline_tb/submit_full_regression.sh
```

Python-model changes from the preceding RTL are specified in
`LATEST_PIPELINE_VS_EDGE_LE_BIAS_LT.md`.

## Python cycle oracle

`run_pipeline_oracle_sbatch.sh` checks one representative Chimera problem against
`chimera_pbit_hardware_sim_pipeline_20260920.py` sweep by sweep. The fixed case is
`dense_cut_n0024_s101`, with one deterministic run and 32 sweeps:

```bash
cd /public3/home/t6s011227/pbit_chimera_pipeline_20260920
sbatch pipeline_tb/run_pipeline_oracle_sbatch.sh
```

The register transactions and `oracle_*.mem` files are precomputed locally and
stored under `chimera_problem/oracle_fixtures`. The T6 job does not import Python
or NumPy. During VCS simulation,
`+CHECK_ORACLE` makes the SystemVerilog testbench compare every completed sweep:
cycle count, score, best score, broken chains, chain ties, I0 level and the full
3200-bit spin vector. A passing run prints both
`[CHIMERA_PIPELINE_ORACLE] PASS` and `[TB_CHIMERA_PIPELINE_PROBLEM] PASS`.
The script deliberately rejects parameter overrides so a stale oracle cannot be
compared against a different case, schedule, seed, run count, or majority value.
