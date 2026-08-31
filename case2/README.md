# 赛题二：2D 渲染加速引擎（RTL + XSIM 系统框架）

板卡无关 RTL 框架已经搭建，已完成的回归记录和最后一轮复验状态见下文。
`rtl/system/c2_renderer_system.sv` 串联 AXI4-Lite/direct-CSR 命令入口、FIFO/parser、
读写行级 burst 渲染器、带 owner 的双主存储仲裁、16-bit RGB565 到宽 AXI4 Full
的适配、vblank page flip/prefetch 和显示扫描路径。竞赛配置默认启用
`READ_BURST_ENABLE=1` 与 `WRITE_BURST_ENABLE=1`。

当前“完成”仅指 RTL、行为模型、AXI 协议适配和 XSIM/代理综合范围。RISC-V
Sapphire 软件与生成 IP、Efinix PLL、DDR3 控制器与 PHY、真实 CDC、HDMI PHY、
引脚约束、Efinity 时序收敛和板上稳定性仍未验证。

官方 8.22 更正版及三份补充资料的逐页概括、赛题二新旧差异和 RTL 缺口审计见
[`resource/官方补充资料概括与赛题二差异分析.md`](../resource/官方补充资料概括与赛题二差异分析.md)。
更正版最终目标已明确为 AXI4 + DDR3 + HDMI；现有 HyperRAM/VGA/APB 等表述只应
视为旧资料或可选内部适配背景，不能替代竞赛最终接口。

## 当前 RTL 基线

- 像素格式：RGB565；地址和 stride 以 byte 为单位，width/height 以 pixel 为单位。
- 描述符校验：每个实际使用的 stride 必须为偶数且不小于 `width×2`，parser 和
  engine 的直连入口都会在发出任何内存请求前拒绝非法 odd-stride；NOP 不检查
  未使用的 surface，Fill 不检查未使用的 source。
- 命令：NOP、Solid Fill、Block Copy、Alpha Blend、Color Key Copy。
- 默认命令总线：256-bit，字段见 `rtl/common/renderer_pkg.sv`。
- 控制面：`USE_AXI4LITE_CSR=1` 时由单 outstanding AXI4-Lite slave 接入现有 CSR；
  AW/W 可独立到达，非全字写返回 `SLVERR`。默认 direct-CSR 分支保留用于紧凑仿真。
- 读取：Copy 以行级 source burst 取数；Alpha/Color Key 依次读取 source 与
  background 行。读 descriptor 同时按 `MAX_READ_BEATS` 和 4 KiB 边界分段，
  并检查每段 `rsp_last`。同一双口行 RAM 先保存源行，再原位覆盖运算结果。
- 写回：先产生 descriptor，再传输独立 `wr_*` 数据，最后等待 `wr_rsp` 提交响应。
- Owner：从 descriptor 接受开始保持到 `wr_rsp` 被接受，可直接映射 AXI B 或外存
  控制器 commit/error。
- 行分段：同时受 `MAX_WRITE_BEATS` 和默认 4 KiB 边界限制，descriptor 不跨界。
- 数据面：`USE_EXT_MEM_IP=1` 时由 `c2_mem_to_axi4_adapter` 把连续 16-bit beat
  聚合为参数化宽 AXI4 Full beat（默认 128 bit），首尾 byte lane 用 `WSTRB`
  屏蔽，并把 AXI B/R 错误映射回抽象完成响应。AW 和 W 独立推进，WVALID 不等待
  AWREADY；只有 AW 与最终 W 均握手后才进入 B 响应阶段。
- 显示：在 vblank 提交 page，下一拍捕获新 page 并 prefetch；复位后第一帧安全
  黑屏，后续 active frame 只在已有预取数据时输出。
- 固定光栅：真实 PHY 在 active video 期间不得拉低 `pixel_ready`。

## 目录

- `rtl/common`：公共常量、命令格式和接口说明。
- `rtl/bus`：AXI4-Lite→CSR 与抽象存储→AXI4 Full 适配器。
- `rtl/cmd`：命令 FIFO、解析和描述符校验。
- `rtl/mem`：地址/burst、owner 仲裁、命令存储引擎和仿真内存模型。
- `rtl/ops`：Fill、Copy、Alpha、Color Key 像素算子。
- `rtl/video`：视频时序、vblank page flip 和 framebuffer burst reader。
- `rtl/fifo`：同步 FIFO、line FIFO 和 skid/握手模块。
- `rtl/system`：CSR bridge、显示路径和板卡无关 assembly top。
- `rtl/ip`：时钟/CDC、视频 PHY、Sapphire 及保留兼容外存边界的命名黑盒。
- `tb`：模块级、协议级和系统级自检 testbench。
- `synth_proxy`：面向 Artix-7 的无约束 RAM/资源代理综合脚本与报告；不替代 Efinity。

