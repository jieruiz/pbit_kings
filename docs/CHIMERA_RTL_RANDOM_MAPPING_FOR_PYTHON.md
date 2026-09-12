# Chimera RTL random mapping for Python models

This document records the bit-exact random-number behavior of the current
Chimera RTL. It is intended to be the reference for Python models that must
reproduce a fixed RTL seed, not merely match the RTL statistically.

Reference RTL directory: `rtl/new_version`

## 1. State and node mapping

Each Chimera unit contains eight nodes:

- nodes `0..3`: shore/column 0, tracks `0..3`;
- nodes `4..7`: shore/column 1, tracks `0..3`.

There are four 32-bit LFSRs per unit. LFSR track `r` is shared by nodes `r`
and `r+4`. Therefore an `ROWS x COLS` array contains
`ROWS * COLS * 4` LFSRs for `ROWS * COLS * 8` p-bits.

For a flat node number:

```python
node = ((unit_row * COLS + unit_col) * 8) + shore * 4 + track
lfsr_id = ((unit_row * COLS + unit_col) * 4) + track
```

The two shores do not own separate random states. They consume consecutive
parts of the same LFSR sequence in their respective update phases.

Source: `unit_cell.sv`, `GEN_DATAPATH`.

## 2. LFSR32 recurrence

The current state is the random word presented to the MAC and comparator
logic. The next state is:

```systemverilog
feedback = state[31] ^ state[21] ^ state[1] ^ state[0];
next      = {state[30:0], feedback};
```

Equivalent Python:

```python
MASK32 = 0xFFFFFFFF

def lfsr32_step(state: int) -> int:
    state &= MASK32
    feedback = (
        ((state >> 31) ^ (state >> 21) ^ (state >> 1) ^ state) & 1
    )
    return ((state << 1) & MASK32) | feedback
```

External register writes convert seed `0` to seed `1`. Reset also initializes
the LFSR to `1`. The LFSR module itself does not repair a zero state, so a
Python model should perform the same conversion at the register-write
boundary:

```python
stored_seed = 1 if (requested_seed & MASK32) == 0 else requested_seed & MASK32
```

An accepted seed write has priority over an LFSR advance. Seed readback is the
current LFSR state, not a shadow copy of the originally written seed.

Sources: `lfsr32_rng32.sv`, `pbit_reg_block.sv`.

## 3. Six edge random values

All six edge decisions for one active node use overlapping 7-bit slices of
the same current 32-bit LFSR state. They are not six independent random draws.

| MAC lane | RTL expression | Source bits | Python expression |
|---:|---|---|---|
| 0 | `rnd32[0 +: 7]`  | `6:0`   | `(state >> 0)  & 0x7f` |
| 1 | `rnd32[4 +: 7]`  | `10:4`  | `(state >> 4)  & 0x7f` |
| 2 | `rnd32[8 +: 7]`  | `14:8`  | `(state >> 8)  & 0x7f` |
| 3 | `rnd32[12 +: 7]` | `18:12` | `(state >> 12) & 0x7f` |
| 4 | `rnd32[16 +: 7]` | `22:16` | `(state >> 16) & 0x7f` |
| 5 | `rnd32[20 +: 7]` | `26:20` | `(state >> 20) & 0x7f` |

```python
def edge_random7(state: int, lane: int) -> int:
    if not 0 <= lane < 6:
        raise ValueError("edge lane must be 0..5")
    return (state >> (4 * lane)) & 0x7F
```

The lane meanings depend on the active shore:

- active shore 0, node `r`: lanes `0..3` are the four internal neighbors,
  lane 4 is up, and lane 5 is down;
- active shore 1, node `4+r`: lanes `0..3` are the four internal neighbors,
  lane 4 is left, and lane 5 is right.

For configured edge types, types `0..3` are the internal K4,4 edges. Type is
the shore-0 track and number is the shore-1 track. Type 4 is a right external
edge and type 5 is a down external edge; `number` selects track `0..3`.

Source: `edge_compare6.sv`, `unit_cell.sv`.

## 4. Edge comparison and contribution

For every lane, the current RTL performs:

```python
edge_accept = bool(edge_valid) and (edge_random7(state, lane) <= edge_prob7)
```

Consequently:

- `valid=0`: contribution is exactly zero for every probability code;
- `valid=1, prob=0`: nominal acceptance probability is `1/128`;
- `valid=1, prob=p`: nominal acceptance probability is `(p+1)/128`;
- `valid=1, prob=127`: acceptance probability is one.

