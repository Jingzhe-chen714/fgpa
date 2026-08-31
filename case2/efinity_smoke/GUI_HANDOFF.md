# Case 2：Efinity / Sapphire / Ti60F225 交接清单

本文把当前可以由脚本自动完成的部分和必须由队员在 Efinity GUI/IP Manager、原理图及板卡上确认的部分分开。以 8.22 更正版赛题二为准，DDR3 帧缓存和 HDMI 640x480@60 输出是必需项，不再按“DDR/SDRAM、VGA/HDMI 均可”的旧范围选配。目标器件按竞赛板图片暂记为 `Ti60F225I3`；外存按图片暂记为 `MT41J128M16JT-125` DDR3 x16。具体参数仍需原理图确认，不能直接把官方 Ti60F225 开发套件的 HyperRAM 示例当成竞赛板配置。

## 当前 RTL 状态与验证边界

- `D:\ELS\Efinity\2026.1` 的 Efinity CLI 可用，最小 Ti60F225 counter 设计已通过 `--flow map`。
- 当前 `c2_renderer_system` 已接入两个板卡无关的真实适配器，不再把控制总线/内存转换全部留作空黑盒：

  - `USE_AXI4LITE_CSR=1`：启用 `c2_axi4lite_csr_adapter`，通过 `s_axi_csr_*` 接收 32-bit AXI4-Lite CSR 访问；当前只支持 `WSTRB=4'hf` 全字写，部分字节写返回 `SLVERR`，不改寄存器。
  - `USE_EXT_MEM_IP=1`：启用 `c2_mem_to_axi4_adapter`，通过 `m_axi_*` 输出 AXI4 Full master；RGB565 16-bit beat 聚合/拆分为参数化宽拍，默认 `AXI_DATA_W=128`、`AXI_ID_W=4`，实际值必须跟生成 IP 一致。
  - 渲染器默认启用行级读/写 burst：源和背景读取、写回均按最大长度及 4 KiB 分段；Alpha/Color Key 复用同一同步 line RAM 原位形成结果。显示侧已使用 burst reader + line FIFO。
- `c2_ext_mem_adapter_blackbox` 和 `c2_sapphire_csr_blackbox` 只保留为 legacy anchor，不再由当前 AXI 配置实例化。新的适配器并不包含 Sapphire CPU、DDR3 controller/PHY、HDMI TX/PHY 或板级引脚。
- 此前结构版本曾以 Efinity SystemVerilog flist 方式通过 Ti60F225 映射探针：

  - 小参数分支 `outflow_sv_small`：PASS；
  - 默认缓存尺寸分支 `outflow_sv_full2`：PASS。
