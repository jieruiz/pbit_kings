# Chimera 问题级仿真指南

## 对应版本与范围

本套新增文件针对 `pbit_chimera` 分支的 `cf76b05` RTL，不改变 `rtl/new_version`、基本读写 TB 或 DC 脚本。
阵列保持 **20×20 个 K4,4 单元，即 3200 个 p-bit**。这里的案例占用其中部分节点，但配置、清零和快照检查覆盖整个阵列。
本套验证数字核心，不包含 I/O PAD、模拟 PLL 或门级时序验证。

采用一个共用的 `rtl/tb/tb_run_chimera_problem.sv`，由不同案例生成不同配置数据，不复制七份配置/评分逻辑。

## 七个代表案例

选自已有 `p_bit_chimera/anneal32_hardware_problem_suite.py` 的默认套件：

| `--case` | 问题 | 逻辑 Ising 节点 | 占用 p-bit | 非零物理 J | 原问题目标 |
|---|---|---:|---:|---:|---:|
| `random_cut_n0096_s401` | 随机加权 MaxCut，96 顶点 | 96 | 318 | 414 | cut=354 |
| `dense_cut_n0024_s101` | 稠密 MaxCut，24 顶点 | 24 | 282 | 534 | cut=834 |
| `random3_cut_n0096_s901` | 多三角结构 MaxCut，96 顶点 | 96 | 823 | 1003 | cut=500 |
| `native_cut_n0448_s201` | 局域结构 MaxCut，448 顶点 | 448 | 512 | 1470 | cut=5847 |
| `random_sat3_n0024_s401` | planted 3-SAT，24 变量/96 子句 | 120 | 555 | 793 | 满足 96 |
| `uniform_sat3_n0060_s501` | uniform 3-SAT，60 变量/240 子句 | 300 | 2381 | 2998 | 满足 240 |
| `random_sat4_n0012_s401` | planted 4-SAT，12 变量/96 子句 | 204 | 935 | 1333 | 满足 96 |

SAT 的逻辑 Ising 节点包括辅助变量，不等于原始布尔变量数。上述目标来自案例证书，并经证书 assignment 重新计分校验；不代表 RTL 每次都能达到该目标。

## 配置如何生成

- 输入：每个案例的 `problem.json`、`physical_ising.json`、`embedding.json`、`certificate.json`，已原样复制到 `rtl/tb/chimera_problem_gen/inputs/<case>/`。远程不需要原来的外部目录。
- 节点编号：`((unit_row*20+unit_col)*8 + shore*4 + track)`；写入 `UNIT_TARGET` 后写 `NODE_TARGET`，不使用按行或全阵列广播。
- 边所有权：类型 0..3 为单元内左侧 track，edge number 为右侧 track；类型 4 为向右的 shore=1 边；类型 5 为向下的 shore=0 边。外边由左/上端单元持有，每条边仅写一次，边界外不发命令。
- 所有 **9440 条合法物理边**均写入并回读，未使用边写 disabled/zero，避免无复位边寄存器残留。3200 个节点及 1600 个共享 LFSR 种子也全部配置并回读。
- 能量约定为 `E=offset+sum(h*s)+sum(J*s*s)`。RTL MAC 要实现 `-h-sum(J*s)`，因此源系数为负时 RTL sign=1；源系数为正时 sign=0。
- 概率量化保持原脚本的 `round(abs(value)/scale*127)`，`scale=max(1, max(abs(h)), max(abs(J)))`，ties-to-even。偏置保持原来的物理落点，不复制或重新分摊。
- 每次 run 的 LFSR master seed 为 `2461+10*run`，初始 spin seed 为 `314592+7919*run`；Python 生成 1600 个排序后的不重复非零种子，初始 spin 由原模型的 LFSR 算法生成。不是从最优解初始化。
- `--sweeps`、`--majority` 和阶段实际轮数是人类填写的实际次数，生成器写寄存器时分别减一。

## 退火设置

默认：3 个 run、每次 200 sweeps、多数表决 5 次，期望系数按 32 点从 0.1 线性增加到 4.0，再选当前 RTL 表中最接近的 I0 档。

