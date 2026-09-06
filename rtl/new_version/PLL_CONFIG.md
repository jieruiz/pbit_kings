# PLL 配置接口与 UART 通信说明

本文对应当前 `pbit_io_wrapper`、`pll_cfg_uart`、`pll_cfg_regs`、`UART_RX` 和 `pbit_uart_reg_master` 的实现。

配置 UART 在 25 MHz 参考时钟域工作，业务 UART 在 PLL 输出的核心时钟域工作。上电后 PLL 关闭、核心保持复位，必须通过配置 UART 发出合法 APPLY 才启动核心。PLL 重配期间配置 UART 仍可使用。

## 1. 时钟、波特率与参数

公共参数位于 `pbit_pkg.sv`：

| 参数 | 当前值 | 含义 |
|---|---:|---|
| `REF_CLK_FREQ_HZ` | `25_000_000` | 外部参考时钟频率，Hz |
| `CLK_FREQ_HZ` | `400_000_000` | 核心设计频率及默认 PLL 输出频率上限，Hz |
| `PLL_CFG_BAUD_RATE` | `1_000_000` | 配置 UART 波特率，bps |
| `BAUD_RATE` | `1_000_000` | 核心在设计频率下的业务 UART 波特率，bps |
| `PLL_CFG_BYTE_TIMEOUT_MS` | `20` | 配置域字节间超时时间，ms；同时决定两个域的默认超时周期数 |

UART 使用 8N1：1 位起始位、8 位数据、无校验、1 位停止位，每个字节内低位先发。RTL 通过 `CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE` 计算整数位周期。

- 配置 UART：25 MHz / 1 Mbps = **25 周期/位**，每位 1 μs。
- 业务 UART：400 MHz / 10 Mbps = **40 周期/位**，每位 100 ns。

业务位周期的计数值在编译时确定。运行时改变 PLL 频率不会自动修改它，上位机必须相应调整业务串口波特率。

| 实际核心时钟 | 业务周期/位 | 实际业务波特率 | 配置波特率 |
|---|---:|---:|---:|
| 400 MHz | 40 | 10 Mbps | 1 Mbps |
| 300 MHz | 40 | 7.5 Mbps | 1 Mbps |
| 25 MHz，BP 旁路 | 40 | 625 kbps | 1 Mbps |

上述参数都是编译期参数，不是可通过寄存器动态修改的 UART 配置。修改参考频率时，还需重新核对 PLL 合法配置、启动等待周期和 UART 整数位周期。

## 2. 顶层连接与复位

| 顶层端口 | 用途 |
|---|---|
| `pad_clk_i` | 外部 25 MHz 参考时钟 |
| `pad_rst_n_i` | 外部低有效复位 |
| `pad_pll_cfg_rx_i` / `pad_pll_cfg_tx_o` | 独立 PLL 配置 UART |
| `pad_uart_rx_i` / `pad_uart_tx_o` | 核心业务 UART |
| `pll_avdd` / `pll_avss` | PLL 模拟供电/地 |
| `pll_dvdd` / `pll_dvss` | PLL 数字供电/地 |
| `pll_dvdd_drv` / `pll_dvss_drv` | PLL 驱动供电/地 |

电源端口须接真实 PG 网络，不能接 tie-cell 输出。按 wrapper 使用要求，在 PLL 电源和参考时钟稳定前保持外部复位有效。

参考域和核心域各使用一个 `reset_sync_async_assert`：复位异步置位，在本域两个时钟上升沿后同步释放。核心同步器的复位输入为 `core_arst_n & core_release`，因此即使核心停钟，也能异步进入复位。

重新 APPLY 会复位核心。业务配置和运行状态不能视为跨 APPLY 保留，主机应按核心初始化流程重新配置。

## 3. 配置 UART 报文

发送二进制原始字节；下表用十六进制表示，不是发送 ASCII 字符串。

