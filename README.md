# p-bit King Graph FPGA Project

This repository contains the source code and simulation testbenches for a UART-configurable p-bit King graph FPGA design.

## Directory Layout

- `top/`
  - Board-level top module.
  - Main file: `AXKU042_PBIT_TOP.sv`.

- `rtl/`
  - Synthesizable RTL modules.
  - Includes the p-bit array, p-bit node, update core, UART configuration bridge, LFSR RNG, tanh LUT, edge/bias compare logic, and majority vote logic.

- `sim/`
  - Simulation testbenches.
  - Includes tanh LUT tests, p-bit update core tests, King graph array tests, and UART top-level tests.

- `docs/`
  - SVG diagrams used for explaining the circuit and King graph structure.

- `vivado_project/`
  - Original Vivado project file for reference.
  - The source files in this upload are reorganized, so the `.xpr` may still reference the original Vivado project directory layout.

## Design Summary

The design implements a four-color King graph p-bit array. Each p-bit computes a local field from its neighboring p-bits and its own configurable bias term. Edge weights and bias terms use sign-controlled probabilistic compare logic. The update probability is generated through a tanh lookup table and compared against random bits from LFSR-based RNG logic.

