# 500 MHz gate-level supplemental regression

This directory adds four pin-only checks to the already passing `basic`,
`small`, `large`, and K4,4 MaxCut gate tests. It uses the same synthesized
20x20/3200-p-bit netlist, PLL model, I/O model, standard-cell model, external
UART protocol, and snapshot path.

The existing `large` case remains the full 3200-bit, ten-page snapshot test.
This fixed 20x20 netlist cannot prove padding behavior for a non-multiple-of-5
array size; the RTL 3x3 test covers that logic, while a gate-level check would
require a separately synthesized 16x16 (or another non-multiple-of-5) netlist.

## Tests

- `exact`: fixed seed, nonzero bias code 37, I0 level 10, majority 5. Eight
  one-sweep runs must produce node-0 sequence `10111110`. The expected values
  come from the cycle-exact pipeline Python model.
- `crossbank`: programs right/down type-4/type-5 edges owned by cell (4,4),
  crossing from BANK(0,0) to BANK(0,1) and BANK(1,0). Both MaxCut neighbors
  must flip while their clamped owners remain high.
- `boundaries`: checks register masking plus runs `(sweeps, majority)` values
  `(1,1)`, `(2,2)`, `(4,31)`, `(4,32)`, and `(5,5)`.
- `recovery`: performs two runs without reset, confirms a deliberately long
  run is busy, asserts the real asynchronous reset pin, reapplies the PLL
  configuration, and completes another run.

## Submit

From this directory on the server:

```bash
bash submit_gate_pipeline_regression.sh all max
```

The first argument is `all`, `exact`, `crossbank`, `boundaries`, or
`recovery`. The second is:

- `zero`: zero-delay netlist simulation.
- `max`: annotate the `MAXIMUM` field of the selected SDF (recommended first).
- `min`: annotate the `MINIMUM` field of the selected SDF.

`min` describes the selected SDF field; it is an FF-corner test only when
`SDF` points to an SDF generated at the FF corner. Override files when needed:

```bash
SDF=/absolute/path/ff_corner.sdf \
NETLIST=/absolute/path/design_gate.v \
bash submit_gate_pipeline_regression.sh all min
```

Each job creates a unique directory under `sim_runs/`. A successful full run
ends with `REGRESSION_SUITE_PASS.txt`; every individual log also contains a
test-specific `PASS` marker.