| 方向 | 第 1 字节 | 第 2 字节 | 第 3 字节 | 第 4 字节 |
|---|---|---|---|---|
| 请求 | OP | ADDR | DATA[15:8] | DATA[7:0] |
| 响应 | STATUS | 回显 ADDR | DATA[15:8] | DATA[7:0] |

OP：`01` 写，`02` 读。读请求的数据字段填 `0000`；写请求响应的数据字段为 `0000`。

| 响应 STATUS | 含义 |
|---|---|
| `00` | 本次寄存器访问成功；对 APPLY 仅表示已接受启动请求 |
| `01` | 非法操作码，由配置 UART 组帧层产生 |
| `02` | 寄存器访问或配置校验错误，具体原因读 STATUS 寄存器 |
| `03` | PLL 控制器忙，本次 SHADOW 写入或 APPLY 被拒绝 |

主机必须一问一答，接收完整 4 字节响应后再发下一请求。配置组帧层发送响应期间不接受新请求，不保证对违反此规则的请求返回忙响应。表中的 `03` 指控制器忙时拒绝访问。

接收端应在发送请求的同时监听响应，避免发完最后一个停止位后才监听而漏掉响应起始沿。报文没有 CRC；建议写 SHADOW 后读回核对，再 APPLY。

## 4. UART 停止位错误与半帧超时

### 4.1 共享 RX 的停止位校验

两路 UART 共用 `uart_rx_8n1`。停止位采样为高时，更新 `rx_data_o` 并产生一拍 `rx_valid_o`；采样为低时，丢弃该字节、不更新有效数据，并产生一拍 `rx_frame_err_o`。

错误后进入 `S_WAIT_IDLE`，等待同步后的 RX 恢复高电平，再重新寻找起始位。持续低电平不会反复产生有效字节或重复的停止位错误脉冲。

**当前两个组帧模块均未使用 `rx_frame_err_o`。** 因此错误字节已在 RX 层丢弃，但已有半帧不会因这个错误脉冲立即清除，也不会因此自动返回配置协议的 `01` 或设置 PLL ERROR_CODE。恢复时仍需依靠下述字节间超时；连续发送错位数据不能保证重新对齐。

### 4.2 两个域采用相同的超时周期数

配置模块参数为：

```systemverilog
parameter int BYTE_TIMEOUT =
    int'((64'(REF_HZ) * pbit_pkg::PLL_CFG_BYTE_TIMEOUT_MS) / 1000);
```

业务模块参数为：

```systemverilog
parameter int BYTE_TIMEOUT =
    int'((64'(pbit_pkg::REF_CLK_FREQ_HZ) * pbit_pkg::PLL_CFG_BYTE_TIMEOUT_MS) / 1000);
```

当前 wrapper 的 `REF_HZ` 等于 `REF_CLK_FREQ_HZ`，且两个 BYTE_TIMEOUT 均未单独覆盖，因此两域都为 **500,000 周期**。业务域没有按核心/参考频率比放大计数；修改公共超时参数会同时影响两域默认值。公式在编译期求值，不生成硬件乘除法器。

| 域/实际时钟 | 超时周期数 | 实际超时时间 |
|---|---:|---:|
| 配置域，25 MHz | 500,000 | 20 ms |
| 业务域，400 MHz | 500,000 | 1.25 ms |
| 业务域，300 MHz | 500,000 | 约 1.667 ms |
| 业务域，25 MHz 旁路 | 500,000 | 20 ms |

计时针对尚未收齐的请求：配置域为 1～3 字节，业务域为 1～6 字节。每个有效字节重新开始计时；收齐请求后不再对该请求执行字节间超时。截止周期到达的有效字节优先接收。

- 配置域超时：清除半帧字节计数，旧移位数据随后由新请求覆盖；不访问 PLL 寄存器，不产生额外响应，也不设置 PLL ERROR_CODE。
- 业务域超时：清除半帧字节计数、残留移位数据和计时器，产生一拍 `uart_frame_err_pulse_o`，进入原有业务错误状态记录路径；不发起寄存器访问或额外串口响应。

