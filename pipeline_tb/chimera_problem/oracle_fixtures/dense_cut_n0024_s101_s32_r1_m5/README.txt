Static cycle-exact oracle for the pipeline Chimera RTL regression.

Case: dense_cut_n0024_s101
Physical array: 20x20 Chimera cells, 3200 p-bits
Logical variables: 24
Runs: 1
Sweeps: 32
Majority trials: 5
Master seed: 2461
Initial-state seed: 314592
Schedule: linear, I0 request 0.1 through 4.0
Model: chimera-pipeline-20260920-edge-le-bias-lt-cycle-exact-v2

The files were generated locally from the same benchmark package and Python
cycle model used by gen_pipeline_oracle.py. The T6 regression copies this
directory verbatim and performs all comparisons in SystemVerilog, avoiding the
server NumPy/MKL runtime dependency.

The oracle updates all 3200 physical p-bits exactly like RTL. This includes
nodes outside the 282-node embedding; those nodes have no programmed problem
couplings but still receive zero-field stochastic updates in hardware.

Expected final sweep: cycles=640, score=620, best=670, broken=14, ties=1,
I0 level=25. Passing requires every sweep's full 3200-bit spin vector and all
reported metrics to match, not only the final values above.
