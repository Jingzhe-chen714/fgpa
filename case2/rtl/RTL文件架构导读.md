# Case2 RTL 文件架构导读

本文面向第一次在 Efinity GUI 中搭建系统的成员，说明 `case2/rtl` 下各个 `.sv` 文件的职责、层次关系、仿真模型边界和集成顺序。当前代码是“板卡无关的二维渲染协处理器 + 可替换的板级接口”，不是已经完成的 Ti60 顶层工程。

## 1. 先记住整体数据流

```text
RISC-V/Sapphire 或仿真CSR
        │ AXI4-Lite（或 direct CSR）
        ▼
c2_axi4lite_csr_adapter → c2_csr_cmd_bridge → render_cmd_fifo
                                                    │
                                                    ▼
                                           render_cmd_parser
                                                    │ 256-bit descriptor
                                                    ▼
                                           render_cmd_mem_engine
                                      ┌─────────────┴─────────────┐
                                      │                           │
                              行级读/写请求                    完成/错误
                                      │                           │
                              owner_mem_arbiter                  CSR状态
                                      │
                    ┌─────────────────┴─────────────────┐
                    │                                   │
             render（client 0）                    display（client 1）
                    │                                   │
              16-bit像素流                        rect reader→line FIFO
                    └─────────────────┬─────────────────┘
                                      ▼
                         c2_mem_to_axi4_adapter → DDR3 IP

video_timing_gen → page_flip_ctrl → display timing/data → HDMI PHY IP
```

系统顶层是 `system/c2_renderer_system.sv`。它把控制、命令、渲染、显示和存储路径连在一起；`USE_*` 参数决定使用仿真模型还是黑盒/IP边界。默认仿真路径使用同一时钟、行为内存和并行视频信号，便于 XSIM；真实板级路径需要另行接入 Sapphire、DDR3、PLL/复位、CDC 和 HDMI。

## 2. 系统层：GUI 中首先理解的三个文件

| 文件 | 模块 | 作用 | 当前状态 |
|---|---|---|---|
| `system/c2_renderer_system.sv` | `c2_renderer_system` | 唯一的 assembly point；实例化控制、FIFO、parser、engine、显示、仲裁器和两种存储后端 | 可作为 RTL 集成顶层，但还不是 Ti60 物理顶层 |
| `system/c2_csr_cmd_bridge.sv` | `c2_csr_cmd_bridge` | 将 32 位 CSR 读写转换为命令字暂存、提交、状态/计数器读出 | 已实现，支持 direct-CSR 仿真入口 |
| `system/c2_display_path.sv` | `c2_display_path` | 将显示页基址、矩形 burst reader、line FIFO 和 RGB/时序信号连接起来 | 已实现板卡无关显示数据路径 |

在 GUI 中应先把 `c2_renderer_system` 作为待分析顶层，确认参数 `READ_BURST_ENABLE=1`、`WRITE_BURST_ENABLE=1`，再沿实例层次展开。不要把 `tb_*.sv`、行为 memory model 或 `ip/*_blackbox.sv` 误设为综合顶层。

## 3. 控制命令路径

| 文件 | 功能 | 与谁连接 |
|---|---|---|
| `cmd/render_cmd_fifo.sv` | 有界 ready/valid 命令 FIFO；满时不覆盖已接收命令，并产生背压诊断 | bridge → parser |
| `cmd/render_cmd_parser.sv` | 解码 256 位命令，分配序号，检查 op、RGB565 几何、stride 对齐；非法命令只计数不送 engine | FIFO → engine |
| `common/renderer_pkg.sv` | 命令字段、操作码、错误码和接口常量的 package 定义 | parser、engine、CSR 等共同引用 |
| `common/renderer_interfaces.md` | 抽象 memory/CSR/渲染接口的文字约定 | 设计参考，不参与编译 |

