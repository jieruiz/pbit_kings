# PLL配置接口

外部参考固定25 MHz。配置UART独立使用115200 bps、8N1，复用uart_rx_8n1和uart_tx_8n1，整数分频217。
新增wrapper引脚：pad_pll_cfg_rx_i、pad_pll_cfg_tx_o。
上电PLL关闭，内核保持复位，SHADOW/ACTIVE默认0x0220。必须发送APPLY才启动。
ACTIVE表示当前PLL引脚值，不表示PLL已启用或锁定。

## 报文

二进制请求4字节：OP、ADDR、DATA_H、DATA_L。OP=01写，02读。
响应4字节：STATUS、ADDR、DATA_H、DATA_L。读请求数据填0，写响应数据为0。
响应STATUS：00成功，01非法操作码，02寄存器错误，03控制器忙。
一问一答，收到完整回复后才发下一帧；发送应答期间不接收新请求，不保证回复违反此规则的请求。
半帧超过20 ms未收到下一有效字节会被丢弃。无CRC；写后读回再APPLY。
复用的RX没有停止位错误输出，因此01仅检测操作码，不代表完整串口帧校验。

## 寄存器

| 字节地址 | 名称 | 权限 |
|---|---|---|
| 00 | CFG_SHADOW | RW |
| 02 | COMMAND | WO，读0 |
| 04 | STATUS | RO |
| 06 | CFG_ACTIVE | RO |

16位整字访问，奇数/未定义地址非法。
CFG：[7:0] N、[8] SELECT、[10:9] OD、[11] BP、[15:12]保留0。
OD编码00/01/10/11分别除1/2/4/8。
COMMAND=0001 APPLY，0002 CLEAR_ERROR，其余非法。
STATUS：[0]BUSY、[1]DONE、[2]ERROR、[3]BP_ACTIVE、[4]PLL_EN、
[5]STARTUP_DONE、[6]CORE_RESET_RELEASED、[11:8]ERROR_CODE，其余0。
DONE在成功接受APPLY时清0，实际复位释放被参考域确认后置1。
错误为粘滞的最近一次错误；成功操作不清除。CLEAR_ERROR不改变DONE或运行配置。
同周期清除和启动超时出现时，超时优先。
STARTUP_DONE只表示等待时间完成，不是LOCK。

| 错误码 | 原因 |
|---|---|
| 0 | 无错误 |
| 1 | 非法地址或写只读寄存器 |
| 2 | APPLY时配置保留位非零 |
| 3 | N小于17或VCO不在500至1200 MHz |
| 4 | BP=0时输出超过400 MHz |
| 5 | 非法COMMAND |
| 6 | BUSY时写SHADOW或APPLY（协议响应03） |
| 7 | 复位释放确认超时 |

APPLY先校验，非法时保持当前内核/PLL不变；合法时快照配置再执行。
25 MHz下SELECT=0允许N=20..48；SELECT=1允许N=17..24。
BP=1也校验N/VCO，但不检查分频输出上限。
控制顺序：异步复位内核，保持4参考周期，关闭PLL，更新配置，稳定后EN=1，
计满375周期(15 us)，请求释放复位，等待实际两级复位同步器反馈。
反馈再经两级同步进入参考域；1024参考周期(40.96 us)仍未收到则错误7、
保持内核复位、结束BUSY、DONE=0。PLL保持使能，UART仍可用于清错及重新APPLY。
不做失锁检测，不自动旁路，不提供外部时钟MUX。

## 示例

每行发送后等4字节回复：

```text
01 00 02 20  写400 MHz配置（BP=0）
02 00 00 00  读回应为00 00 02 20
01 02 00 02  清除错误
01 02 00 01  APPLY，成功响应仅表示接受
02 04 00 00  查询状态；正常完成、无历史错误时数据0072
02 06 00 00  读ACTIVE
```

旁路配置为0A20；APPLY后正常状态007A，CKOUT1预期25 MHz。
业务UART固定分频40：400 MHz时10 Mbps，25 MHz时625 kbps，上位机自行匹配。
APPLY响应丢失时先查询STATUS/ACTIVE，勿盲目重发（再次APPLY会再次复位内核）。

## 工程与验证

综合增加pll_cfg_uart.sv、pll_cfg_regs.sv；先编译pbit_pkg.sv。
UART_RX/TX默认参数保留业务UART配置，配置实例独立覆盖25 MHz/115200。
PLL综合使用interface/PLL_TOP.v与lib/db，仿真使用verilog/PLL_TOP.v，两者不能同时编译。
需要为配置域及PLL输出分别建立时钟、约束复位反馈CDC，BP模式单独建立STA场景；
本次没有修改SDC，也未完成400 MHz物理时序签核。

tests_pll_cfg/run.ps1运行ModelSim回归，在系统临时目录生成work和日志。
串口测试复用真实UART、以独立时钟激励验证控制器；寄存器测试穷举4096种配置。
wrapper测试使用真实pbit_top、厂商PLL模型和IO功能桩，验证400 MHz启动。
BP控制和恢复由独立激励验证，不代表厂商BP模型或模拟电路已验证。
厂商模型已有BP调度竞争和重复EN时CKTST除零问题，本次未修改。