主机怀疑丢字节、帧错误或错位时，应先保持 RX 空闲高电平，等待超过相应域的超时时间并留出接收完成余量，再从完整请求首字节重发。若错误后仍连续发送有效字节，计时器会持续重启。

## 5. PLL 寄存器

地址为字节地址，数据为 16 位整字，不支持字节使能。奇数地址及未定义地址非法。

| 地址 | 名称 | 权限 | 外部复位后的值 |
|---|---|---|---|
| `00` | CFG_SHADOW | RW | `0220` |
| `02` | COMMAND | 写命令；读返回 `0000` | — |
| `04` | STATUS | RO | `0000` |
| `06` | CFG_ACTIVE | RO | `0220` |

CFG_SHADOW 是待应用配置；CFG_ACTIVE 是当前驱动 PLL 配置引脚的值。ACTIVE 的存在或数值正确不表示 PLL 已启用、核心已释放或 PLL 已锁定。

### 5.1 CFG_SHADOW / CFG_ACTIVE 位定义

| 位 | 名称 | 含义 |
|---|---|---|
| `[7:0]` | N | PLL 倍频配置 |
| `[8]` | SELECT | 0：倍率因子 1；1：倍率因子 2 |
| `[10:9]` | OD | 输出除数编码：00/01/10/11 对应 1/2/4/8 |
| `[11]` | BP | 1：旁路，CKOUT1 预期为参考时钟；0：使用 PLL 分频输出 |
| `[15:12]` | 保留 | APPLY 时要求为 0 |

数字控制器采用以下频率模型进行合法性校验：

```text
F_VCO = REF_HZ × N × (SELECT ? 2 : 1)
F_OUT = F_VCO / 2^OD
```

APPLY 要求：保留位为 0、N ≥ 17、500 MHz ≤ F_VCO ≤ 1200 MHz；BP=0 时还要求 F_OUT ≤ MAX_CORE_HZ，当前上限为400 MHz。BP=1 仍校验 N 和 VCO，跳过分频输出上限检查。

在25 MHz参考时钟下，VCO条件允许 SELECT=0 时 N=20～48、SELECT=1 时 N=17～24；BP=0 时还需选择合适 OD 才满足核心频率上限。这是当前 RTL 接受范围，实际采用的配置还需符合厂商 PLL 规格。

SHADOW 写入只检查地址和忙状态；即使配置不合法，也可以先写入和读回。真正的配置合法性检查发生在 APPLY。

### 5.2 COMMAND

| 写入值 | 操作 |
|---|---|
| `0001` | APPLY：校验并快照 SHADOW，启动或重新配置 PLL |
| `0002` | CLEAR_ERROR：清除粘滞错误 |
| 其他值 | 非法命令，ERROR_CODE=5 |

合法 APPLY 被接受时 DONE 清零、BUSY 置位；启动完成后再通过 STATUS 判断结果。忙时禁止写 SHADOW 或再次 APPLY，允许读寄存器和 CLEAR_ERROR。非法 APPLY 保持当前 PLL/核心运行状态和 ACTIVE 配置。

### 5.3 STATUS

| 位 | 名称 | 含义 |
|---|---|---|
| `[0]` | BUSY | 控制器处于启动/重配过程 |
| `[1]` | DONE | 本次 APPLY 已收到核心复位释放反馈；下次合法 APPLY 时清零 |
| `[2]` | ERROR | ERROR_CODE 非零 |
| `[3]` | BP_ACTIVE | ACTIVE 中的 BP 位 |
| `[4]` | PLL_EN | 当前 PLL 使能输出 |
| `[5]` | STARTUP_DONE | 固定启动等待已完成，不代表 LOCK |
| `[6]` | CORE_RESET_RELEASED | 核心复位释放状态经两级同步后的反馈 |
| `[7]` | 保留 | 0 |
| `[11:8]` | ERROR_CODE | 最近一次粘滞错误码 |
| `[15:12]` | 保留 | 0 |