命令描述符的低位字段依次包含 `op`、`flags`、`pixel_fmt`、源/目的地址、宽高、源/目的 stride、颜色、alpha 和 color key。软件写入 `CMD_WORD0..7` 后写 `CMD_SUBMIT`，bridge 才将八个字的快照送入 FIFO。parser 和 engine 都会检查关键地址/stride 条件，因此绕过 parser 的单元测试也不会静默执行奇数 RGB565 stride。

## 4. 像素算子层：独立、可单测、通常不直接挂总线

| 文件 | 模块 | 功能 |
|---|---|---|
| `ops/alpha_blend_pixel.sv` | `alpha_blend_pixel`、RGB565/RGB888 别名 | 单像素组合 Alpha；RGB565 按原生 R5/G6/B5 通道、`(numerator+128)/255` 计算并饱和 |
| `ops/alpha_blend.sv` | `alpha_blend`、`alpha_blend_stream` | 带一拍 ready/valid 弹性寄存器的 Alpha 流接口 |
| `ops/color_key_pixel.sv` | `color_key_pixel`、RGB565 别名 | color key 命中输出背景，否则输出源像素 |
| `ops/color_key.sv` | `color_key`、`color_key_stream` | 带背压的 color-key 流接口，并输出 `key_hit` |
| `ops/pixel_pack.sv` | pack/unpack、RGB565/RGB888 别名 | 像素与通道、字节序之间的转换；RGB565 低地址字节为低 8 位 |
| `ops/tb_pixel_ops.sv` | 测试平台 | 只验证像素算子，不应加入综合源 |

当前 `render_cmd_mem_engine.sv` 内部直接调用等价的 RGB565 运算函数，因而 `ops` 目录更多用于算法基线和独立回归；不要假定把 `alpha_blend_stream` 接上 engine 就自动形成流水线或 DSP 实现。

## 5. 渲染与存储层：协处理器的核心

### 5.1 渲染控制器

`mem/render_cmd_mem_engine.sv` 是核心状态机。它接收 parser 的一个 descriptor，按 Fill、Copy、Alpha、Color Key 分别执行：源行读取、必要时背景行读取、同步 line RAM 计算/覆盖、分段写回，并在每个写 descriptor 收到 `wr_rsp` 后才推进。默认内部像素宽度为 16 位；行宽可超过一次 burst，但会按最大 beat 数和 4 KiB 边界拆分。Fill 不需要源行缓存，是容量上的例外。

### 5.2 burst 基础模块

| 文件 | 作用 | 备注 |
|---|---|---|
| `mem/c2_burst_planner.sv` | 将一行转换成对齐、长度受限、不可跨 4 KiB 的 descriptor | 只产生请求，不处理返回数据 |
| `mem/c2_burst_read_stream.sv` | 将一次读 descriptor 转成连续 response/pixel 流 | 检查提前或缺失 `rsp_last`，带一拍 holding register |
| `mem/c2_burst_write_stream.sv` | 接受一个写 descriptor，转发独立的 data/strb/last 流 | 写响应在上层由 owner/adapter 完成 |
| `mem/c2_rect_burst_reader.sv` | planner + read stream 的组合 | 输出像素坐标、行尾和帧尾标记；显示路径使用 |
| `mem/c2_mem_arbiter_2m_owner.sv` | render 与 display 两个 master 的带 owner 仲裁器 | 读保持到 `rsp_last`；写保持到最后数据和 `wr_rsp` |
| `mem/c2_mem_arbiter_2m.sv` | 旧版单 beat 仲裁器 | 仅供 legacy 测试，不是当前 burst 系统主路径 |

owner 仲裁器是连接渲染器/显示器与外部存储适配器的唯一共享边界。不要把两个 master 直接并接到 DDR3 slave；CPU 若也访问 DDR3，还要在系统级增加 AXI interconnect 或协议桥。

### 5.3 渲染所需的行为内存与仿真模型

| 文件 | 用途 | 是否综合到真实板 |
|---|---|---|
| `mem/render_mem_model.sv` | 旧式单 beat 行为 RAM，支持 scoreboard | 否，XSIM only |
| `mem/render_burst_mem_model.sv` | 多 beat 读响应模型 | 否，XSIM only |
| `mem/render_write_burst_mem_model.sv` | 独立写数据流和延迟写响应模型 | 否，XSIM only |
| `mem/render_owner_mem_model.sv` | owner 集成测试的读/写/写完成模型 | 否，`USE_EXT_MEM_IP=0` 仿真后端 |

