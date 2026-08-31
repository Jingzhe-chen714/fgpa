# 2026 FPGA 赛题官方补充资料分析与赛题一/二适配建议

> 面向对象：赛题一“AI 赋能的实时绘画”和赛题二“2D 图形渲染加速引擎”的设计会话  
> 分析范围：`resource/` 下四份官方补充 PDF、`doc/` 中旧版赛题指南，以及 `D:\contest\Demo\Ti60F225_IMX219_HDMI_1080P` 已解压工程  
> 结论基准：PDF 物理页码；所有资源数字均为规划依据，最终以对应板卡、Efinity 版本和 post-route 报告为准

## 1. 技术结论摘要

1. **更正版对赛题一的技术指标基本没有实质放松。** MIPI CSI-2、RAW 转 RGB、Resize、外部 DDR 双缓冲、CNN 卷积/激活/归一化、AXI4、RISC-V 调度、HDMI 和 640×480 下稳定 15 fps 仍然是基础闭环。
2. **更正版对赛题二作了实质性收窄。** 旧版允许“AXI4/Wishbone、DDR/SDRAM、VGA/HDMI”，更正版改为“AXI4、DDR3、HDMI”。赛题二会话应以 AXI4 master + DDR3 + HDMI 为正式目标，Wishbone、SDRAM 或 VGA 只能作为内部原型，不能作为最终交付边界。
3. **TinyML 手册提供的是可借鉴的 EVSoC 架构，不是竞赛板可直接运行的完整 Demo。** 手册使用 Raspberry Pi V2 摄像头、HyperRAM 和 Mini-DSI；竞赛一平台指向 SC431HAI、DDR3 和 HDMI，摄像头驱动、存储控制器、显示链路和约束都需要替换。
4. **片上 RAM 是赛题一最早暴露出的资源风险。** TinyML 手册中的完整视频框架使用 211 个 M10K；若按 Ti60 的 256 个 M10K 规划，只剩 45 个。参数生成器截图中的一个 TinyML 示例又估算 38 个 RAM，机械叠加将达到 249/256，仅余 7 个。该加法不是最终综合结论，但足以否定“不裁剪地整套搬用 EVSoC 框架”的方案。
5. **现成 TinyML 流程没有证明赛题一的实时性。** 手册正文称示例一次推理约 940 ms，同页终端截图又显示前层约 1218 ms、输出层约 31 ms；两种口径都远大于 15 fps 对应的 66.7 ms/帧。模型不同，不能直接判定风格迁移失败，但必须把 Efinity 资源与端到端周期估算前置。
6. **Custom Instruction 适合作为加速器 doorbell/descriptor 接口，不适合逐像素搬运。** 接口只有两个 32-bit 输入、10-bit function ID 和一个 32-bit 返回值。赛题一可传张量/描述符地址，赛题二可传命令描述符或队列索引；实际图像数据仍应通过 AXI4/DDR。
7. **Custom Instruction 示例存在握手勘误。** 文档时序图显示 `rsp_valid` 先于 `rsp_ready`，但模板把 `rsp_valid` 组合依赖于 `rsp_ready`，两者矛盾，也不符合常规 ready/valid 规则。不要直接复制模板。
8. **`EFX_DSP48/24/12` 是 Efinity 厂商原语，Vivado xsim 默认不能识别。** 应在算法核心外增加厂商适配层：Efinity 分支实例化 EFX 原语，xsim 分支使用等延迟的行为模型；同时统一有符号、舍入、饱和、流水级数和 back-pressure 行为。
9. **难度判断没有反转。** 赛题二仍可在 RTL+xsim 阶段完成大部分核心逻辑；赛题一虽有参考框架，但资源、算子覆盖和真实性能均要求尽早进入 Efinity 与板卡验证，整体风险仍显著高于赛题二。
10. **解压后的视频工程确认是 IMX219 2-Lane RAW8，而不是 SC2210。** `I2C_SC2210_19201080_4Lanes_Config` 只是误标名称；其 `0x30EB`、`0x0114`、`0x016x/0x017x`、`0x018C/0x018D` 和 `0x030x` 序列均对应 IMX219。该表仍不能用于赛题一的 SC431HAI。
11. **视频 Demo 与 TinyML Demo 没有集成。** 解压工程只有 camera→DDR→RAW8 ISP→HDMI，不含 Sapphire、TinyML/NPU 或真正 Resize。赛题二完全不需要 TinyML；赛题一也只能在模型审计通过后选择性接入 TinyML 结构。

## 2. 资料清单、适用范围与可靠性

