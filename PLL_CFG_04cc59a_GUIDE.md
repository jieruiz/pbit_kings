# Programmable PLL verification and DC (updated 2026-09-07)

The filename is retained for existing links. Current settings follow cc21c83:
both UARTs use 1 Mbps at their design clocks. The wrapper test now derives
business bit periods from the package divider and each checked PLL clock period.
The 2026-09-06 validation record below is historical, not a PASS for these edits.

Local validation on 2026-09-07: the updated full wrapper test passed in Xilinx
xsim 2018.3 using a temporary 4x4 array, real UART/core RTL, ideal PLL model and
functional pad stubs. It checked 400/300/25/400 MHz with business bit periods
1000/1333.3333/16000/1000 ns. No production RTL dimensions were changed.
This verifies the baud-transition test flow only; full 40x40/80x80 wrapper
regressions remain pending on the remote server.

## Original source baseline and current directories

Upstream: https://github.com/jieruiz/pbit_kings/tree/yanzenan_testversion_260724
Commit: 04cc59a8900419961b78adcaf6f0d18fc7b3826d.
Existing source and DC directories were not modified.

Current source directories:
- pbit_kings_random_enhanced_40x40_5fe1932: 1600 spins, 400 shared tiles, 4 LUT banks, 5 snapshot pages; directory name retained after cc21c83.
- pbit_kings_pll_cfg_80x80_04cc59a: 6400 spins, 1600 shared tiles, 16 LUT banks, 20 snapshot pages.

The original 04cc59a integration separated configuration baud from business baud.
Later upstream changes added XOR random extraction, UART framing/timeout handling
and set both BAUD_RATE and PLL_CFG_BAUD_RATE to 1_000_000. The 80x80 branch
retains its dimensions and corresponding problem row stride.

| Core register field | 40x40 | 80x80 |
|---|---|---|
| NODE/EDGE target row | bits 13:8 | bits 14:8 |
| NODE/EDGE target column | bits 21:16 | bits 22:16 |
| Snapshot page address | bits 2:0, pages 0..4 | bits 4:0, pages 0..19 |

The PLL register table is unchanged between sizes. For the expanded core target
fields, use the package constants above rather than old fixed six-bit host code.

## Two independent UART interfaces

| Interface | Clock | Baud at 400 MHz | Request / response |
|---|---|---|---|
| Business UART | PLL CKOUT1 | 1 Mbps, divider 400 | 7 bytes: OP/STATUS + 16-bit address + 32-bit data |
| PLL configuration UART | 25 MHz reference | 1 Mbps, divider 25 | 4 bytes: OP/STATUS + 8-bit address + 16-bit data |

See rtl/new_version/PLL_CONFIG.md and rtl/pll_register_file.xlsx for the PLL register map.
The core is held in reset and PLL disabled after power-on. Read/write SHADOW,
then write COMMAND=1 (APPLY), then read STATUS; an APPLY reply means accepted,
not locked or completed. STATUS=0x0072 is completed without a recorded error.
At 400 MHz, write SHADOW=0x0220. At 300 MHz, use 0x0218 with the SAME 25 MHz reference.
Business divider stays 400, so its baud becomes 750 kbps at 300 MHz.
APPLY resets the core; reload the problem configuration before starting a new
computation. Do not assume computation state survives a frequency change.
The config UART stays 1 Mbps at both frequencies. Bypass=0x0a20 gives 25 MHz core
and 62.5 kbps business UART. STARTUP_DONE is a timer, NOT analog PLL LOCK.

## Test coverage and limits

| TEST | What it checks |
|---|---|
| pll_regs | 4096 configurations, independent frequency-validity oracle, readback, BUSY rejection, atomic APPLY, missing reset feedback timeout and retry |
| pll_uart | Real 25 MHz/1 Mbps serial link, reset values, read/write, odd address/RO/opcode/command errors, sticky error clear, rejected APPLY, successful startup, production 20 ms partial-frame timeout |
| pll_wrapper | Actual wrapper + actual full-size pbit_top, two physical UART paths, initial reset, 400/300 MHz/bypass/restart, last-node/last-edge/shared-tile-seed reads and writes, snapshot bit from last page |
| rw | Existing business register/edge/node/seed tests, including high address bit at 80x80 |
| 3x3 / majority / maxcut3x3 | Existing array functionality, majority-count cases and small MaxCut |
| w50 / ksat | Existing standalone problem tests |
| problem | Python-generated configuration + unified TB + per-sweep score/cycle logging |