The `valid` bit is persistent edge configuration. A zero-weight/absent edge
must therefore be encoded as `valid=0`. Setting `valid=1, prob=0` encodes the
smallest nonzero stochastic edge, not a disabled edge.

The sign and spin encoding is:

- `edge_sign=1`: `J=+1`;
- `edge_sign=0`: `J=-1`;
- `neighbor_spin=1`: `s=+1`;
- `neighbor_spin=0`: `s=-1`.

An accepted edge contributes `J*s`; a rejected edge contributes zero.

Sources: `edge_prob_compare.sv`, `pbit_edge_contrib2.sv`,
`edge_reg_coupler.sv`.

## 5. Bias random value and comparison

Bias uses seven even-numbered bits from the same current LFSR state:

```systemverilog
bias_rand = {state[12], state[10], state[8], state[6],
             state[4], state[2], state[0]};
```

The leftmost item is output bit 6. Equivalent Python:

```python
def bias_random7(state: int) -> int:
    return sum(((state >> (2 * bit)) & 1) << bit for bit in range(7))
```

The current comparison is:

```python
bias_accept = bias_random7(state) <= bias_prob7
```

There is no persistent runtime bias-enable bit. `BIAS_VALID` in `A_NODE_CFG`
is only a write mask controlling whether a configuration transaction updates
the bias sign and probability registers. In the MAC, bias comparator
`valid_i` is tied to one.

Therefore the current RTL behavior is:

- `bias_prob=0`: nominal acceptance probability is `1/128`, not zero;
- `bias_prob=p`: nominal acceptance probability is `(p+1)/128`;
- `bias_prob=127`: acceptance probability is one.

Bias is evaluated as an edge to a fixed `+1` neighbor. An accepted bias
contributes `+1` when `bias_sign=1` and `-1` when `bias_sign=0`. After reset,
both bias registers are zero, so an otherwise unconfigured node has a small
negative residual bias in the current implementation.

If RTL is later changed to make code zero mean exactly zero, the Python line
must change to:

```python
bias_accept = (bias_prob7 != 0) and (bias_random7(state) <= bias_prob7)
```

Do not change `<=` to `<` globally: that would shift all nonzero codes and
would make code 127 less than one.

Sources: `mac.sv`, `pbit_node.sv`, `edge_prob_compare.sv`.

## 6. MAC field

For one trial, the registered field is the signed sum of six possible edge
contributions and one possible bias contribution:

```python
h = sum(edge_contribution[0:6]) + bias_contribution
```

The legal mathematical range is `-7..+7`. All edge decisions and the bias
decision in this field use the same current LFSR state. Their random values
are correlated by the fixed bit mapping above.

## 7. Proposal random value

The 16-bit random value used after the tanh threshold is not `state & 0xffff`.
It is the following XOR mapping:

| Output bit | XOR of LFSR bits |
|---:|---|
| 0  | 23, 28 |
| 1  | 9, 22 |
| 2  | 5, 14 |
| 3  | 11, 18 |
| 4  | 19, 30 |
| 5  | 21, 29 |
| 6  | 17, 26 |
| 7  | 10, 24 |
| 8  | 16, 28 |
| 9  | 2, 15 |
| 10 | 6, 25 |
| 11 | 8, 27 |
| 12 | 12, 31 |
| 13 | 0, 7 |
| 14 | 20, 24 |
| 15 | 4, 18 |

```python
PBIT_RAND16_XOR_BITS = (
    (23, 28), (9, 22), (5, 14), (11, 18),
    (19, 30), (21, 29), (17, 26), (10, 24),
    (16, 28), (2, 15), (6, 25), (8, 27),
    (12, 31), (0, 7), (20, 24), (4, 18),
)

def pbit_random16(state: int) -> int:
    value = 0
    for out_bit, (a, b) in enumerate(PBIT_RAND16_XOR_BITS):
        value |= ((((state >> a) ^ (state >> b)) & 1) << out_bit)
    return value
```

Sources: `pbit_rand16_extract.sv`, `comparator_vote.sv`.

## 8. Tanh threshold comparison

The 16-bit threshold must come from the exact table in `tanh_LUT.sv` for the
selected 5-bit I0 level and signed field. The selector behavior is:

- `h=0`: threshold `0x8000`;
- `h=+1..+7`: positive table entry;
- `h=-1..-7`: bitwise complement of the corresponding positive entry;
- an encoded `h=-8` is saturated to magnitude 7.

The proposal comparison is:

```python
proposal_is_up = False if threshold16 == 0 else (
    pbit_random16(proposal_state) <= threshold16
)
```

