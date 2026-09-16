# Edge <= and bias < comparison variant

This branch derives from the validated Chimera RTL and gate-simulation branch.

- Edge acceptance remains `valid && (random_7bit <= probability_code)`.
- Edge `valid=0` represents an exactly disabled connection.
- Bias acceptance is `random_7bit < probability_code`.
- Bias code 0 therefore has exactly zero acceptance probability.
- Bias codes 1 through 127 represent `code / 128`; the maximum bias acceptance is `127/128`.
- The 16-bit p-bit state proposal comparison is unchanged.

The corresponding standalone `dc_350MHz_20_ss125_fanout32` flow synthesizes a 20x20 Chimera-unit array, or 3200 p-bits, at 350 MHz using the SS 1.08 V, 125 C standard-cell corner, matching SS I/O corner, typical PLL model, and a data max-fanout target of 32. Synthesis outputs and work directories are intentionally not stored in this repository.