Business regressions instantiate pbit_top directly, intentionally avoiding PLL
and slow configuration UART overhead. They do NOT prove wrapper startup; run
pll_wrapper as well. The new small tests do not replace array/problem regressions.

pll_regs alone shortens WAIT_CYCLES/RELEASE_TIMEOUT for unit coverage.
pll_uart and pll_wrapper use production 375-reference-cycle startup wait.
The default wrapper PLL is an explicitly simulation-only ideal clock model,
and pad models are functional connectivity stubs. These tests do not sign off
PLL analog behavior, jitter, pad delays, CDC metastability, or physical timing.
To replace only the PLL model, set PLL_SIM_MODEL to an absolute vendor
behavioral Verilog path; do not supply the interface-only DC stub.
Vendor model support for bypass/startup still needs checking.

For bounded local checking, tb_pll_wrapper also supports +STARTUP_ONLY. It ends
after observing startup/reset release and measuring the 400 MHz clock, during
the APPLY reply; it does not replace the complete wrapper regression. The sbatch
script never enables this shortcut and always runs the complete wrapper case.

TB clock periods use real numbers (2.5 ns), target fields derive from package
widths, and snapshot decoding uses flat_idx=row*COLS+col, word=flat_idx/32,
bit=flat_idx%32. Seven-bit coordinates are tested in the 80x80 version.
The problem generator emits sized coordinate types and the current MAC/control/
comparator source list, without the unused one_counter. Existing problem sizes
are retained; 80x80 specs change physical row stride to rtl_cols=80, not the
mathematical problem. Always regenerate includes after changing a spec.
The unified TB now rejects generated geometry/stride/page/seed dimensions that
do not fit the compiled RTL, before sending any configuration writes.

## Upload and submit simulations

Upload both source folders under /public3/home/t6s011227/ with the same names.
Do not upload .git, __pycache__, outputs or sim_runs. All problem inputs are
already under rtl/tb/problem_gen/inputs; no external problem data paths are needed.

From the selected source root (not rtl/):

```bash
cd /public3/home/t6s011227/pbit_kings_random_enhanced_40x40_5fe1932
sbatch --export=ALL,TEST=pll_regs run_sim_sbatch.sh
sbatch --export=ALL,TEST=pll_uart run_sim_sbatch.sh
sbatch --export=ALL,TEST=pll_wrapper run_sim_sbatch.sh
sbatch --export=ALL,TEST=rw run_sim_sbatch.sh
sbatch --export=ALL,TEST=3x3 run_sim_sbatch.sh
sbatch --export=ALL,TEST=majority run_sim_sbatch.sh
sbatch --export=ALL,TEST=maxcut3x3 run_sim_sbatch.sh
sbatch --export=ALL,TEST=problem,SPEC=tb/problem_gen/specs/w50_maxcut.json run_sim_sbatch.sh
sbatch --export=ALL,TEST=problem,SPEC=tb/problem_gen/specs/ksat_10v40c.json run_sim_sbatch.sh
```

For 80x80, change only the cd directory to pbit_kings_pll_cfg_80x80_04cc59a.
Standalone W50/KSAT are TEST=w50 / TEST=ksat. For another generated problem,
change SPEC (e.g. local_qubo_40x40.json or native_king_maxcut_40x40.json).

Jobs request 4 CPUs / 64 GB, copy RTL and inputs into their own job directory,
and run VCS there. Concurrent jobs do not share generated includes, csrc or daidir.
No shared files are deleted. Python 3.6+ is required; use python3 on the server.
Results: source_root/sim_runs/TEST_JOBID/rtl/compile.log and sim_TEST.log.
The script requires both successful exit and a TB PASS line.

## Current DC upload and submission

For current 1 Mbps RTL use the separately supplied
dc_pbit_random_5fe1932_40_80_400MHz directory (its retained name now covers
40/80/100). Upload it alongside the current 40x40 source above, then run:

```bash
cd /public3/home/t6s011227/dc_pbit_random_5fe1932_40_80_400MHz
bash submit_dc_by_size.sh 40 80
```

Each task creates its own dimension-specific RTL copy. Reports use the cc21c83
baseline label. See that directory's README for resources and library paths.
Do not use the original 04cc59a DC scripts below unchanged: their baud checks
expect the old configuration.

## Historical DC setup (04cc59a)