行为模型用于制造 backpressure、延迟和错误，不能当作 DDR3 时序或吞吐证明。真实路径是 owner → `c2_mem_to_axi4_adapter` → 顶层 `m_axi_*` → Efinity 生成的 DDR3 controller。

## 6. FIFO 与弹性缓冲

| 文件 | 功能 |
|---|---|
| `fifo/c2_sync_fifo.sv` | 同时钟 ready/valid FIFO，支持同周期 pop+push |
| `fifo/c2_skid_buffer.sv` | 一项深度的弹性缓冲，吸收下游短暂停顿 |
| `fifo/c2_line_fifo.sv` | 显示行 FIFO，带行尾标记、同步 RAM 读和 flush |

这些模块只解决同一时钟域的握手。RISC-V、DDR3 用户时钟、渲染时钟和 HDMI 像素时钟不同时，不能直接跨域连接；需要真正的异步 FIFO、握手 CDC 或厂商 CDC IP。

## 7. 总线适配层

| 文件 | 接口方向 | 功能 |
|---|---|---|
| `bus/c2_axi4lite_csr_adapter.sv` | AXI4-Lite slave → CSR handshake | AW/W 可乱序到达；单 outstanding；只接受完整 32 位写；B/R 在背压下保持 |
| `bus/c2_mem_to_axi4_adapter.sv` | 抽象 16 位 memory → AXI4 Full master | 默认 128 位宽拍聚合/拆包；保护首尾 WSTRB；ID 0、单 outstanding；把 AXI B/R 错误转换为抽象错误 |

AXI4-Lite 适配器只提供渲染器的 CSR 从端，不包含 Sapphire CPU、地址译码和 interconnect。AXI Full 适配器只提供 AXI 信号，不包含 DDR3 training、refresh、PHY、引脚或物理时序。实际集成时应从 Efinity 生成 IP 的 AXI 数据宽度、ID 宽度和用户时钟反向设置顶层参数，而不是直接沿用默认值。

## 8. 显示与换页层

| 文件 | 功能 | 当前系统是否使用 |
|---|---|---|
| `video/c2_video_timing_gen.sv` | 参数化光栅计数器；默认 640×480 时序，产生 DE/HS/VS、vblank 和 prefetch 边界 | 使用 |
| `video/c2_page_flip_ctrl.sv` | 单 pending 页请求，在安全提交点更新 active page 并产生 ack | 使用 |
| `video/c2_framebuffer_reader.sv` | 旧版单 beat 线性帧缓存读取器 | 保留用于隔离测试，当前 system 使用 burst reader |
| `system/c2_display_path.sv` | page/timing + `c2_rect_burst_reader` + `c2_line_fifo` + RGB 输出的组合 | 使用 |

当前 page commit 点是垂直消隐开始，下一拍 capture 新页并 flush 旧 FIFO，再启动预取。第一帧复位后为黑屏。活动页变化本身不代表旧页读请求已排空；实际软件交接仍需 CDC、完成标志和页面所有权协议。

## 9. IP/黑盒边界

| 文件 | 预留内容 | GUI 集成动作 |
|---|---|---|
| `ip/c2_clock_reset_blackbox.sv` | 系统/像素时钟、同步复位、PLL lock | 用实际 PLL/clock-reset IP wrapper 替换或包裹 |
| `ip/c2_mem_cdc_blackbox.sv` | 显示只读 descriptor/response 跨时钟 | 根据系统/像素时钟关系使用异步 FIFO 或 CDC IP |
| `ip/c2_page_cdc_blackbox.sv` | page request/status 跨域 | 用握手同步器或小 FIFO 实现 |
| `ip/c2_video_phy_blackbox.sv` | RGB565/timing 到 HDMI TX/PHY | 连接生成的 HDMI wrapper、像素时钟和物理引脚 |
| `ip/c2_ext_mem_adapter_blackbox.sv` | 旧式 native memory 接口 | 当前顶层不选用，仅保留历史接口锚点 |
| `ip/c2_sapphire_csr_blackbox.sv` | 旧式非 AXI 控制锚点 | 当前 AXI 控制路径不实例化 |