成功访问不会自动清除旧错误，CLEAR_ERROR 不修改 DONE、ACTIVE 或运行配置。轮询时应结合 BUSY、DONE、ERROR 和 CORE_RESET_RELEASED，不能只看 STARTUP_DONE。

| ERROR_CODE | 原因 |
|---|---|
| 0 | 无错误 |
| 1 | 非法地址或写只读寄存器 |
| 2 | APPLY 配置保留位非零 |
| 3 | N < 17，或 VCO 超出 500～1200 MHz |
| 4 | BP=0 且输出超过 MAX_CORE_HZ |
| 5 | 非法 COMMAND |
| 6 | BUSY 时写 SHADOW 或 APPLY，对应协议响应 `03` |
| 7 | 核心复位释放反馈超时 |

ERROR_CODE=7 与 UART 字节间超时是不同事件。若 CLEAR_ERROR 和释放反馈超时同周期发生，超时错误优先。

## 6. PLL 启动与重配流程

控制器状态依次为：

```text
IDLE → HOLD_RESET → DISABLE_PLL → SET_CONFIG
     → ENABLE_PLL → WAIT_START → WAIT_RELEASE → IDLE
```

1. 接受合法 APPLY，快照 SHADOW，拉低 core_release，使核心异步进入复位。
2. 保持4个参考周期后关闭 PLL。
3. 将快照写入 ACTIVE，更新 N、SELECT、OD 和 BP。
4. 在后续状态使能 PLL，进入启动等待。
5. 等待 WAIT_CYCLES，默认 `(REF_HZ / 1_000_000) * 15`，当前为375周期，即15 μs。
6. 拉高 core_release；核心复位同步器收到两个 CKOUT1 上升沿后释放 core_rst_n。
7. core_rst_n 经两级寄存器同步回参考域，控制器确认后置 DONE 并结束 BUSY。

WAIT_RELEASE 的 RELEASE_TIMEOUT 默认1024参考周期，当前为40.96 μs，从固定启动等待结束后计时。最后允许周期收到反馈时，成功优先于超时。

反馈超时后 ERROR_CODE=7、DONE=0、BUSY=0，重新保持核心复位；PLL 仍保持使能，配置 UART 仍可清错并重新 APPLY。

设计没有 LOCK 输入、失锁检测、自动旁路或外部时钟切换器。固定15 μs等待及复位反馈不能证明模拟 PLL 已锁定；启动等待值须由目标 PLL 在采用配置和 PVT 条件下的规格支持。

## 7. 主机操作示例

以下每行请求都要等待完整响应，数值均为十六进制：

| 请求 | 作用 | 预期响应/处理 |
|---|---|---|
| `01 00 02 20` | 写400 MHz配置：N=32、SELECT=0、OD=1、BP=0 | `00 00 00 00` |
| `02 00 00 00` | 读回 SHADOW | `00 00 02 20` |
| `01 02 00 02` | 清除历史错误 | `00 02 00 00` |
| `01 02 00 01` | APPLY | `00 02 00 00`，仅表示请求已接受 |
| `02 04 00 00` | 轮询状态 | 完成且无错误时为 `00 04 00 72` |
| `02 06 00 00` | 读 ACTIVE | `00 06 02 20` |

确认核心已释放后，将业务串口设置为10 Mbps，再执行核心配置和运行操作。

- 300 MHz配置为 `0218`；APPLY成功后业务波特率为7.5 Mbps。
- 25 MHz旁路配置为 `0A20`；正常完成状态为 `007A`，业务波特率为625 kbps。
- 返回400 MHz时写 `0220` 并重新 APPLY，再把业务波特率恢复为10 Mbps。

若 APPLY 响应丢失，应先恢复配置通道组帧并查询 STATUS/ACTIVE，勿直接反复重发 APPLY，因为每次合法 APPLY 都会重新复位核心。

## 8. 工程入口与验证

PLL相关模块需先编译 `pbit_pkg.sv` 和公共触发器，再编译 UART、复位同步器、PLL配置模块和顶层依赖。独立测试入口位于 `rtl`：

