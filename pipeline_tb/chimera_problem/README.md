# Latest-pipeline Chimera problem regression

The suite contains all seven cases used for the preceding Chimera RTL:

| Case | Problem | Logical size | Target |
|---|---:|---:|---:|
| `random_cut_n0096_s401` | weighted MaxCut | 96 nodes, 192 edges | 354 |
| `dense_cut_n0024_s101` | dense weighted MaxCut | 24 nodes, 276 edges | 834 |
| `random3_cut_n0096_s901` | weighted MaxCut | 96 nodes, 276 edges | 500 |
| `native_cut_n0448_s201` | native Chimera weighted MaxCut | 448 nodes, 1406 edges | 5847 |
| `random_sat3_n0024_s401` | random 3-SAT | 24 variables, 96 clauses | 96 |
| `uniform_sat3_n0060_s501` | uniform 3-SAT | 60 variables, 240 clauses | 240 |
| `random_sat4_n0012_s401` | random 4-SAT | 12 variables, 96 clauses | 96 |

Together they exercise sparse, dense and native embeddings, K4,4 intra-cell
edges, horizontal/vertical inter-cell edges, chains, bias terms, two-color
updates, 32-level annealing, majority sampling and complete node/seed/edge
configuration readback. Unused physical nodes and edges are explicitly disabled.

Defaults: 3 deterministic runs, 500 sweeps/run, N=5 proposals per phase,
linear I0 0.1 to 4.0, seeds 2461 and 314592. The old non-pipelined run with the
same run-0 seed reached best score 4211 within 200 sweeps; this is a comparison
reference, not a mandatory threshold because the new pipeline changes which
LFSR state supplies each proposal.

The test uses the register bus test harness for 57,811 checked configuration
transactions per run. UART serialization is deliberately omitted here because
the separate rw/run3x3 tests already verify the production UART path. Register
legality, request routing, bank storage, p-bit datapaths and run scheduling are
the production RTL.

The checker requires the latest pipeline and bias `<`. Every phase start must
be `N+5` clocks apart, every completed sweep exactly `2*(N+5)` clocks, and the
default 500-sweep run exactly 10,000 clocks from accepted RUN to RUN_DONE.
All banks must complete together. Every sweep is independently rescored from
the saved physical state, and final/best UART-register snapshots are checked.
Optimization reaching 5847 is reported separately from functional PASS.

`check_results.py` is deliberately an independent state decoder and Ising
score checker, not a cycle-for-cycle software oracle. The older exact Python
model consumes a different LFSR proposal index than this pipelined RTL, so it
must be updated before a bit-exact trajectory comparison would be meaningful.

Submit one case from the latest project root:

```bash
cd /public3/home/t6s011227/pbit_chimera_pipeline_20260920
sbatch --export=ALL,CASE_NAME=native_cut_n0448_s201 \
  pipeline_tb/run_chimera_problem_sbatch.sh
```

For a direct one-run/200-sweep comparison with the earlier result:

```bash
sbatch --export=ALL,RUNS=1,SWEEPS=200 pipeline_tb/run_chimera_problem_sbatch.sh
```

Optional overrides: `RUNS`, `SWEEPS`, `MAJORITY`, `SEED_MASTER`, `INIT_SEED`,
`SCHEDULE`, `I0_START`, `I0_END`, and `MIN_SCORE`. Do not set `MIN_SCORE` until
the new deterministic baseline is known; a missed optimum is not a functional
RTL failure.

Results are under `sim_pipeline/problems/<case>_<job-id>/rtl/`:
`sim.log`, `chimera_sweeps.csv`, `chimera_states.txt`, `python_score_check.log`,
the generated register program/manifest, source hashes, compile log and binary.
