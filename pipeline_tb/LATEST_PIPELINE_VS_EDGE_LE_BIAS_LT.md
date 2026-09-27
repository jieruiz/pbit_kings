# Latest pipeline RTL versus edge-<= / bias-< RTL

This note defines the changes that a cycle-accurate Python model must make when
moving from the preceding `pbit_kings_chimera_edge_le_bias_lt` RTL to the latest
`pbit_chimera_pipeline_20260920` RTL. It is based on a file-by-file RTL diff.

## Unchanged external model

- Chimera geometry, node numbering, six stored edge types and edge ownership are
  unchanged.
- Register addresses, packed node/edge fields, seed programming and readback are
  unchanged.
- Edge probability remains `edge_valid && (edge_rand7 <= edge_prob7)`. Therefore
  a valid edge code `p` has `(p+1)/128` acceptance probability; use `valid=0` for
  an exact zero edge.
- Bias probability remains `bias_rand7 < bias_prob7`. Bias code `p` has `p/128`
  acceptance probability, including exact zero at code 0.
- The final 16-bit spin comparator remains
  `prob16 == 0 ? false : rand16 <= prob16`.
- The tanh table, quantization, two-color order, vote threshold, simultaneous
  color commit, clamp behavior and LFSR polynomial are unchanged.

The LFSR transition is:

```text
next = ((state << 1) & 0xffffffff)
       | bit31(state) ^ bit21(state) ^ bit1(state) ^ bit0(state)
```

## RTL changes

Only four functional RTL files differ.

| File | Change | Python consequence |
|---|---|---|
| `mac.sv` | Adds `contrib_q[0:6]`; six edge terms plus bias are registered before the adder tree. | Edge/bias stochastic contributions are sampled one cycle earlier than the final 16-bit proposal random value. |
| `pbit_control.sv` | Adds `contrib_en`, `S_DRAIN_MAC`, and a second delayed-valid stage. | A phase takes one more clock and advances every node LFSR once more. |
| `pbit_bank.sv` | Registers seven positive tanh thresholds at phase start. | Use the I0 level captured for that phase; no LUT numeric change. |
| `unit_cell.sv` | Carries `contrib_en` into each shared MAC. | Structural wiring only; no new encoding or probability rule. |

## Exact per-phase timing

Let `N` be the actual majority sample count (`encoded_num_majority + 1`), and
let `R[k]` be the LFSR state after `k` advances from the state present when the
phase is accepted. `E0` is the phase-accept clock edge.

| Edge age | Operation |
|---|---|
| `E0` | Capture phase, color, I0 and majority threshold; no LFSR advance. |
| `E1..EN` | Register contribution trials 0..N-1 using edge/bias random bits from `R[0]..R[N-1]`. |
| `E2..E(N+1)` | Register the corresponding seven-term MAC sums. |
| `E3..E(N+2)` | Accumulate proposal bits 0..N-1; trial `t` uses `rand16(R[t+2])` with the MAC result formed from `R[t]`. |
| `E(N+3)` | Commit the majority result simultaneously for the active color and assert phase completion; LFSR reaches `R[N+3]`. |

Thus a Python trial must not use one random state for both stochastic edge/bias
terms and the final tanh comparison. For trial `t`:

```python
contrib_state = phase_states[t]       # R[t]
proposal_state = phase_states[t + 2]  # R[t+2]
```

The old RTL used `R[t+1]` for the proposal and ended a phase at `R[N+2]`; the
latest RTL uses `R[t+2]` and ends at `R[N+3]`.

## Run timing

The array controller consumes registered completion and launches the next color
on the following control edge. Consecutive `phase_start` pulses are therefore
`N+5` clocks apart. Starting from accepted `RUN_START`:

```text
phase count       = 2 * sweeps
clocks per sweep  = 2 * (N + 5)
total run clocks  = 2 * sweeps * (N + 5)
```

For example, `N=5` and 500 sweeps require 10,000 clocks from run acceptance to
`run_done`. The spin vector may change only at the two color-commit edges in
each sweep.

## Python update checklist

1. Keep all existing address, graph, quantization and probability semantics.
2. Build each contribution from `R[t]` and its pre-commit neighbor-spin snapshot.
3. Build the final 16-bit random value from `R[t+2]` using the existing XOR-bit
   extractor.
4. Collect exactly `N` votes, apply the existing majority threshold, then commit
   every node of the active color simultaneously.
5. Advance each shared node-pair LFSR through `R[N+3]` before the next phase.
6. Use `N+5` clocks per color if the Python model reports cycle counts.

The RTL regression `tb_run3x3.sv` independently predicts spins and final RNG
states with these rules. The seven generated problem tests additionally verify
configuration, cycle counts and every recorded sweep score.