## 存储和显示关键契约

`req_len` 采用 beats-minus-one，地址是 byte address。读 descriptor 返回恰好
`req_len+1` 个有序 beat，且仅最后一拍置 `rsp_last`。写 descriptor 被接受后，
恰好传输 `req_len+1` 个 write-data beat；最后一拍置 `wr_last`。数据阶段结束不等于
写完成，memory adapter 必须随后返回一个 `wr_rsp`。真实 Efinix adapter 应把该
响应映射到 AXI B 或 DDR3 控制器的提交/错误结果。当前
`c2_mem_to_axi4_adapter` 已完成这层板卡无关映射，但结束于 AXI4 master pins；
DDR3 training、刷新、PHY 和物理引脚仍由 Efinity 生成 IP 承担。

Page request 与 renderer completion 没有硬件自动绑定。软件应渲染 inactive page，
等待相应命令成功完成，再请求翻页。Page controller 在 vblank commit；显示路径在
下一拍看到新的 active page 并利用剩余垂直消隐预取。第一帧没有此前的预取窗口，
因此按设计保持黑屏，而不是输出半帧。

## 仿真入口和最新结果

2026-08-31 完整 `Run-NewguideRegression` 已通过 10 项自检仿真与 11 项展开。
最终记录目录为 `tb/xsim_newguide_signoff_20260831`，22 个阶段状态文件（含一次
统一编译）均确认 `worker_in_job=false`、`state=completed`、`returncode=0`。
以下同时保留既有模块专项记录；本轮执行集合和逐项日志见 `verification.md`。

- Owner 专项：
  `TB_C2_MEM_ARBITER_OWNER_PASS writes=6 reads=1 rsp=3 recovered=1`
- 行写/legacy-read 专项：
  `TB_RENDER_CMD_MEM_ENGINE_BURST_PASS req=21 reads=8 writes=13 pixels=20 beats=20`
- 行读专项（含最大长度、4 KiB 分段、读背压、错误 `rsp_last`）：
  `TB_RENDER_CMD_MEM_ENGINE_READ_BURST_PASS reads=11 writes=8 pixels=26 errors=1`
  （1 个错误为测试主动注入）
- 读写行级 burst + owner + memory 集成：
  `TB_C2_CMD_MEM_ENGINE_BURST_PASS req=18 reads=8 writes=10 wr_rsp=10 pixels=15`
- AXI4-Lite CSR：
  `TB_C2_AXI4LITE_CSR_ADAPTER_PASS csr=5 writes=3 reads=2`
- 16→64/128-bit AXI4 Full 适配专项分别通过：
  `TB_C2_MEM_TO_AXI4_ADAPTER_PASS width=64/128 aw=6 ar=14 r=25 protocol=5 axi=5`
  （两个数据宽度分别运行；覆盖 AW 时序、RID、提前/延后 RLAST、4 KiB 拒绝，
  错误计数为测试主动注入）
- RGB565 stride 对齐入口专项：
  `TB_C2_STRIDE_ALIGNMENT_PASS parser_rejected=7 direct_rejected=7 allowed=6 requests=12 reads=4 writes=8 pixels=32 errors=7`
  （7 个错误为主动构造的非法 descriptor）
- 竞赛接口 system shell：
  `TB_C2_RENDERER_SYSTEM_AXI_SHELL_PASS submit=1 done=1`
- Legacy 兼容路径：
  `tb_cmd_mem PASS: req=25 read=11 write=14 pixels=15`
- 系统端到端：
  `TB_C2_RENDERER_SYSTEM_PASS video=16 page1=8 done=1 active_page=1 underflow=0`
- 系统可选择的 clock/video/CDC 黑盒和外部 AXI memory 分支：
  `tb_c2_renderer_system_ip_stub` 仅 `xvlog/xelab PASS`，不运行无行为黑盒 xsim。

完整覆盖范围见 `verification.md`。`xvlog`、`xelab`、`xsim` 分阶段执行并不自动
保证脱离 Windows Job；本机实测普通 breakaway worker 仍可能处于 Job 中。
当前调用器为
[`scripts/Start-DetachedEdaTool.ps1`](scripts/Start-DetachedEdaTool.ps1)，它经 WMI
`Win32_Process` 服务隐藏创建 `run_detached_tool.py` 的 Python worker。worker
检查 `worker_in_job=false` 后才启动 Vivado，并把状态和日志持久化；检查失败则
拒绝启动工具。应按这一检查结果确认进程隔离，不能仅凭“三个独立命令”判断。

