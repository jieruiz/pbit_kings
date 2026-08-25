# pbit_kings shared-LFSR/LUT 工作日志

更新时间：2026-08-25

## 当前工作区

- 本地新版本 worktree：`C:\Users\86134\Documents\a_P_BIT\pbit_kings_shared_lfsr_lut`
- 当前分支：`zenghongjie_version_3_shared_lfsr_lut`
- 基础来源：GitHub `jieruiz/pbit_kings.git` 的 `yanzenan_testversion_260724` 新版 RTL
- 远程服务器验证路径：`/public3/home/t6s011227/pbit_kings_shared_lfsr_lut/rtl/`
- 新版 RTL 目录：`rtl/new_version/`
- 新寄存器表：`rtl/pbit_register_file.xlsx`

## 新版 RTL 关键变化

- LFSR 从每个 p-bit 一个，改成每个 `2x2` tile 共用一个。
  - 40x40 阵列对应 `20x20 = 400` 个共享 LFSR。
  - node 配置仍使用物理节点坐标 `(row, col)`。
  - seed 配置使用 tile 坐标 `(row/2, col/2)`。
- tanh LUT 也改成每个 `2x2` tile 共用一个。
  - 4 个颜色相位分别选择 tile 内的 `h0/h1/h2/h3`。
- `NODE_CFG` 删除旧 `SEED_VALID`。
  - 当前有效位为 `INIT_VALID / CLAMP_VALID / BIAS_VALID`。
- `NODE_CMD` 从旧 5 位改成 8 位：
  - `APPLY_CFG`
  - `APPLY_SEED`
  - `LOAD_NODE`
  - `CLEAR_CFG_SCOPE_EN`
  - `CLEAR_SEED_SCOPE_EN`
  - `CLEAR_LOCAL_ALL`
  - `READBACK_CFG`
  - `READBACK_SEED`
- `GLOBAL_CFG` 中 sweep 和 majority 都改成寄存器值表示“实际值 - 1”。
  - 写实际 `num_sweeps=N` 时，寄存器写 `N-1`。
  - 写实际 `num_majority=M` 时，寄存器写 `M-1`。
- `SWEEP_INTERVAL` 也改成寄存器值表示“实际值 - 1”。
  - 新版里写 `0` 表示实际 interval 为 1，不再表示旧版的跳过/不用。

## 已发现并修复的 RTL 问题

文件：`rtl/new_version/pbit_array_kings.sv`

- 位置：共享 tanh LUT 输出连接到每个 p-bit 的局部阈值处。
- 原问题：
  - `p_up_thr_match_w` 被声明成 `logic`，只有 1 bit。
  - 但 `p_up_thr_w` 和 `pbit_node.p_up_thr_i` 都是 `LUT_WIDTH` 位，也就是 16-bit 概率阈值。
  - 这会截断 tanh LUT 输出，使自由 p-bit 的随机比较阈值错误。
- 修复：
  - 改成 `logic [LUT_WIDTH-1:0] p_up_thr_match_w;`
  - 修改处已加注释。
- 暴露方式：
  - `tb_run_3x3` 主要检查 clamp 节点，不能明显暴露。
  - `tb_run_3x3_majority` 的中心节点自由运行，能暴露该问题。

## 已适配并验证通过的 testbench

### `rtl/tb/tb_rw_basic.sv`

目的：

- 验证新版寄存器读写。
- 覆盖 edge 配置读写、node cfg 配置读写、node seed 配置读写。

主要适配：

- 去掉 `SEED_VALID`。
- `NODE_CMD` 改成 8 位新格式。
- node cfg 写物理坐标。
- node seed 写 tile 坐标。
- cfg readback 和 seed readback 拆开。

远程验证结果：

- VCS 编译/elab/link 0 error。
- `[TB_RW_BASIC] PASS`

### `rtl/tb/tb_run_3x3.sv`

目的：

- 验证最小 3x3 阵列配置和运行。

主要适配：

- `GLOBAL_CFG` 写实际值减 1。
- `SWEEP_INTERVAL` 写实际值减 1。
- node cfg 和 seed 分两次命令写入。
- seed 使用共享 tile 坐标。

远程验证结果：

- VCS 编译/elab/link 0 error。
- `[TB_RUN_3X3] PASS`

### `rtl/tb/tb_run_3x3_majority.sv`

目的：

- 验证不同多数表决次数配置是否生效。
- 验证自由中心点在正场下“大概率为 1”的统计趋势。

主要适配：

- 新 `NODE_CMD`。
- seed tile 坐标。
- sweep / majority / interval 都按实际值减 1 写入。
- 检查 `cnt_max` 是否随 actual majority 正确变化。
- 将中心点从单次硬断言改成统计检查：
  - `MAJORITY_STAT_TRIALS = 16`
  - `MAJORITY_MIN_CENTER_ONES = 10`
  - 每个 majority 跑 16 个固定 seed trial。

远程验证结果：

- 修复 `p_up_thr_match_w` 位宽后，`num_majority=1/5` 先通过。
- `num_majority=9` 单次可能为 0，因此改为统计验证。
- 统计版本已通过。

### `rtl/tb/tb_run_3x3_maxcut.sv`

目的：

- 进一步验证新版共享 LFSR/LUT 下的小规模 MaxCut 问题。
- 3x3 king graph，共 20 条边。
- 反铁磁耦合 `sign=0`，cut score 目标为最大化相邻不同。

主要适配：