表在 `rtl/tb/chimera_problem_gen/inputs/anneal_i0_32_dec.txt`。该表来自之前的 32 档表，与此 Chimera RTL 的 LUT 对照；不会使用旧 64 档线性编号。
每轮阶段位置按原 Python 模型的 `round(31*s/(S-1))` 分配，连续重复 I0 会合并成一个硬件阶段。最终精确阶段表记录在 `manifest.json`，日志也输出 I0 与持续轮数。

可选：

```bash
# 使用全部 32 档实际 LUT 系数
python3 tb/chimera_problem_gen/gen_chimera_problem.py --schedule table
# 固定为最接近 1.0 的实际档位
python3 tb/chimera_problem_gen/gen_chimera_problem.py --schedule fixed --i0-start 1.0
# 改变试验次数、种子、多数表决、退火范围
python3 tb/chimera_problem_gen/gen_chimera_problem.py --runs 3 --sweeps 1000 --majority 9 --seed-master 3461 --init-seed 414592 --i0-start 0.1 --i0-end 4.0
```

Python 理论求解器的随机数抽取方式、LFSR 每阶段推进节拍与当前 RTL 不完全相同；未使用节点的更新方式也有差异。这里移植的是同一个量化问题与初始配置，**不是逐拍等价的 Python 模型**，不以逐轮轨迹一致作为 PASS 条件。

## 两种传输方式

1. 默认 `bus`：TB 驱动生产 `pbit_reg_block` 的寄存器总线，经过真实 NODE/SEED/EDGE 请求握手、bank 流水线与阵列。绕过的是 UART 串行收发，不是配置译码，更不是强制写内部寄存器。适合大量求解仿真。
2. `uart`：同一个 test harness 使用生产 `pbit_uart_reg_master`，所有读写通过真实串行帧，以包中波特率运行。它明显慢得多。harness 的核心连接按 `pbit_top` 展开，仅增加 TB 总线选择，不修改生产顶层。

`+UART_SMOKE` 还可在问题仿真前单独做实际波特率的 UART 基础事务，然后继续 bus 模式。完整协议错误覆盖仍由已有 `tb_rw_basic.sv` 负责。

提交脚本可通过环境变量启用该检查：

```bash
UART_SMOKE=1 sbatch run_chimera_problem_sbatch.sh random_cut_n0096_s401 --runs 1 --sweeps 32
```

## Additional directed regressions

Three independent tests cover the interfaces and corner cases that are not
efficient to repeat for every generated optimization problem:

| Test | Coverage |
|---|---|
| `uart_end_to_end` | Production 1 Mbps UART, NODE/SEED/EDGE write and readback, RUN, status and snapshot |
| `config_boundaries` | Actual-minus-one count encoding, majority 1/2/31/32, stage intervals, I0 order, exact cycle count and field masks |
| `error_paths` | Busy conflicts, runtime configuration rejection, sticky UART errors, interrupted reset and back-to-back runs |

Submit all three from the repository root:

```bash
bash submit_chimera_extra_tbs.sh
```

Or submit one test:

```bash
sbatch run_chimera_extra_tb_sbatch.sh uart_end_to_end
sbatch run_chimera_extra_tb_sbatch.sh config_boundaries
sbatch run_chimera_extra_tb_sbatch.sh error_paths
```

Each job uses an isolated directory under
`sim_chimera_extra/<test>/<job-id>/rtl`, so concurrent VCS compilations do not
share `simv.daidir` or `csrc`.

## 远程提交

将整个本地 `pbit_kings_chimera_cf76b05` 上传到：

```text
/public3/home/t6s011227/pbit_kings_chimera_cf76b05/
```

在登录节点只提交 sbatch，不直接运行 VCS：