- 上述旧探针的外存、视频 PHY、时钟/复位和 CDC 走命名 blackbox，只表示该版语法/连线/可综合性检查通过。旧报告不能直接证明本次新增 AXI/read-burst 路径或 DDR3/HDMI 板级功能通过；新版本以新生成的日志为准。
- 默认行为内存模型 `MEM_BYTES=1228800` 不应送入 Efinity map；它是仿真数组，曾导致主机内存耗尽。板级工程应选择已有 AXI4 适配器，再连接生成的 DDR3 controller/PHY。
- 功能验证分为行为内存系统回归、独立 AXI4-Lite/AXI4 adapter 回归、行级读 burst 回归，以及 AXI4-Lite NOP 系统闭环。NOP 系统测试故意保持 DDR3 未初始化，只验证控制闭环/初始化门控，不代表已完成真实 DDR3 帧缓存访问。剩余时钟/CDC/视频黑盒只做结构检查。
- 最终回归目录 `case2/tb/xsim_newguide_signoff_20260831` 已完成全部 11 项展开与 10 项功能仿真，均 PASS，覆盖奇数 stride 入口拒绝及 AXI 64/128-bit 配置；IP stub 只展开、不做功能仿真。可使用 `case2/scripts/Run-NewguideRegression.ps1` 重跑。上述结果仍不包含真实 DDR3/HDMI 厂商 IP 或板级功能验证。
- 最新 Vivado system proxy 综合为 `3680 LUT`、`3840 FF`、`2 RAMB36 + 1 RAMB18`、`0 DSP`；缓存已映射为块 RAM。它是所选系统/接口 stub 的资源检查，不包含真实 DDR3/HDMI/CPU IP，也不是 Ti60 资源或板级时序结论。
- 旧 `outflow_sv_full2` 的黑盒裁剪后报告约为 1269 FF、1087 LUT；不含黑盒内部、被裁剪路径和实际 RAM/PHY 资源，也未覆盖新增总线层，不能作为 Ti60 最终资源预算。真实资源/时序需要生成 IP 后重新综合、P&R、STA。
- 本次最终探针 `outflow_sv_axi_final/case2_rtl_probe_axi_final.map.rpt` 已完成 Efinity map，结果 PASS：`EFX_LUT4=2384`、`FF=2134`、`ADD=804`、RAM/DSP 均为 0。该探针仍有 stub/输入绑 0 引起的逻辑裁剪，且未启用 AXI4-Lite 控制分支；0 RAM/DSP 不能解释为完整系统不需要这些资源。这是新增 RTL 的结构映射证据，不是完整 AXI 控制面、DDR3/HDMI IP 或板级 P&R/时序验证结果。

## 必须在 GUI 中确认的操作

### 1. 生成 Sapphire RV32 SoC

1. 启动 `D:\ELS\Efinity\2026.1\bin\setup.bat --run`。
2. 打开 IP Catalog（Tools → Open IP Catalog）。选择普通可配置的 **Sapphire RV32 SoC**，不要选只支持更高端 Titanium 器件的 Sapphire High-Performance；器件选择 `Ti60F225I3`。
3. 模块名建议先用 `c2_sapphire`。第一版采用单核 Bare-Metal、保留 UART0；指令扩展、片上 RAM 和缓存按生成器实际选项及软件需要选择。重点查看并导出当前版本的用户 AXI4 接口，确认 CPU 能作为主机访问渲染器 CSR 和 DDR3。不要再以 APB-only 作为默认方案：当前渲染器已有 AXI4-Lite slave，若 Sapphire 导出 AXI4 Full master，应通过地址译码/interconnect 和相应协议桥接到该窗口，而不是直接省略 Full AXI 的附加信号。若界面没有匹配选项，请提供接口页截图后再决定桥接方式。
4. 在 Deliverables 中勾选生成 RTL、testbench、Ti60F225 开发板示例（如果当前器件/版本提供）、embedded software/BSP，然后 Generate。不要手工把生成的 `<module>.v` 再添加一次，IP Manager 会自动加入工程。
5. 先保留自动地址分配；生成后以 `soc.h`、链接脚本和导出的接口文件为准。当前 renderer CSR 使用 12-bit 窗口内偏移，外层地址译码必须分配独立基地址；软件用对齐的 32-bit 读写访问，不能自行猜 CPU 地址。
6. 赛题要求屏幕上比较 CPU 软件与硬件加速的 FPS，因此 CPU 访问帧缓存的路径必须纳入系统方案，不能当作永远不需要的可选项。Sapphire CPU 与当前加速器 `m_axi_*` 应通过系统级 AXI interconnect 共享 DDR3；加速器内部 owner arbiter 只仲裁 renderer/scanout，不仲裁 CPU。若启用 cache，需明确帧缓存映射属性、flush/invalidate 和内存屏障。

### 2. 生成 DDR3 控制器和物理接口