| 资料 | 主要内容 | 对题一/二的价值 | 可靠性与限制 |
|---|---|---|---|
| [2026 FPGA 竞赛赛题指南 - 8.22（更正版）](<./resource/2026 FPGA竞赛赛题指南 -8.22(更正版).pdf>) | 平台、题一至题四要求、支持与 Q&A | 当前赛题要求的首要依据 | 没有修订记录；p.7 与 p.29 对指定板卡是否强制存在冲突 |
| [旧版 2026 FPGA 赛道选题指南](<./doc/全国大学生嵌入式芯片与系统设计竞赛'2026FPGA赛道选题指南-易灵思.pdf>) | 旧版任务、技术提示、自由选题 | 用于识别更正内容，并保留被新版压缩掉的工程提示 | 规则冲突时应让位于更正版及后续官方答复 |
| [EVSoC TinyML 用户手册](<./resource/1_3_EVSOC_tinyml用户手册_0416.pdf>) | Sapphire、DMA、MIPI、HyperRAM、TinyML、TFLite、量化与资源示例 | 题一架构和软硬件接口的重要参考；题二可借鉴 DMA/控制面模式 | 封面为 Draft V2.0，内容基于另一块 Ti60 F225 DevKit；多处交叉引用和性能数字不一致 |
| [RISC-V Custom Instruction](<./resource/2、RISCV Custom Instruction.pdf>) | CI 架构、信号、时序、RTL 模板、软件宏 | 题一/题二降低 CPU 发命令开销 | 只有 8 页介绍，缺少完整 SoC 配置、资源和性能；示例握手存在明显矛盾 |
| [Titanium FPGA DSP 原语介绍](<./resource/3、 钛金FPGA DSP原语介绍.pdf>) | DSP48/24/12 模式、端口与模板 | 题一 INT8/INT4 MAC、题二 Alpha Blending | 是介绍型幻灯片而非完整原语手册；存在拼写和位宽注释错误，FMax 为条件性上限 |

### 2.1 本报告如何使用这些资料

- **规则优先级：** 后续官方书面答复 > 更正版赛题指南 > 旧版指南 > 示例手册和演示幻灯片。
- **资源优先级：** 目标工程 Efinity post-route > Efinity synthesis > TinyML Generator 估算 > 文档典型值 > Vivado 代理综合。
- **性能优先级：** 实板端到端测量 > Efinity 时序与周期模型 > RTL 仿真周期数 > 文档示例时间。
- **Vivado 的定位：** 验证算法、协议和控制状态机；Vivado 的 LUT/BRAM/DSP 映射不能替代 Ti60 的资源和时序结果。

## 3. 更正版赛题指南的实质变化

### 3.1 赛题一：任务不变，工程提示被压缩

旧版 p.4–7 与更正版 p.11–13 的基础指标基本一致：

- SC431HAI 经 MIPI D-PHY RX 与 CSI-2 RX Controller 接入；
- FPGA 完成 CSI-2 解析、Debayer、Resize，最低 640×480@30 fps；
- 预处理帧写入外部 DDR，并采用 Ping-Pong Buffer；
- 至少硬件化 3×3 或 5×5 卷积、ReLU、BatchNorm 或 InstanceNorm 的近似计算；
- 加速器通过 AXI4 从 DDR 读图像块并写回结果帧；
- HDMI 最低 720p@60 fps 或 1080p@30 fps；
- RISC-V 完成摄像头初始化、权重部署、任务调度和中断处理；
- 640×480 下稳定达到 15 fps，并显示原画与风格画对比。

更正版删除了旧版中“C 语言驱动”的显式字样，但没有删除任何控制任务。因此实现上仍应提供清晰的 C/C++ 驱动接口和寄存器定义。

旧版 p.7 的网络轻量化、行流水线和展示建议未进入新版幻灯片。这更像版面压缩，不代表整帧逐层回写 DDR 因此变成合理方案。对于 Ti60，层融合、行/块流水线和减少中间特征图流量仍是赛题一能否成立的核心。

### 3.2 赛题二：总线、外存和显示接口被明确收窄

| 项目 | 旧版 p.7–8 | 更正版 p.15–16 | 应采用的正式实现 |
|---|---|---|---|
| 系统总线 | AXI4 / Wishbone | AXI4 | AXI4-Lite 控制 + AXI4 master 数据面 |
| 外部存储 | DDR / SDRAM | DDR3 | 板载 DDR3 控制器与物理接口 |
| 显示 | VGA / HDMI | HDMI | HDMI 时序、帧缓存和双缓冲 |
| 基础操作 | Block Copy、Solid Fill | 不变 | 必做 |
| 内存优化 | Burst、FIFO | 不变且新版语气更直接 | 必做并需要随机等待仿真 |
| 软件对比 | CPU vs Hardware FPS | 不变，新版用红色强调 | 必须设计可重复的性能基线 |

这意味着赛题二会话可以继续使用 xsim 的 AXI RAM/DDR 行为模型，但顶层接口、寄存器协议和测试场景必须能够无结构性重写地迁移至 AXI4 + DDR3 + HDMI。

### 3.3 平台规则在更正版内部仍有冲突

- 更正版 p.7 写“同一个赛题所有参赛队伍统一使用同款开发板”。
- 更正版 p.29 又写“指定使用 Ti60 处理器，不强制使用指定开发板；只要是 Ti60 芯片都可以做赛题 1～4”。

当前最稳妥的工程解释是：**Ti60 器件是硬约束，官方开发板是强烈推荐而非唯一合法硬件。** 但这只是推断，必须向官方确认参赛规则，以免在自制板或第三方板上投入后遇到资格问题。

更正版 p.7 还把 Ti60F225I3 描述为“集成 RISC-V 处理器及专用 NPU”。TinyML 手册则明确展示 Sapphire RISC-V SoC 和 TinyML Accelerator 占用 FPGA LUT、RAM 和 DSP。报告中因此不把所谓 NPU 当作免费硬核资源，除非官方进一步提供：

- NPU 的确切 IP 名称与版本；
- 是否是硅上硬核、加密网表还是普通 RTL；
- 支持算子、数据格式、资源占用和授权方式；
- 是否包含在竞赛资料包及指定 Efinity 许可中。

## 4. Ti60 与竞赛板资源基线

### 4.1 器件规划基线

本项目继续采用此前已核对的 Ti60F225 规划口径：

| 资源 | 规划基线 | 说明 |
|---|---:|---|
| XLR | 60,800 | Efinity 布局报告口径，与 Vivado LUT 不能一一换算 |
| M10K Memory Blocks | 256 | 总计约 2.6 Mbit，约 320 KiB |
| DSP Blocks | 160 | 物理 DSP 数与 DSP12/24 原语实例数不必一一对应 |
| GBUF | 32 | 系统、DDR、MIPI、HDMI 等全局时钟需要共同规划 |
| PLL | 4 | HDMI、MIPI、DDR3 和系统时钟需要统一规划 |

最终应以具体订购型号 Ti60F225I3、封装、速度等级和 Efinity 器件数据库为准。

### 4.2 更正版展示的题一至题三开发板

更正版 p.7 的开发板照片和标注显示：

- Ti60F225I3；
- 板载 DDR3；
- HDMI RX 与 HDMI TX；
- MIPI 连接器与 LVDS/MIPI 接口；
- YT8531SC 三速以太网 PHY；
- FT4232、JTAG/UART、按键和 LED。

赛题说明正文只承诺 MIPI CSI-2 输入、HDMI 音视频输出、DDR3 和千兆以太网。照片中的 HDMI RX 等接口是否提供完整参考工程、约束和 IP，不能仅凭板卡丝印推断。

补充资料没有明确给出以下关键板级参数：

- DDR3 容量、数据位宽、器件速度和可用 AXI 数据宽度；
- DDR3 控制器是否硬核、软 IP 或板卡参考 RTL；
- HDMI TX 使用方式、颜色位宽和音频链路；
- SC431HAI 的 lane 数、RAW 位宽、Bayer 顺序和默认时序；
- MIPI D-PHY/CSI-2、DDR3、HDMI 和 Sapphire IP 的确切版本。

在这些信息确认前，题一/题二工程应把板级依赖隔离为适配层，不在算法 RTL 内直接实例化 Xilinx MIG、XPM 或 EFX 原语。

### 4.3 已解压视频工程对资料结论的验证与修正

分析路径：

```text
D:\contest\Demo\Ti60F225_IMX219_HDMI_1080P
```

该工程使用 Efinity 2024.2.294、Ti60F225 C4，最后一次 route/bitstream 成功。其活动数据路径是：

```text
IMX219 2-lane CSI-2 RAW8
    -> CSI RX
    -> DDR3 四帧 frame store
    -> RAW8 Bayer RGB
    -> manual white balance
    -> 2-pixel boundary crop
    -> LCD timing / TMDS encoder
    -> Efinity LVDS serializers
    -> HDMI
```

这里需要纠正一个很容易误导设计会话的命名问题：活动模块虽然叫 `I2C_SC2210_19201080_4Lanes_Config`，其寄存器表实际是 IMX219。`0x0114=0x01` 与生成的 CSI RX `NUM_DATA_LANE=2` 一致，`0x018C/0x018D=0x08/0x08` 与顶层“只支持 RAW8”及 RAW8 Bayer 模块一致。这些定义可与 [Linux upstream IMX219 driver](https://github.com/torvalds/linux/blob/master/drivers/media/i2c/imx219.c) 交叉核对。顶层 D0～D3 四组端口只是宽模板，最后层次只生成两个 lane FSM，lane 2/3 被移除或悬空。

工程对赛题的价值和缺口如下：

| 项目 | 赛题一 | 赛题二 |
|---|---|---|
| 架构相关性估计 | 约 60%～70% | 约 35%～45% |
| 可直接复用代码估计 | 约 25%～35% | 约 15%～25% |
| 最有价值内容 | CSI/帧写读/视频 timing/HDMI 骨架 | DDR scanout、video timing、TMDS 编码 |
| 必须重做 | SC431HAI、lane/RAW、RAW10 unpack、Resize、风格核、Sapphire、多主 DDR | BitBlt descriptor、二维 AXI master、Fill/Copy/Alpha/Key、Sapphire、仲裁 |
| 应删除 | 旧 IMX219 表和无关 DSI/LVDS 分支 | 全部 camera/I²C/CSI/Bayer/白平衡/DSI/LVDS 分支 |

百分比是按赛题功能范围做的工程估计，不是文件数占比。特别是视频 `axi4_ctrl` 只是固定 1920×1080、128-beat burst、四帧轮转的 frame pump；它既不是通用多主 AXI fabric，也没有 BitBlt 的 source/destination/stride/alpha/color-key 语义。工程中的通用 crop 实例被注释，活动裁剪只有边界两像素，不能当作 Resize。

最后一次实现的资源为 8,981/60,800 XLR、62/256 RAM、1/160 DSP、15/32 GBUF、4/4 PLL。资源不是压力点，但 PLL 已满、GBUF 接近一半，合并 Sapphire/TinyML 前必须删除未使用的 DSI/LVDS/LCD 时钟分支并重新规划。C4 报告中最薄 setup/hold 余量约为 0.116/0.026 ns，不能外推至竞赛 I3。

Vivado xsim 的实际边界也得到确认：CSI RX/DDR 生成脚本面向 ModelSim/Questa，DDR 主文件包含 IEEE-1735 保护块；HDMI 的物理 LVDS serializer 位于 `.peri.xml`。因此应以行为 CSI 源、随机延迟 AXI memory model 和 TMDS symbol checker 完成纯 RTL 验证，不把 xsim 不能展开的厂商 IP 当作前期阻塞。更详细的文件级入口、警告和适配步骤见 [官方 Demo 深度分析与赛题一/二适配指南](./OFFICIAL_DEMO_ADAPTATION_GUIDE.md)。

## 5. TinyML 参考架构、资源和性能风险

### 5.1 手册架构并非竞赛板的原样工程

TinyML 手册 p.6–13 的数据流是：

```text
Raspberry Pi V2 / MIPI CSI-2 RX
    -> Pre-Processor
    -> DMA Controller
    -> HyperRAM
    -> Hardware Accelerator 或 TinyML Accelerator
    -> DMA / Post-Processor
    -> CSI-2 TX
    -> Mini-DSI Panel
```

关键接口：

- RISC-V SoC 连接系统互连并进行配置；
- 普通 Hardware Accelerator 由 AXI4 slave 寄存器控制；
- DMA 与普通加速器之间默认使用 32-bit AXI-Stream；
- DMA 支持 direct 和 scatter-gather，支持轮询或中断；
- TinyML Accelerator 通过 Custom Instruction 接收命令，并通过 AXI4 master 访问外存；
- TFLite 软件在 RISC-V 上运行，硬件模块加速耗时算子。

竞赛一需要替换的边界：

| TinyML 手册 | 赛题一 |
|---|---|
| Raspberry Pi V2 | SC431HAI |
| HyperRAM | DDR3 |
| Mini-DSI / CSI-2 TX | HDMI TX |
| 1920×1080 RAW10，裁剪至 1080×1080 再缩至 540×540 | 640×480 输入处理，720p60 或 1080p30 显示 |
| 人脸/人体检测模型 | 风格迁移网络 |

因此应复用“模块划分与控制思想”，而不是把该工程视作 pin-compatible Demo。

### 5.2 算子覆盖不足以直接承载常见风格迁移网络

手册 p.10–12 只明确列出：

- Convolution / Depthwise Convolution；
- ADD；
- MAXIMUM；
- MULT；
- Fully Connected。

常见风格迁移模型可能还包含：

- Instance Normalization；
- Reflection/Same Padding；
- Resize、Upsample 或 Transposed Convolution；
- Concat、Slice、Reshape；
- Tanh、LeakyReLU 或其他非线性；
- 残差连接和不同量化 scale 的 requantization。

BatchNorm 在推理时通常可以折叠进卷积权重和偏置；InstanceNorm 依赖当前样本统计量，通常不能直接按同一方式无条件折叠。题一会话必须在确定网络之前导出 `.tflite` 算子和 tensor shape 清单，逐项标记：

```text
TinyML 已支持 / 可折叠 / 可由 CPU 低频完成 / 需要自定义 RTL / 应替换网络结构
```

### 5.3 完整视频框架已经接近 M10K 上限

TinyML 手册 p.7–8 的典型资源如下：

| 模块 | FF | Adders | LUT | M10K | DSP |
|---|---:|---:|---:|---:|---:|
| Complete Design | 19,246 | 2,673 | 28,265 | 211 | 4 |
| RISC-V SoC | 6,196 | 702 | 7,301 | 59 | 4 |
| DMA Controller | 6,162 | 745 | 8,393 | 67 | 0 |
| CSI-2 RX | 871 | 60 | 2,149 | 15 | 0 |
| DSI TX | 1,574 | 111 | 4,506 | 21 | 0 |
| HyperRAM Controller | 1,738 | 263 | 2,601 | 18 | 0 |
| Camera | 814 | 618 | 1,039 | 11 | 0 |
| Display | 489 | 0 | 716 | 12 | 0 |
| Hardware Accelerator | 630 | 162 | 606 | 8 | 0 |
| TinyML Accelerator | 文档为空 | 文档为空 | 文档为空 | 文档为空 | 文档为空 |

三个结论：

1. `Complete Design` 的 211 M10K 约占 256 块基线的 82.4%。
2. DMA Controller 单独使用 67 个 M10K，说明多通道、大深度 FIFO 是优先裁剪对象。
3. TinyML Accelerator 行为空，`Complete Design` 不能被理解为已经包含 AI 推理资源。

手册 p.21 的参数生成器截图显示某个示例配置估算为：

- 13,971 LUT；
- 11,612 FF；
- 6,119 Adders；
- 38 RAM；
- 60 MULT/DSP。

若仅作风险上界提示而机械相加：

```text
LUT  = 28,265 + 13,971 = 42,236
FF   = 19,246 + 11,612 = 30,858
RAM  = 211 + 38 = 249 / 256
DSP  = 4 + 60 = 64 / 160
```

这里的 `RAM` 和 `MULT/DSP` 是 Generator 估算列，是否最终映射为同数量 M10K/物理 DSP 要由 Efinity 确认。即便如此，249/256 的量级意味着设计几乎没有 CDC FIFO、额外行缓存、调试逻辑和布局布线余量，不能作为可交付方案。

### 5.4 现有性能数字不能支持 15 fps 目标

赛题一 15 fps 的平均帧周期预算为：

```text
1 / 15 fps = 66.7 ms/frame
```

TinyML 手册 p.31：

- 正文声称一次推理约 940 ms；
- 同页终端截图显示前层约 1218 ms、输出层约 31 ms，总计约 1249 ms。

该模型并非风格迁移，且配置可能不同，因此这些数字只可用于风险判断，不能直接换算题一 FPS。但它们说明：

- `interpreter->Invoke()` 成功不等于实时；
- 必须区分 CPU fallback 算子与硬件算子；
- 需要测算每层 MAC、DDR 字节量、并行度和周期；
- 15 fps 必须通过专用数据流、减少中间 DDR、提高并行度或进一步简化网络实现。

### 5.5 外部内存与文档口径仍需核实

手册 p.7 架构图使用 16-bit HyperRAM，p.8 又写 DMA 连接“外部 256 位 DDR DRAM 接口”。可能一个指物理总线、一个指内部数据路径，但文档没有解释。手册 p.28、p.31 的软件构建还显示 16 MB 级 RAM region、默认 10 MB `kTensorArenaSize` 和约 84%–87% 使用率。

竞赛板改用 DDR3 后，应重新确认：

- CPU 可用内存区和缓存策略；
- Framebuffer、权重、Tensor Arena 和描述符的地址划分；
- AXI 数据宽度、突发长度、跨 4 KB 边界规则；
- 摄像头写、CNN 读写、HDMI 读之间的仲裁优先级。

## 6. Custom Instruction 接口与握手勘误

### 6.1 文档接口

Custom Instruction 文档 p.4 给出的 CPU 侧接口为：

| 信号 | 方向（以 CPU 为参照） | 含义 |
|---|---|---|
| `cpun_customInstruction_cmd_valid` | 输出 | rs1、rs2 和 function ID 有效 |
| `cpun_customInstruction_cmd_ready` | 输入 | 自定义逻辑能够接收命令 |
| `cpun_customInstruction_function_id[9:0]` | 输出 | 10-bit 功能号 |
| `cpun_customInstruction_inputs_0[31:0]` | 输出 | rs1 |
| `cpun_customInstruction_inputs_1[31:0]` | 输出 | rs2 |
| `cpun_customInstruction_rsp_valid` | 输入 | 结果有效 |
| `cpun_customInstruction_rsp_ready` | 输出 | CPU 能接收结果 |
| `cpun_customInstruction_outputs_0[31:0]` | 输入 | 32-bit 结果 |

软件侧使用 `driver/riscv.h` 中的 `opcode_R(opcode, func3, func7, rs1, rs2)`，示例使用 `CUSTOM0` 和不同的功能字段。

### 6.2 文档模板不能直接复制

文档 p.5 的时序图显示 `rsp_valid` 先拉高并保持，之后 `rsp_ready` 到来完成握手。但 p.6 模板包含：

```verilog
assign rsp_valid = rsp_ready & alu_result_ready;
assign cmd_ready = rsp_ready & (!alu_result_ready) & (!alu_busy) & (!rsp_valid);
```

问题包括：

- `rsp_valid` 依赖 `rsp_ready`，与 p.5 时序图矛盾；
- 若 CPU 等待 `valid` 后才产生 `ready`，可能死锁；
- `cmd_ready` 也被 `rsp_ready` 限制，命令接收和响应通道被不必要耦合；
- 模板 `case` 只使用 `cmd_function_id[1:0]`，而接口提供 10-bit function ID；
- 没有完整展示结果 pending、异常、超时和多周期 busy 的状态管理。

建议采用单未决事务的明确状态机：

```verilog
assign cmd_ready = !busy && !rsp_pending;
assign rsp_valid = rsp_pending;
assign rsp_data  = result_hold;

// cmd_valid && cmd_ready：锁存命令并启动
// result_done：锁存结果并置 rsp_pending
// rsp_valid && rsp_ready：清除 rsp_pending
```

必须保证在 `rsp_valid && !rsp_ready` 期间：

- `rsp_valid` 保持为 1；
- `rsp_data` 保持稳定；
- 不接受会覆盖结果的新命令。

### 6.3 题一和题二的正确用法

题一建议：

```text
rs1 = tensor/job descriptor 地址
rs2 = operator ID、layer index 或 flags
result = completion status、error code 或 cycle count
```

题二官方最小命令已经包含 `op + src + dst + width + height`，两个 32-bit 操作数无法一次承载。建议二选一：

1. `rs1 = command descriptor 地址`，`rs2 = queue index/flags`；
2. AXI4-Lite 寄存器或 DDR command ring 负责命令，CI 仅作为 doorbell。

无论使用哪种方式，CI 都不能替代更正版要求的 AXI4 数据面。

## 7. DSP 原语与 Vivado xsim 适配

### 7.1 原语能力

DSP 文档 p.2–8 列出：

| 原语 | 输入端口 | 输出 | 模式与用途 |
|---|---|---|---|
| `EFX_DSP48` | A[18:0]、B[17:0]、C[17:0] | O[47:0] | 整数 Normal/Dual/Quad、BF16、乘加、级联、移位 |
| `EFX_DSP24` | A/B/C[7:0] | O[23:0] | 8-bit 整数运算 |
| `EFX_DSP12` | A/B/C[3:0] | O[11:0] | 4-bit 整数运算 |

`EFX_DSP48` 的模式切片：

- Normal：19×18；
- Dual：一个 11×10 与一个 8×8；
- Quad：一个 7×6 与三个 4×4；
- BFloat：16×16。

支持：

- signed/unsigned 运算；
- A/B/C/P/OP/W/O 可选寄存器；
- 乘、加、减、累加和可变右移；
- `CASCIN/CASCOUT` 级联；
- DSP48 的 BF16 与舍入配置。

文档说多个 DSP12/DSP24 可以合并进一个物理 DSP48，但没有给出保证的打包比例。资源预算必须使用 Efinity 的 packed/physical DSP 报告，不能把原语实例数直接当物理 DSP 数。

### 7.2 文档勘误和使用限制

- p.2 的 `bfoat16` 应为 `bfloat16`，“FMA晕眩”应为 FMA 运算；
- p.6 中 `C[17:0]` 实际为 18 bit，注释却写“17-bit C input”；
- p.7、p.8 标题写作“DSP48 24/12”，实际原语名是 `EFX_DSP24/12`；
- p.2 的“FMax 可达 1 GHz”是条件性上限，而 p.6–8 示例默认关闭各级寄存器，不能据此设定工程目标频率。

题一的 INT8 MAC 可优先评估 DSP24 或 DSP48 多通道模式，INT4 可评估 DSP12/Quad。题二的 Copy、Fill、Color Key 不需要 DSP；Alpha Blending 才需要乘法资源。

对题二 Alpha，推荐先用数学上清晰的无符号实现：

```text
out = (fg * alpha + bg * (255 - alpha) + rounding) >> 8
```

另一个常见形式 `bg + (fg-bg)*alpha/256` 涉及有符号差值与无符号 alpha；若原语只有统一 `SIGNED` 参数，必须谨慎扩展位宽，不能把 8'hFF 在 signed 模式下误解释为 -1。

### 7.3 xsim 适配层

Vivado xsim 默认不认识 `EFX_DSP48/24/12`。建议目录和层次保持如下：

```text
algorithm_core/
    conv_mac_array.sv
    alpha_blend.sv

platform/
    efinity/efx_dsp_mac.sv      // EFX_DSP* 原语
    xsim/dsp_mac_model.sv       // 纯 RTL 行为模型
    dsp_mac_wrapper.sv          // 条件选择
```

行为模型必须与硬件配置对齐：

- 输入/输出位宽；
- signed/unsigned；
- 乘加和移位次序；
- rounding、截断、饱和或 wrap；
- A/B/C/P/O 等寄存器造成的总延迟；
- CE、reset 同步/异步和有效极性；
- back-pressure 下数据与 valid 的保持。

建议在 xsim 中先验证算法核心，不使用 Xilinx DSP48E、XPM RAM 或 MIG 作为不可替换依赖。若用 Vivado 综合作代理估算，应使用可综合乘法表达式，并明确报告只反映 Xilinx 映射趋势。

## 8. 对赛题一会话的直接影响

### 8.1 仍可在 RTL+xsim 完成的工作

- RAW/Bayer 测试流生成、Debayer 和 Resize；
- INT8/INT4 卷积、Depthwise、ReLU、requantization；
- BatchNorm 折叠后的 scale/bias；
- 行缓存、Tile Buffer、层融合和 valid/ready；
- AXI4/AXI-Stream 行为模型；
- DDR 随机延迟、突发和仲裁模型；
- CI 状态机与 descriptor 解析；
- Python/TFLite Golden Model 的逐层或逐像素对比；
- 每层周期、理论 DDR 字节量和端到端帧周期统计。

### 8.2 不能由 xsim 证明的工作

- MIPI D-PHY lane、CSI-2 加密 IP 和 SC431HAI 实际驱动；
- DDR3 PHY 初始化、校准、板级稳定性和真实带宽；
- Sapphire IP 生成、固件下载、Cache/中断一致性；
- EFX DSP、M10K、PLL 和布局布线后的真实 FMax；
- HDMI TX 与显示器兼容性；
- 640×480 实机稳定 15 fps 和无丢帧风格切换。

### 8.3 赛题一近期淘汰门槛

在继续投入完整系统前，至少满足：

1. 已得到候选模型完整算子清单，没有未处理的 CPU-heavy fallback；
2. 固定点 Golden Model 画质可接受，所有量化参数有明确位宽；
3. RTL 核心周期估算满足小于 66.7 ms/帧，并预留 DDR/调度余量；
4. Efinity 早期综合后 M10K、逻辑和 DSP 均保留可用余量，不接受接近 249/256 M10K 的方案；
5. MIPI、DDR3、Sapphire 和 HDMI 官方最小 Demo 均已分别验证。

结论：补充资料提升了题一的架构可参考性，但也确认了资源和性能高风险，不能仅凭 TinyML 工程存在就认为难度下降。

## 9. 对赛题二会话的直接影响

### 9.1 正式架构应锁定为 AXI4 + DDR3 + HDMI

建议结构：

```text
Sapphire / command producer
    -> AXI4-Lite registers 或 DDR command ring
    -> BitBlt scheduler
    -> AXI4 read burst / line FIFO
    -> Copy / Fill / Color Key / Alpha pipeline
    -> AXI4 write burst
    -> DDR3 framebuffer
    -> display DMA / HDMI timing
```

Custom Instruction 可作为命令提交优化，但不要把 BitBlt 数据通路挂在 CI 的 32-bit 操作数上。

### 9.2 不建议整体复用 TinyML DMA

TinyML 手册中的 DMA 为多路固定方向视频框架服务，典型资源约 8,393 LUT、67 M10K。赛题二只需要受控的二维读写、stride、Burst、FIFO 和读改写路径，自研精简二维 DMA 更容易：

- 控制资源；
- 处理源/目标 stride；
- 支持小 Sprite 和大图不同 burst 策略；
- 支持地址不对齐与行尾；
- 处理源/目标区域重叠；
- 为 Alpha 增加背景读和写回；
- 与 VSync/双缓冲建立明确所有权。

### 9.3 赛题二可在 xsim 完成的大部分任务

- Block Copy 和 Solid Fill；
- AXI4 burst 拆分、4 KB 边界和 back-pressure；
- 不对齐地址、奇数宽度、stride 和裁剪；
- 小 Sprite 导致的短 burst 效率；
- 双缓冲与 VSync 指针切换；
- Alpha、Color Key 和像素格式处理；
- CPU 软件渲染与硬件周期基线；
- 随机 DDR ready/latency 下的死锁、溢出和数据一致性验证。

### 9.4 必须在 Efinity/板卡完成的证明

- Sapphire 驱动和命令提交开销；
- DDR3 控制器、PHY、仲裁和真实 burst 效率；
- HDMI 640×480@60 Hz 及更高分辨率稳定输出；
- 双缓冲是否真实无撕裂；
- 同屏 Sprite 数量、60 fps 稳定性和资源报告；
- Alpha DSP 原语打包与时序。

结论：赛题二仍是更适合先用 RTL+xsim 做深度评估的题目，补充资料没有引入题一级别的 AI 算子与资源不确定性。

## 10. RTL+xsim 与 Efinity/板卡工作的明确边界

| 工作项 | RTL+xsim | Efinity | 实际板卡 |
|---|---|---|---|
| 算法数值正确性 | 主要完成 | 可复核 | 演示确认 |
| valid/ready、FIFO、CDC 逻辑 | 主要完成 | 时序/实现检查 | 长时间稳定性 |
| AXI4 协议、随机等待 | 主要完成 | IP 连接检查 | 真实带宽 |
| CI 命令与响应 | 行为模型完成 | Sapphire IP 接入 | 固件与中断 |
| DSP 算法 | 行为模型完成 | EFX 原语映射和打包 | FMax/功耗 |
| 片上 RAM | 抽象模型 | M10K 映射 | 稳定性 |
| MIPI/CSI-2 | 只能仿真抽象像素流 | IP 生成与时序 | 必须验证 PHY/相机 |
| DDR3 | 行为 RAM/延迟模型 | 控制器、PHY、时序 | 必须校准和压测 |
| HDMI | 像素与时序模型 | PLL、IO 和约束 | 必须接显示器 |
| 端到端 FPS | 周期上界 | 频率与资源 | 最终裁决 |

判断原则：

- xsim 通过只能证明“设计逻辑在模型假设下正确”；
- Efinity 综合通过只能证明“资源和时序有机会成立”；
- 板卡稳定运行才能证明“接口、带宽、软件和物理链路闭环成立”。

## 11. 两个会话的近期行动清单

### 11.1 共同工作

1. 安装或取得与官方 Demo 匹配的 Efinity、RISC-V SDK 和 IP 包版本。
2. 从官方 Demo 提取板级接口层，确认 DDR3、Sapphire、HDMI、MIPI 和约束文件的实际模块名。
3. 建立厂商无关的 `core` 与 Efinity/xsim 两套 `platform wrapper`。
4. 为 ready/valid、AXI、FIFO 和 CI 增加断言；禁止直接复制 CI p.6 模板。
5. 第一次 Efinity 综合就记录 M10K、物理 DSP、逻辑、FMax 和拥塞，不等到功能完整后再看资源。

### 11.2 赛题一会话

1. 导出候选风格网络算子、tensor shape、参数量和逐层 MAC。
2. 用代表性图像做 INT8 量化，验证画质与 InstanceNorm 替代策略。
3. 运行 TinyML Generator 或最小 Efinity 工程，获得单独加速器资源，而非沿用手册空白行。
4. 先做 `synthetic RAW -> preproc -> one/two layer accelerator -> framebuffer model` 的 xsim 闭环。
5. 以 640×480@15 fps 为唯一第一阶段目标；720p30、多风格和交互延后。
6. 优先裁剪 DMA 通道、FIFO 深度和不需要的显示/MIPI TX 模块。

### 11.3 赛题二会话

1. 将总线接口正式锁定为 AXI4，不再把 Wishbone-only 作为候选终版。
2. 定义包含 `op/src/dst/width/height/src_stride/dst_stride/format/flags` 的 descriptor。
3. 完成行为 DDR 的随机延迟、短 burst、4 KB 边界和 back-pressure 测试。
4. 先完成 Fill、Copy、双缓冲，再加入 Color Key，最后加入 Alpha。
5. 为 CPU 软件基线和硬件基线定义相同分辨率、像素格式、元素数量和测量窗口。
6. 不整体移植 TinyML DMA；只参考其 direct/SG、FIFO、轮询/中断结构。

## 12. 待向官方确认的问题

### 12.1 规则与板卡

1. 赛题 1～4 是只强制 Ti60 器件，还是强制对应官方开发板？p.7 与 p.29 哪一条优先？
2. 题一至题三开发板的准确型号、原理图版本和 Ti60 速度等级是什么？
3. DDR3 的容量、位宽、频率、颗粒型号和官方控制器版本是什么？
4. HDMI RX、HDMI TX、以太网是否都提供完整 Efinity 工程、约束和软件驱动？

### 12.2 赛题一

5. SC431HAI 使用几条 MIPI lane、RAW10 还是 RAW12、默认 Bayer 顺序和目标输入帧率是什么？
6. MIPI D-PHY RX、CSI-2 RX Controller 是否包含可用于当前 Efinity 版本的仿真模型？是否支持 xsim？
7. “专用 NPU”究竟是硬核、加密 IP 还是 TinyML RTL？参赛队伍是否都能获得？
8. TinyML Accelerator 支持的完整 TFLite 算子、量化约束和模型生成器版本是什么？
9. 基础要求中的 InstanceNorm 是否允许网络替换、近似或以其他归一化实现？评价标准是什么？
10. 15 fps 是纯 CNN 处理帧率还是摄像头到 HDMI 的端到端有效更新帧率？

### 12.3 赛题二

11. 更正版将总线写为 AXI4，AXI4-Lite 控制 + AXI4 master 数据面是否符合要求？
12. Framebuffer 是否必须位于 DDR3，还是允许片上缓存参与局部合成？
13. CPU 与硬件 FPS 对比的统一场景、计时方法和最低运行时长是否有规定？
14. 双缓冲是否要求与 HDMI VSync 同步切换，还是只要求演示无撕裂？
15. Alpha Blending 的像素格式、alpha 位宽和舍入规则是否由队伍自定义？

### 12.4 工具链与原语

16. 竞赛推荐的 Efinity、RISC-V SDK、Sapphire、DDR3、MIPI 和 HDMI IP 精确版本是什么？
17. `EFX_DSP12/24` 的物理 DSP48 打包规则和 Generator 中 `MULT/DSPs` 的统计口径是什么？
18. Custom Instruction p.6 的 `rsp_valid` 写法是否为文档错误？官方是否有已验证 RTL 示例？
19. 官方提供的 TinyML 示例资源表为何 `TinyML Accelerator` 一行为空？完整工程是否包含该模块？
20. TinyML 手册 p.31 的 940 ms 与终端截图约 1249 ms 分别对应什么模型和配置？

## 13. 决策建议

- **赛题一：** 在拿到 Efinity/IP 后立即做资源和算子覆盖审计。若完整闭环无法在片上 RAM 留出合理余量，或 640×480 下周期预算明显超过 66.7 ms，应及时缩小网络或停止作为主选题。补充资料没有消除其高风险属性。
- **赛题二：** 继续推进 RTL+xsim 是合理投入。把 AXI4、DDR3、HDMI 作为接口约束，从一开始就用随机 back-pressure 和 descriptor 驱动验证；待 Efinity 可用后优先验证 DDR3、Sapphire 和 HDMI，不必等待全部高阶功能完成。
- **两会话共用原则：** 算法核心保持厂商无关，板级 IP 和 EFX 原语集中封装；所有手册数字均作为初始风险信号，不作为“已经满足资源/性能”的证据。