`USE_AXI4LITE_CSR=1` 选择真实 AXI-Lite adapter；`USE_EXT_MEM_IP=1` 选择 AXI Full adapter；`USE_CLOCK_RESET_IP=1`、`USE_VIDEO_PHY_IP=1` 和 CDC 参数选择相应黑盒。选择参数不会自动生成厂商 IP，必须在 Efinity GUI 生成并核对端口。

## 10. 综合源、仿真源和排除项

### 建议的最小综合源（板无关代理）

`common/renderer_pkg.sv`、`bus/*.sv`、`cmd/render_cmd_fifo.sv`、`cmd/render_cmd_parser.sv`、`fifo/c2_sync_fifo.sv`、`fifo/c2_skid_buffer.sv`、`fifo/c2_line_fifo.sv`、`mem/c2_*.sv`、`mem/render_cmd_mem_engine.sv`、`system/*.sv`、`video/c2_*.sv`，以及所需的 `ip/*_blackbox.sv` 声明。

若使用真实 Efinity IP，应以生成 wrapper 替换同名 blackbox 实例，并将真实 wrapper、约束和 IP 生成文件加入工程。`ops/*.sv` 只有在顶层或 engine 明确实例化时才需要加入；当前 engine 的组合函数已包含基础像素算法。

### 仅仿真/验证源

所有 `tb_*.sv`、`ops/tb_pixel_ops.sv`、`mem/render_*_mem_model.sv`、`video/tb_*.sv` 以及 `case2/tb` 下的测试平台。`xsim_*` 目录中的 `.log`、`.jou`、`.pb`、`.dbg` 和 `xsim.dir` 不是 RTL 源，不要导入 Efinity 综合。

### 不参与编译的文档

各目录 `README.md`、`common/renderer_interfaces.md` 和本文件用于理解接口；它们不应作为 HDL source 添加。

## 11. 推荐 GUI 集成顺序

先建立一个仅使用 direct CSR、behavior memory、同源时钟和并行 video 的 board-independent 工程，确认 `c2_renderer_system` 能综合/仿真。然后仅替换一项边界：先接 AXI-Lite 控制，再接 DDR3 AXI 用户端，随后接 page/display CDC，最后接 PLL/复位和 HDMI PHY。每替换一项都保留前一版可运行的仿真参数。

建议每一步都观察以下信号：`cmd_valid/cmd_ready`、`parser_error_valid`、`engine_busy/done/error`、owner grant、`mem_req_valid/ready`、`mem_rsp_valid/last`、`mem_wr_valid/last`、`mem_wr_rsp_valid/error`、`vblank_start/prefetch_start`、`active_page`、`display_underflow` 和 AXI 的 AW/W/B/AR/R 通道。特别要确认写 owner 在最后一个 W beat 后仍保持到 B/`wr_rsp`，否则可能提前释放共享端口。

## 12. 当前文件架构的已知边界

这些 `.sv` 文件已经覆盖了二维渲染协处理器的 RTL 基线、burst 事务、owner 仲裁、AXI 协议适配和行为级显示验证，但不等于完成了：Sapphire/RISC-V 软件、CPU 与加速器共享 DDR 的系统互连、DDR3 校准、真实 CDC、HDMI 物理输出、Efinity 目标器件布局布线/STA、板上 FPS 或高负载游戏。GUI 集成时应把黑盒和这些缺口当作明确的工程任务，而不是把 stub 接通视为完成。

相关验证入口和真实数据口径见 [赛题二技术报告](D:/contest/2026FPGA/yilingsi/case2/report/赛题二_二维图形加速系统设计报告.md) 与 [system README](D:/contest/2026FPGA/yilingsi/case2/rtl/system/README.md)。