可复用入口为 [`scripts/Run-NewguideRegression.ps1`](scripts/Run-NewguideRegression.ps1)。
在仓库根目录运行以下命令可新建带时间戳的回归目录；可通过 `-PythonPath`、
`-VivadoBin`、`-RunName` 覆盖本机路径，已有运行目录不会被覆盖。

```powershell
.\case2\scripts\Run-NewguideRegression.ps1
```

## 资源和带宽提醒

默认渲染行缓存为 `4096×16=65,536 bit`，若成功推断为 10-Kbit embedded memory，
约需 7 个块；默认显示 FIFO 为 `1024×17=17,408 bit`，约需 2 个块。实际 RAM
块数必须以 Efinity 报告为准。最新 Vivado/Artix-7 无约束代理综合结果为：

- 最新 system top（选择 AXI4-Lite、AXI4 Full、clock/video/CDC IP 分支）：3,680 LUT、
  3,840 FF、2×RAMB36E1、1×RAMB18E1、0 DSP；其中 AXI4-Lite adapter 为
  115 LUT/100 FF，AXI4 Full adapter 为 459 LUT/439 FF；
- 最终 `render_cmd_mem_engine` 独立综合为 2,265 LUT、647 FF、2×RAMB36E1、
  0 DSP，已包含 odd-stride 修正并通过脱离 Job 的顺序重跑。
  同一行 RAM 被 source/result 复用，没有增加第二个全行缓存；
- 旧的 2,690 LUT/3,108 FF 数值属于增加读 burst 和两层 AXI 适配之前的历史代理
  基线；中间版本 3,602 LUT/3,830 FF 也已由上述最终 system 结果替代。

这些数字不含任何厂商黑盒内部资源，不能换算成 Ti60 最终占用或 Fmax，详见
`synth_proxy` 报告。

并行 scanout+render 的理论带宽下限为：

- 640×480@60：scanout/Copy/Alpha 约
  36.864/110.592/147.456 MB/s；
- 1280×720@60：scanout/Copy/Alpha 约
  110.592/331.776/442.368 MB/s。

这些数字未计刷新、读写切换、仲裁、CDC 和控制器效率，不代表实测性能。详细预算
见 `resource_budget.md`。

## Efinity 和板卡阶段

已安装并验证 Efinity v2026.1.132（含补丁）后，新增了 [Efinity/Sapphire/Ti60F225 GUI 交接清单](efinity_smoke/GUI_HANDOFF.md)。其中记录了已通过的 Ti60F225 CLI 结构映射、Sapphire/DDR3 IP Manager 配置建议、必须依据竞赛板原理图确认的参数，以及 RISC-V IDE 的软件交付物。当前仍不能把黑盒分支的 map 结果当成真实 DDR3/视频 PHY 的最终资源或板级通过。

本轮最终 AXI 修正版的 Ti60F225 Efinity map 已通过，报告为
[`case2_rtl_probe_axi_final.map.rpt`](efinity_smoke/outflow_sv_axi_final/case2_rtl_probe_axi_final.map.rpt)：
2,384 LUT4、2,134 FF、804 ADD、0 RAM、0 DSP。该 probe 的 AXI ready/response
输入绑 0，且未启用 AXI4-Lite，导致大量数据路径被裁剪；因此这里只证明当前 RTL
可经 Efinity 解析/结构映射，不能据 0 RAM/0 DSP 或这些逻辑数字估算完整系统占用。

1. 依据竞赛板 BOM/原理图确认 MT41J128M16JT-125 DDR3 的引脚、时钟、数据宽度和
   Efinity controller 参数；
2. 生成 PLL/复位、DDR3 controller/PHY、真实 memory/page CDC 和 HDMI PHY；
3. 按生成 DDR3 IP 的实际 AXI 数据/ID 宽度设置 `AXI_DATA_W/AXI_ID_W`，接通
   `c2_mem_to_axi4_adapter` 并核对 init/training 状态；
4. 接入 Sapphire CSR，加入 pin/clock/IO 约束并完成 Efinity timing closure；
5. 进行外存 training、固定图案、page flip、欠载、scanout+render 吞吐及长时间
   ILA/UART 板级调试。

在这些步骤完成之前，不应声称资源、Fmax、外存效率或真实视频输出已经验证。