| filelist | 仿真顶层 | 范围 |
|---|---|---|
| `filelist_pll_cfg_regs.f` | `tb_pll_cfg_regs` | 寄存器和配置合法性 |
| `filelist_pll_cfg_uart.f` | `tb_pll_cfg_uart` | 配置串口、报文及生产参数超时 |
| `filelist_pll_wrapper.f` | `tb_pll_wrapper` | 真实40×40核心与PLL控制集成 |
| `filelist_uart_rx_framing.f` | `tb_uart_rx_framing` | 两域RX停止位、持续低电平与恢复 |
| `filelist_uart_byte_timeout.f` | `tb_uart_byte_timeout` | 业务半帧、逐字节计时及超时边界 |

在已配置VCS和Slurm的集群上，从项目根目录使用现有脚本：

```bash
sbatch --export=ALL,TEST=pll_regs run_sim_sbatch.sh
sbatch --export=ALL,TEST=pll_uart run_sim_sbatch.sh
sbatch --export=ALL,TEST=pll_wrapper run_sim_sbatch.sh
```

脚本将RTL复制到独立的 `sim_runs` 任务目录，保存编译和仿真日志，并检查PASS标记。新增两个UART专项TB尚未加入该脚本的TEST分支，可在独立仿真目录使用对应filelist和顶层运行。本次没有在集群执行以上命令。

默认wrapper filelist使用 `tb/pll_cfg/pll_functional_model.sv` 理想PLL和 `io_functional_stubs.sv` 功能IO桩。脚本允许通过 `PLL_SIM_MODEL` 指定厂商PLL仿真模型，以替换理想PLL；替换时IO仍使用功能桩。厂商模型及其依赖需要另行提供，不能将PLL综合黑盒声明当作仿真模型，也不能同时编译多个同名PLL实现。

2026-09-06 本机 ModelSim 功能验证记录：

- PLL寄存器：4096配置，235接受、3861拒绝；另有默认等待周期下的忙时拒绝、停钟反馈超时和恢复验证。
- 配置UART：1 Mbps通信及500,000参考周期的半帧超时恢复通过。
- wrapper：400→300→25 MHz旁路→400 MHz，以及业务读写/快照通过。
- RX专项：每域1044个有效字节正确接收，3个错误停止位/持续低电平用例均拒绝；恢复、毛刺、接收中复位及有限位周期偏差用例通过。
- 业务超时专项：生产500,000周期，在400 MHz和25 MHz下验证1～6字节半帧、截止周期优先级、晚到字节、逐字节重新计时及复位恢复，通过。

上述是数字功能仿真结果。没有据此验证真实 PLL 锁定、抖动、电源行为或工艺IO电气特性；业务回归中使用过修正并行监听的TB副本，不能据此宣称全部原始业务TB均已修正。

## 9. 综合与时序集成要求

综合需使用目标工艺标准单元、IO及PLL对应的接口和时序库，排除仿真专用PLL/IO桩。所有PG端口连接、宏视图和实际引脚方向必须与后端采用版本一致。

- 建立25 MHz参考时钟与PLL输出时钟场景，覆盖400 MHz目标、采用的其他合法频率及BP旁路；按真实IP关系设置生成时钟、抖动和不确定度。
- 对外部reset、跨域core_release和UART异步输入，精确约束同步器入口；同步器级间保留正常时序检查。
- 对同步释放后的域内复位网络保留recovery/removal检查；同步soft reset按数据控制路径检查，避免把所有reset路径统一false-path。
- 核心复位释放反馈经两级同步回参考域，应落实CDC识别和布局要求；不能仅依据RTL的ASYNC_REG属性认定物理实现已完成。
- 完成真实网表的setup/hold、recovery/removal、最小脉宽及未约束路径审核，并结合CDC/RDC和宏集成检查。

当前项目内尚未提供可供本次审查使用的ASIC SDC、工艺时序库及物理STA报告。400 MHz物理时序和流片签核应以对应后端工程的实际报告为准。