```bash
cd /public3/home/t6s011227/pbit_kings_chimera_cf76b05
sbatch --job-name=chimera_cut96 run_chimera_problem_sbatch.sh random_cut_n0096_s401 --runs 3 --sweeps 200 --majority 5
sbatch --job-name=chimera_sat3 run_chimera_problem_sbatch.sh random_sat3_n0024_s401 --runs 3 --sweeps 200 --majority 5
sbatch --job-name=chimera_sat4 run_chimera_problem_sbatch.sh random_sat4_n0012_s401 --runs 3 --sweeps 200 --majority 9
```

其余案例替换第一个参数即可。脚本默认 4 核/16 GiB，符合此前发现的每核约 4 GiB 内存配额；实际分配由平台调度策略决定。每个 job 独立复制 RTL、生成数据和编译，不共用 `simv/csrc/.daidir`。

一次提交全部七个：

```bash
chmod +x submit_chimera_cases.sh
./submit_chimera_cases.sh

# 可选覆盖默认值（默认 runs=3、sweeps=500、majority=5）
RUNS=5 SWEEPS=1000 MAJORITY=5 ./submit_chimera_cases.sh
```

完整 UART 模式：

```bash
sbatch --export=ALL,TRANSPORT=uart --job-name=chimera_uart_cut96 run_chimera_problem_sbatch.sh random_cut_n0096_s401 --runs 1 --sweeps 32
```

结果目录：`sim_chimera/<case>/<jobid>/rtl/`，提交标准输出/错误在项目根目录 `chimera-<jobid>.out/.err`。

在已申请的交互计算节点，手动流程为：

```bash
cd /public3/home/t6s011227/pbit_kings_chimera_cf76b05/rtl
python3 tb/chimera_problem_gen/gen_chimera_problem.py --case random_cut_n0096_s401
vcs -full64 -sverilog -f filelist_run_chimera_problem.f -top tb_chimera_problem -o simv_chimera
./simv_chimera -l sim_chimera.log
python3 tb/chimera_problem_gen/check_results.py
```

## 输出与 PASS 定义

- `compile_chimera.log` / `sim_chimera.log`：编译及运行日志。
- `tb/chimera_generated/manifest.json`：案例、输入哈希、量化比例、实际阶段和配置参数。
- `chimera_sweeps.csv`：每个 run 每轮的分数、最佳分数、断链/平票数、I0 和周期数。
- `chimera_states.txt`：最终与最佳物理 spin、最佳逻辑解，可重新译码核对。
- `python_score_check.log`：Python 对最终与最佳物理状态独立译码，重新计算原 MaxCut/SAT 分数并与 TB 比对。
- `input_sha256.txt`：该次任务使用的 RTL、公共 DFF 和生成配置的哈希。

周期从 `phase_control` 真正接受 RUN 的时钟边沿计数，到完整两色 sweep 完成事件截止。不包含写配置、串口 ACK 或快照读取时间。
`first_success=0` 表示此 run 未达到证书目标，不是第 0 轮达到。多数表决次数或随机初始种子改变后，最早成功轮数也可能变化。

`[TB_CHIMERA_PROBLEM] PASS` 表示以下检查通过：所有配置回读、初始 spin、各页快照、正确两色顺序、全部 bank 同拍完成、准确 sweep 数与 I0 调度、无 X 状态、无寄存器错误，以及结束后状态保持。
它**不代表每次都找到最优解**。优化质量另看 `success_runs`、`best/target`、`first_success` 和断链数量。原问题达到目标但链有断裂，说明逻辑译码成功，不代表物理嵌入无断链成功。

需要把求解质量设为硬性测试条件时，可指定每个 run 的最低 best 分数：

```bash
sbatch --export=ALL,MIN_SCORE=354 run_chimera_problem_sbatch.sh random_cut_n0096_s401
# 或执行仿真时附加 +MIN_SCORE=354
```

## 验证工具

`python3 rtl/tb/chimera_problem_gen/test_generator.py`：地址无冲突、二分图着色、种子、配置镜像、表与 RTL 的一致性、全部七个案例的证书和配置检查。
`verify_local.py`：可选本地 Vivado Simulator 回归，不改 RTL；它的运行输出必须单独保留，不能将仅生成数据或仅编译通过当作功能 PASS。