Upload these new script folders alongside the source folders:
- dc_pbit_pll_cfg_40x40_400MHz_high_effort
- dc_pbit_pll_cfg_80x80_400MHz_high_effort

```bash
cd /public3/home/t6s011227/dc_pbit_pll_cfg_40x40_400MHz_high_effort
sbatch run_dc_high_effort_sbatch.sh
cd /public3/home/t6s011227/dc_pbit_pll_cfg_80x80_400MHz_high_effort
sbatch run_dc_high_effort_sbatch.sh
```

Defaults: 16 CPUs, 128 GB, compile_ultra -area_high_effort_script, no
-no_autoungroup. Six pads, two tie cells and PLL are dont_touch. The six
reset/feedback synchronizer flops are also preserved; other digital logic
can be optimized across hierarchy. Source is not rewritten by the scripts.
Library paths remain the prior standard-cell TT1.2V / IO v2p50 / PLL typ DBs;
see 01_setup.tcl. Check these paths on the server before submitting.

Results are under each script folder:
dc_result/pbit_io_wrapper_pll_cfg_DIM_400MHz_high_effort/JOBID/
Report/netlist/DDC/SDF/SDC/SVF filenames include the dimension and 400MHz.
jobs/JOBID/ contains dc_shell.log and RTL SHA256 fingerprints.
Power without switching activity remains an estimate, not measured power.

## Timing intent

- Reference pad clock: ref_clk, 40 ns. Config UART and PLL register/controller
  paths are timed at 25 MHz. UART baud is not a separate clock.
- PLL CKOUT1: generated clk, x16 of ref_clk, 2.5 ns. This is the selected
  0x0220 operating scenario, not a constraint that freezes programmable pins.
- Do NOT case-analyze N, OD, SELECT, BP, EN or core_release during synthesis:
  that could remove register/programming/startup circuitry.
- No blanket asynchronous clock groups. Except only the core reset
  synchronizer's async inputs and the feedback synchronizer's first D stage.
  Both synchronizer stage-to-stage paths and synchronized reset distribution
  remain timed. Missing/ambiguous endpoint matches stop the script.
- Both RX pad paths are cut only to their first synchronization D pin.
  Both TX pad paths are excluded from setup/hold optimization because no board
  budget has been supplied. This is not UART/pad timing signoff.
- Setup uncertainty=0.100 ns, hold=0.050 ns, transition=0.100 ns, matching prior
  exploratory settings. They are not measured PLL jitter.
- Core, ref, cross-domain, max/min timing, constraints and protected-IP reports
  are separate. Max/min reports include capacitance/transition/net information.
- Bypass, other programmed frequencies, SS/FF corners, CTS and extracted RC,
  reset-domain crossing, PLL control settling/enable sequencing and pad/board
  electrical constraints still need signoff. A synthesis PASS is not tapeout approval.

Reference on why reset crossings need dedicated verification:
https://www.synopsys.com/verification/static-and-formal-verification/vc-spyglass/vc-spyglass-rdc.html

## Historical local validation record (2026-09-06, before baud updates)

- Xilinx xsim 2018.3: TB_PLL_CFG_REGS PASS. All 4096 configurations tested;
  235 accepted, 3861 rejected; timeout/BUSY/retry checks passed.
- Xilinx xsim 2018.3: TB_PLL_CFG_UART PASS at 115200 baud / 25 MHz, including
  the production 20 ms partial-frame timeout.
- Full 40x40 and 80x80 wrapper RTL elaborated successfully in xelab 2018.3.
- STARTUP_ONLY integration checks passed for BOTH sizes: 15 us minimum wait,
  core reset release, measured 2.5000 ns clock, bank counts 4 and 16.
- Both wrappers and all seven business TBs passed xvlog syntax compilation.
- All seven bundled problem specs generated data and score includes for both
  sizes (14 generator smoke tests). This is not a solver-quality result.
- Bash syntax checks passed for both simulation and both DC submission scripts.
- tests/check_dc_pll_cfg_scripts.py passed mocked Tcl control-flow checks;
  tests/check_pll_cfg_release.py passed source/filelist/geometry/Python-3.6-syntax checks.
- The full 40x40 wrapper run was stopped locally because of runtime cost; it
  was NOT counted as passed. Full wrapper reconfiguration/business readback,
  all business functional regressions and all VCS/DC/library/STA checks remain
  to be run on the remote server. No claim of physical/analog PLL signoff is made.
- Previous source/DC directories and remote Git branches were not modified.