- 去掉 `SEED_VALID`。
- `NODE_CMD` 改成新 8 位格式。
- node cfg 写物理坐标。
- node seed 写 tile 坐标。
- `GLOBAL_CFG` 写 actual sweep/majority 减 1。
- `SWEEP_INTERVAL` 写 actual interval 减 1。
- 当前小 schedule：
  - `i0 = 4, 16, 48`
  - 每个 level 实际 2 sweep。

远程验证状态：

- 已完成本地静态检查。
- 需要在远程服务器运行：

```bash
cd /public3/home/t6s011227/pbit_kings_shared_lfsr_lut/rtl/
rm -rf simv_run_3x3_maxcut simv_run_3x3_maxcut.daidir csrc ucli.key
vcs -full64 -sverilog -debug_access+all -kdb -f filelist_run_3x3_maxcut.f -o ./simv_run_3x3_maxcut
./simv_run_3x3_maxcut -l sim_run_3x3_maxcut.log
```

## 远程运行脚本注意事项

推荐脚本结构：

```bash
#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH -n 4
#SBATCH -J pbit_sim
#SBATCH -o sim-%j.out
#SBATCH -e sim-%j.err

set -eo pipefail

cd /public3/home/t6s011227/pbit_kings_shared_lfsr_lut/rtl/

set +u
source ~/.bashrc
set -u

echo "Node: $(hostname)"
echo "Job ID: $SLURM_JOB_ID"
echo "Start: $(date)"
echo "PWD: $(pwd)"

rm -rf simv_name simv_name.daidir csrc ucli.key
vcs -full64 -sverilog -debug_access+all -kdb -f filelist_xxx.f -o ./simv_name
./simv_name -l sim_xxx.log

echo "End: $(date)"
```

注意：

- 远程 Linux 脚本里不要混入 Windows 路径，例如 `C:\Xilinx\vivado\Vivado\2018.3\bin`。
- 若使用 Python 生成问题，服务器上 `python` 可能是 Python 2.7，应显式使用 `python3`。
- 已遇到过 `~/.bashrc` 中 `PS1: unbound variable`，用 `set +u; source ~/.bashrc; set -u` 可以避免。
- VCS 并行任务不要共用同一个 `simv` 输出目录，否则可能出现 `.daidir` 文件冲突。

## 下一步建议

1. 远程运行并确认 `tb_run_3x3_maxcut.sv`。
2. 迁移统一问题框架 `rtl/tb/tb_run_problem.sv`。
   - 当前已改为 node cfg 写 physical node，seed 写 shared-LFSR tile。
   - 1600 节点问题对应 `20x20 = 400` 个 tile seed。
3. 迁移 `rtl/tb/problem_gen/` 下的 Python 生成脚本。
   - 当前已改为生成 `problem_tile_seed[run][tile]`，不再生成 `problem_node_seed[run][physical]`。
   - `gen_problem.py`、`gen_native_king_maxcut.py`、`gen_tsp5_full_kings40.py` 已同步此格式。
   - 统一问题输入已收进 `rtl/tb/problem_gen/inputs/`，spec 不再依赖服务器外部 `p-bit_withbias`、根目录 `generated_W50.txt` 或根目录退火表路径。
   - `inputs/common/` 保存共享的 W50 embedding 和退火译码表；`inputs/w50_maxcut/`、`inputs/ksat_10v40c/`、`inputs/tsp5_full_kings40/` 保存各问题专属输入。
4. 小规模验证顺序建议：
   - `w50_maxcut`
   - `ksat_10v40c`
   - `local_qubo_10x10`
5. 全规模验证顺序建议：
   - native king maxcut 40x40
   - local QUBO 40x40
   - TSP5 full kings40

## 重要本地文件清单

- `rtl/new_version/pbit_pkg.sv`
- `rtl/new_version/pbit_array_kings.sv`
- `rtl/new_version/pbit_node.sv`
- `rtl/new_version/phase_control_4color.sv`
- `rtl/new_version/pbit_reg_block.sv`
- `rtl/pbit_register_file.xlsx`
- `rtl/tb/tb_rw_basic.sv`
- `rtl/tb/tb_run_3x3.sv`
- `rtl/tb/tb_run_3x3_majority.sv`
- `rtl/tb/tb_run_3x3_maxcut.sv`
- `rtl/tb/tb_run_problem.sv`
- `rtl/tb/problem_gen/gen_problem.py`
- `rtl/tb/problem_gen/specs/`
- `rtl/tb/problem_gen/inputs/common/`
- `rtl/tb/problem_gen/inputs/w50_maxcut/`
- `rtl/tb/problem_gen/inputs/ksat_10v40c/`
- `rtl/tb/problem_gen/inputs/tsp5_full_kings40/`

## 提交注意事项

- 当前 worktree 中 `sim/` 下两个文件可能显示为 modified，但此前判断主要是 CRLF/LF 行尾问题：
  - `sim/tb_p_bit_array_kings_3_3_direction.sv`
  - `sim/tb_p_bit_kings_graph_19_19.sv`
- 不要把无关行尾变化混入提交。
- `rtl/~$pbit_register_file.xlsx` 是 Excel 临时锁文件，不应提交。
- 建议提交时只 stage 有意改动：

```bash
git add rtl/new_version/pbit_array_kings.sv
git add rtl/tb/tb_rw_basic.sv
git add rtl/tb/tb_run_3x3.sv
git add rtl/tb/tb_run_3x3_majority.sv
git add rtl/tb/tb_run_3x3_maxcut.sv
git add WORK_LOG_zenghongjie_shared_lfsr_lut.md
```