Thus threshold zero is exactly zero probability. For every nonzero threshold,
the RTL retains the inclusive comparison. In particular, threshold `0x8000`
accepts 32769 of 65536 ideal uniformly distributed codes, and `0xffff` always
accepts.

Sources: `tanh_LUT.sv`, `pbit_prob_compare16.sv`.

## 9. Per-trial LFSR timing

The MAC is registered and the proposal accumulator is delayed by one cycle.
For each vote trial `k`, the field uses LFSR state `S[k]`, while the proposal
comparison for that field uses the next state `S[k+1]`.

A compact software equivalent for one phase is:

```python
votes = []
state = phase_start_state

for _ in range(N):
    field = rtl_mac_field(state, fixed_neighbor_snapshot, edge_cfg, bias_cfg)
    state = lfsr32_step(state)
    threshold = exact_rtl_tanh_threshold(i0_level, field)
    votes.append(pbit_random16(state) <= threshold if threshold else False)

# DRAIN capture edge and COMMIT edge both advance the LFSR.
state = lfsr32_step(state)
state = lfsr32_step(state)
```

Therefore each phase advances every shared LFSR exactly `N+2` times. A full
two-phase sweep advances it `2*(N+2)` times. The phase-start acceptance edge
does not advance the LFSR. States are not reset between phases, sweeps, or
annealing rounds.

Sources: `pbit_control.sv`, `lfsr32_rng32.sv`, `mac.sv`,
`comparator_vote.sv`.

## 10. Two-color update order

The configured majority field is a code `M=0..31`; the actual number of
proposal trials is `N=M+1`.

For unit `(row, col)`:

```python
active_shore = phase ^ ((row + col) & 1)
```

Phase 0 updates one endpoint from every shared-LFSR pair. Phase 1 updates the
other endpoint. All spins not belonging to the active phase remain fixed while
the active phase collects its proposals.

The RTL positive-vote threshold is not generally equivalent to an unconditional
`votes > N/2` expression for every even `N`. Reproduce the configured formula:

```python
M = configured_num_majority & 0x1F
N = M + 1
vote_threshold = (M >> 1) + 1 + ((M & 1) & ((M >> 1) & 1))
new_spin_bit = int(positive_vote_count >= vote_threshold)
```

A clamped node ignores the committed majority result and retains its configured
clamp spin.

Sources: `phase_control.sv`, `pbit_bank.sv`, `pbit_node.sv`.

## 11. Audit of the existing standalone Python simulator

The current standalone file
`../p_bit_chimera/chimera_pbit_hardware_sim.py` is based on an older random
mapping and is not bit-exact with this RTL revision. At the time this document
was written, the following items differ:

1. `EDGE_BITS_MSB` uses six older non-contiguous bit maps; current RTL uses the
   overlapping contiguous slices listed in section 3.
2. `BIAS_BITS_MSB` uses older source bits; current RTL uses bits
   `12,10,8,6,4,2,0`.
3. Proposal random currently uses `lfsr_state & 0xffff`; current RTL uses the
   16 XOR pairs in section 7.
4. `_active()` treats code zero as disabled and uses `<`; current RTL uses
   `<=`. Edge zero remains disabled only when its separate valid bit is zero,
   while bias code zero is currently accepted on random code zero.
5. `PHASE_OVERHEAD_LFSR_STEPS` is three after the per-trial loop; current RTL
   requires two additional steps after the loop, for `N+2` total advances.
6. The simulator computes a floating-point `tanh` probability. Bit-exact
   matching requires the actual 32-level, signed-field threshold table from
   `tanh_LUT.sv` and the comparison in section 8.
7. `votes > 0` agrees with ordinary odd-N majority cases, including the common
   N=5 case, but the exact RTL threshold formula must be used for all supported
   even-N settings.

These differences can still produce similar aggregate optimization statistics,
but they will not reproduce the same fixed-seed sweep trajectory. A single
different early proposal can change later spins even though the underlying LFSR
states continue to advance deterministically.

## 12. Minimum bit-exact checklist

A Python model claiming fixed-seed equivalence should verify all of the
following:

- zero seed is converted to one at the configuration boundary;
- four LFSRs per unit and two p-bits per LFSR;
- exact LFSR recurrence and unsigned 32-bit masking;
- six overlapping edge slices from one shared state;
- exact bias bit gather from the same state;
- edge `valid` gating and inclusive `<=` comparison;
- current zero-bias residual behavior, unless RTL is intentionally changed;
- proposal XOR mapping from the next LFSR state;
- exact 16-bit LUT entries and zero-threshold special case;
- `N=M+1`, exact vote threshold, DRAIN and COMMIT advances;
- checkerboard two-color order and no LFSR reset between phases.