1. 在 IP Catalog 中查找 Titanium DDR/DDR3 Soft Controller（或当前版本显示的 DDR3 Controller V2）以及对应 PHY/校准模块。官方 Sapphire RV32 数据手册对 Titanium 的 SoC 外部 DDR 描述偏向 LPDDR4/LPDDR4X 硬控制器；竞赛板若确实使用 DDR3，应把 DDR3 Soft Controller 作为独立 IP，再通过 AXI4/native adapter 接入渲染器和/或 Sapphire，而不是假定 Sapphire 默认 DDR 端口可以直接接 DDR3。模块参数必须依据竞赛板原理图和 pinout：`MT41J128M16JT-125`、x16、800 Mbps 数据率（通常对应 400 MHz DDR 时钟），行/列/Bank、DQS、CK、ODT、复位和电压均不能凭图片猜。
2. 先生成 controller 的 example/testbench；确认 `init_done`/calibration-done、用户时钟、AXI 数据/ID 宽度和写响应语义。当前 `c2_mem_to_axi4_adapter` 已完成 16-bit RGB565 到宽 AXI4 的聚合/拆分，使用对齐全宽 INCR burst、单 outstanding、ID 0；将系统 `AXI_DATA_W/AXI_ID_W` 设置为生成端口所需宽度，并连接所有 AXI 响应。它将 AXI B 转为“写完成/错误响应”，不能在最后一个 W beat 时提前替代 B。
3. 将 calibration 状态接到系统 `ext_mem_init_done/error`。成功初始化前 RTL 会阻止新内存请求；不要把这两个输入固定成“成功”来绕开 training。确认 DDR3 AXI user clock 与 `clk_sys` 一致，否则需要外层 AXI CDC。先运行厂商固定模式读写例程，再测现有 adapter 的字节顺序、部分首尾 `WSTRB`、4 KiB 边界及错误返回。
4. 若 IP Catalog 没有与该竞赛板匹配的 DDR3 controller，停止继续配置并提供 IP Catalog 截图、器件包名和板卡原理图；不要用 HyperRAM 参数替代 DDR3。若生成 IP 只有 native 用户接口，则仍需额外 native bridge；旧 `c2_ext_mem_adapter_blackbox` 只是空锚点，不是已完成实现。

### 3. 时钟、复位、CDC 和视频 PHY

1. 以板上实际使用的 50 MHz（或原理图标注的其他输入）生成 system、640x480@60 所需 pixel、memory/PHY clocks。默认 800x525 总计数只规定 raster，不会自动生成正确像素时钟；PLL 倍频、相位和复位释放仍由 IP/约束决定，不要先硬编码 148.5 MHz。
2. 连接 Sapphire 的异步复位、SoC reset outputs、DDR 初始化完成和 PLL lock。所有未使用的 ready/valid 输入按生成模板绑定到确定值，否则 SoC 可能保持在 reset。
3. 本赛题已明确要求 HDMI，因此必须生成并接入板卡匹配的 HDMI TX/PHY，而不是只保留 RGB 输出或换成 MIPI/VGA。当前 `c2_video_phy_blackbox` 还是并行 RGB565/时序接口锚点，板级 wrapper 需要按 IP 格式扩展像素位宽、连接实际 HDMI 引脚并对齐 `de/hsync/vsync` 延迟。`pixel_ready` 在 active video 期间不能被 PHY 拉低。
4. 当 system/pixel 时钟不同，实现 `c2_page_cdc_blackbox` 的页面请求/状态握手及 `c2_mem_cdc_blackbox` 的显示只读 descriptor/response 通道；后者不是通用写通道 CDC，也不能代替 DDR3/CPU 总线所需的 AXI CDC。系统在 `vblank_start` 提交页面，下一拍 `prefetch_start` 捕获新页面并预取，不能把它改回有效显示第一拍才换页而不复查时序。

### 4. 导出并交回给 RTL 集成的文件

请保留并提供生成工程目录或至少以下文件路径/截图：

- Sapphire：`<module>.v`、`*_define.vh`、`settings.json`、`embedded_sw/<module>/bsp`、`soc.h`、链接脚本、生成的 testbench/top；
- DDR3：`*_define.vh`、`*_tmpl.v`/`*_tmpl.vhd`、`*.v`、`settings.json`、校准/PHY 文件、AXI 端口及 user-clock 说明；
- HDMI/时钟/互联：TX/PHY 生成目录、模板、像素格式和时钟配置、AXI interconnect/协议桥/CDC 模板；
- 工程约束：`.peri.xml`、`.interface.csv`、`.pinout.csv`、`.isf`、`.sdc`/`.pt.sdc`；
- 若生成开发板示例：`*_devkit` 目录和 IP Manager 版本显示。

拿到这些文件后，已有 AXI4-Lite/AXI4 适配器的具体端口接线、必要的 interconnect/CDC wrapper、软件寄存器驱动和 Efinity CLI 的 map/pnr/sta 可以继续脚本化。需要队员在 GUI/原理图中确认的仍包括实际 IP 参数、引脚和时钟；首次下载、training/HDMI 观察与板级测量需要真实板卡配合，不能由结构编译结果替代。

## RISC-V IDE 的使用边界

生成 BSP 后，从 Efinity GUI 启动 RISC-V Embedded Software IDE，或先运行 `D:\ELS\efinity-riscv-ide-2026.1\setup.bat`（需要 FreeRTOS 时按提示输入源码目录），再启动 `D:\ELS\efinity-riscv-ide-2026.1\Efinity-RISCV-IDE\efinity-riscv-ide.exe`。第一阶段使用 Bare-Metal 工程：导入 BSP、编译生成 `.elf`/`.bin`，软件只通过生成的 `soc.h` 访问 CSR、UART 和中断。OpenOCD 调试、Flash 下载地址和 linker script 必须以生成 BSP/板卡示例为准；官方 Ti60 套件资料中的 `0x00380000` 是该套件示例的 SPI Active 地址，不能直接套到竞赛板。

RISC-V 驱动仍待编写/联调。至少需要完成：写入 8 个命令字并 submit、等待完成/错误、只向非显示页面渲染、完成后再请求换页、资源加载与缓存一致性，以及同场景的 CPU-only/硬件加速 FPS 统计并显示在 HDMI 画面上。当前 RTL 适配器和 NOP 测试不是这些软件工作的完成证明。Custom Instruction 可作为之后的可选优化，不能替代要求的 AXI4 数据面。

## 工具选择

- Vivado XSIM：当前 SystemVerilog 行级读/写 burst、AXI4-Lite/AXI4 adapter、owner 写响应、显示 prefetch 和系统回归的主参考。`xvlog`、`xelab`、`xsim` 分阶段执行便于隔离日志，但“分开启动”不等于脱离 Windows Job。本机普通 breakaway 方式已实测仍返回 `in_job=true`，因而拒绝继续启动。使用 `case2/scripts/Start-DetachedEdaTool.ps1` 经本机 `Win32_Process` WMI 服务隐藏创建 `case2/scripts/run_detached_tool.py` worker，并确认实际 `worker_in_job=false` 后再启动 Vivado；若仍处于 Job 内，不应把长时间仿真启动为当前会话的附属进程。
- Efinity map/pnr/sta：Ti60 器件的真实综合、布局布线、时序和资源报告，必须在生成 IP/约束之后运行。
- Icarus + GTKWave：适合小型纯 Verilog 模块和 VCD 查看。Efinity 文档明确提示 IVerilog 不支持完整 SystemVerilog，且不能解密受保护 IP；不能用它替代 XSIM/厂商支持的加密 IP 仿真。

## 当前结论

板卡无关的行级 burst 渲染、AXI4-Lite CSR 和 AXI4 Full 内存转换已进入当前 RTL，不必再把这些适配层从头设计。仍未完成的是生成并连接 Sapphire、DDR3 controller/PHY、必需 HDMI TX/PHY、PLL/CDC、RISC-V 驱动、真实板级 P&R/STA 与实测。没有原理图、pinout 和 IP Manager 生成结果时，不能安全决定 training、PHY 电气配置和引脚，也不能保证首次板上启动。下一步请按本清单生成 Sapphire + DDR3 + HDMI/时钟的最小示例，再交回导出目录进行端口集成与完整验证。
