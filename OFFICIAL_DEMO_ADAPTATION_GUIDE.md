# 易灵思官方 Demo 深度分析与赛题一/二适配指南

分析对象：`D:\contest\Demo`

分析日期：2026-08-30

## 0. 先读结论

官方 Demo 不是一个已经打通的“摄像头 + TinyML + HDMI”系统，而是两套独立工程：

1. `tinyml-main\tinyml_hello_world\Ti60F225_tinyml_helloworld`：Sapphire RISC-V、TinyML 加速器和 DDR3 的 Hello World；
2. `Ti60F225_IMX219_HDMI_1080P`：已经解压的 IMX219、DDR3 帧缓存、基础 ISP 和 HDMI 视频工程。

两者的 Efinity 版本、器件时序模型、顶层、DDR 控制器、时钟树、地址映射和板级接口都不一致，不能把两个顶层或两份 `.peri.xml` 直接拼在一起。正确的复用方式是：

- 从视频工程提取 MIPI/视频时序/HDMI 的结构和板级配置思路；
- 从 TinyML 工程提取 Sapphire、Custom Instruction、AXI128、软件 BSP 和模型工具链的结构；
- 在竞赛 Ti60F225I3 板上重新生成一套统一的 PLL、DDR3、MIPI、HDMI、Sapphire 和总线系统；
- 全系统只能保留一个 DDR3 控制器、一个最终顶层、一个地址图和一套复位/时钟规划。

对赛题一/二的直接结论如下。百分比表示“完成赛题功能时可借鉴/复用的功能范围”，不是文件数量占比：

| 赛题 | 架构相关性 | 可直接复用代码估计 | 结论 |
|---|---:|---:|---|
| 赛题一 | 约 60%～70% | 约 25%～35% | 可借鉴 CSI→DDR→视频输出骨架，但 SC431HAI、RAW10/12、Resize、风格迁移、Sapphire 和多主 DDR 都没有完成 |
| 赛题二 | 约 35%～45% | 约 15%～25% | 只重点复用 DDR 帧缓存/scanout、视频时序和 HDMI 编码思路；BitBlt、命令队列、二维 AXI master 和 Sapphire 均需新增 |

因此，`tinyml-main` 主要服务赛题三式的 TinyML 示例：**赛题二完全不需要 TinyML；赛题一只有在候选模型通过算子、资源和性能审计后，才可能选择性使用其 Sapphire/TinyML 结构。** 已解压视频工程自身不含 RISC-V、TinyML 或 NPU 内容。

最重要的陷阱有七个：

1. `I2C_SC2210_19201080_4Lanes_Config.v` 的文件名和模块名是误标；寄存器序列实际对应 **IMX219、2 Lane、RAW8、1920×1080**，工程目录名反而是正确的；
2. 顶层虽然保留 D0～D3 四组端口，但生成的 CSI RX 和有效综合层次只有 2 Lane，lane 2/3 被优化或悬空；
3. 工程只有被注释的 crop 和活动的两像素边界裁剪，没有赛题一所需的通用 Resize；
4. 视频 `axi4_ctrl` 是固定 1080p 四帧循环搬运器，不是通用 AXI fabric，更不是赛题二 BitBlt；
5. 视频工程针对 `Ti60F225 C4`，竞赛题一至三平台为 `Ti60F225I3`，C4 时序通过不能证明 I3 收敛；
6. TinyML 工程虽生成了 bitstream，但 300 MHz `i_sysclk` 的 setup slack 为 `-0.136 ns`；
7. TinyML 软件示例使用编译进固件的静态输入，不是实时摄像头输入；加速器主体还是受保护网表，Vivado xsim 不能承担其内部功能验证。

## 1. Demo 清单

| 路径 | 内容 | 适合复用的层次 |
|---|---|---|
| `D:\contest\Demo\tinyml-main` | TinyML 仓库精简快照 | 文档、模型生成器、Sapphire/TFLM 软件、Hello World 工程 |
| `D:\contest\Demo\tinyml-main\tinyml_hello_world\Ti60F225_tinyml_helloworld` | 完整 Efinity TinyML Hello World | SoC/DDR/AXI/TinyML 集成参考 |
| `D:\contest\Demo\Ti60F225_tinyml_helloworld.bit` | 预生成 bitstream | 仅可作旧工程冒烟测试，不能作为竞赛最终 bitstream |
| `D:\contest\Demo\Ti60F225_IMX219_HDMI_1080P` | 已解压的 MIPI 摄像头到 HDMI 工程 | 视频输入、帧缓存、RAW8/ISP、HDMI 参考 |
| `D:\contest\Demo\Ti60F225_IMX219_HDMI_1080P.zip` | 上述工程的原始压缩包 | 归档；分析和阅读以解压目录为准 |
| `D:\contest\Demo\Ti60_F225_Core_V1.4.pdf` | 2023 年核心板原理图 | 旧板 DDR、晶振、电源、B2B 连接关系 |
| `D:\contest\Demo\Ti60-F225_Button_Board_V1.1_20230915.pdf` | 2023 年扩展板原理图 | 旧板 MIPI/CMOS/LVDS/HDMI/UART 接口关系 |
| `D:\contest\Demo\创建和导出模型`、同名 `.7z` | 模型创建和导出样例 | 理解 TFLite 全整型转换流程 |

`tinyml-main\README.md` 还引用了 `tinyml_vision` 和 `tinyml_hello_world/README.md`，但当前快照中没有这两个目标。因此不能把 README 对实时视觉方案的描述当成已随 Demo 交付的源码。

## 2. 为什么这是两个独立工程

| 项目 | TinyML Hello World | 已解压视频工程 |
|---|---|---|
| 主工程版本 | Efinity `2025.1.110.1.5` | Efinity `2024.2.294` |
| 器件时序模型 | Ti60F225 `I3` | Ti60F225 `C4` |
| RTL 顶层 | `tinyml_soc_top` | `example_top` |
| 外部参考时钟 | 25 MHz 为主 | 24 MHz 系统参考 |
| DDR 用户时钟 | 400 MHz DDR 相位，AXI/SoC 100/300 MHz | 384 MHz DDR 相位、192 MHz core |
| DDR 控制器 | 工程内 soft controller，AXI128 | `DdrCtrl` IP + 视频 `axi4_ctrl` |
| CPU | Sapphire SoC | 无 Sapphire |
| 视频输入/输出 | 无 MIPI、无 HDMI | CSI、DDR、RAW/ISP、HDMI |
| PLL 使用 | 2 个 PLL | 4/4 PLL 全部使用 |

直接拼接会遇到：两个 DDR 控制器争用同一组管脚、两套 PLL 频率冲突、不同 `.peri.xml` 管脚覆盖、不同复位条件、不同 AXI 接口和地址图，以及跨 2023.1/2024.2/2025.1 的生成 IP 兼容风险。

推荐选择一个“壳”后移植子系统：

- 赛题一：以重新生成的竞赛板视频壳为基础，再接入 Sapphire 和推理核；
- 赛题二：以精简后的视频 DDR/显示壳为基础，接入 Sapphire 和 BitBlt；
- 不建议把任何一个旧顶层原封不动作为竞赛最终顶层。

## 3. TinyML Hello World 工程

### 3.1 快速入口

工程根目录：

```text
D:\contest\Demo\tinyml-main\tinyml_hello_world\Ti60F225_tinyml_helloworld
```

关键文件：

| 路径 | 作用 |
|---|---|
| `Ti60F225_tinyml_helloworld.xml` | Efinity 工程、器件、源文件和策略 |
| `Ti60F225_tinyml_helloworld.peri.xml` | PLL、DDR I/O、GPIO 和外围配置 |
| `src\tinyml_soc_top.v` | 系统顶层 |
| `src\source.f` | 手写 RTL 源清单 |
| `src\tinyml\defines.v` | TinyML 算子和并行度配置 |
| `src\tinyml\tinyml_top.v` | Custom Instruction 分流入口 |
| `src\tinyml\tinyml_accelerator.v` | TinyML AXI/CI 封装及受保护核心 |
| `src\ddr3_controller\ddr3_parameter.vh` | DDR 和 AXI 参数 |
| `ip\sapphire_soc\settings.json` | Sapphire SoC 配置 |
| `embedded_sw\sapphire_soc_tinyml\software\standalone` | 六个 RISC-V/TFLM 示例 |
| `outflow\Ti60F225_tinyml_helloworld.res.csv` | 分层资源报告 |
| `outflow\Ti60F225_tinyml_helloworld.place.rpt` | 器件总资源使用率 |
| `outflow\Ti60F225_tinyml_helloworld.timing.rpt` | 最终时序 |
| `outflow\Ti60F225_tinyml_helloworld.warn.log` | 未驱动接口等警告 |

### 3.2 顶层结构和关键行

`src\tinyml_soc_top.v`：

- 顶层声明：第 16 行；
- DDR 上电等待/复位：第 129-133、344-369 行；
- `u_ddr3_top`：第 372-474 行；
- `u_sapphire_soc`：第 486-596 行；
- `u_tinyml_top`：第 599-646 行；
- 三输入 AXI interconnect：第 648-720 行；
- 第 683 行写着“Connect to HyperRAM controller”，但实际连接的是 DDR3，这是过时注释。

实际数据路径：

```text
Sapphire AXI128 -----+
                     +--> axi_interconnect_beta --> DDR3 controller --> DDR3 x16
TinyML AXI128 -------+
未驱动的 DMA S1 ----+

Sapphire Custom Instruction --> tinyml_top --> tinyml_accelerator
```

AXI interconnect 声明了 S0/S1/S2 三个输入；S0 是 Sapphire，S2 是 TinyML，S1 预留给外部 DMA 但没有实例。`outflow\Ti60F225_tinyml_helloworld.warn.log` 第 255-266 行明确报告 `axi_inter_s1_* does not have a driver`。`ip\dma\dma.v` 和两个 hw_accel FIFO 被加入工程，不代表它们已经工作。

### 3.3 RTL 文件作用

| 分组 | 文件 | 作用及是否活动 |
|---|---|---|
| 系统 | `tinyml_soc_top.v` | 活动；统一接入 SoC、TinyML、DDR、AXI |
| TinyML | `tinyml_top.v` | 活动；Custom Instruction bit 9=0 进入 TinyML，bit 9=1 的用户扩展代码被注释 |
| TinyML | `tinyml_accelerator.v` | 活动；AXI128 和 CI 包装，主体为受保护代码 |
| TinyML | `defines.v` | 活动；算子实现模式、并行度、缓存深度 |
| AXI | `axi_interconnect_beta.v`、master/slave coupler、crossbar、arbiter、read/write SFIFO | 活动；SoC/TinyML 共享 DDR |
| DDR | `ddr3_top.v`、`axi4_bus_ctl.v`、`axi_upsizer*`、`lb2_axi_clk.v`、`memory_bus_ctl.v`、`phy_ctl*` | 活动；控制、位宽转换、校准和 PHY |
| 通用 | APB3 wrapper、reset/reset_ctrl、shift register、单双口 RAM、Efinix FIFO wrapper | 部分活动 |
| 图像预处理 | `hw_accel.v`、`nearest_neighbor.v`、`rgb2gray.v`、`pack.v` | 未实例化；文件存在但 bitstream 不含该流水线 |
| 图像 DMA 包装 | `hw_accel_wrapper.v`、`hw_accel_axi4.v`、`Ddr_Read.v`、`Ddr_Write.v` | 未实例化/部分未进 source list |
| 其他 | `axi_full_to_half_duplex.v` | 被列入源清单但未实例化 |

未启用的 `hw_accel` 默认做最近邻缩放、RGB 转灰度和打包，但不能把它当成现有实时视觉通路。它更适合提取算法骨架后单独写 testbench。

### 3.4 SoC、TinyML 和 DDR 配置

`ip\sapphire_soc\settings.json` 的主要配置：

- Sapphire IP 3.2.1；
- 单 RISC-V 核，FPU 关闭；
- 系统 300 MHz、外设 100 MHz；
- I/D Cache 各 4 KiB，OCR 4 KiB；
- Custom Instruction、UART0、SPI0、APB Slave0 开启；
- DDR AXI 数据宽度 128 bit；
- APB bridge `0xF8000000`，OCR `0xF9000000`。

配置中的 DDR size `0xE0000000` 是 CPU 地址窗口，不是物理 DDR 容量。

`src\ddr3_controller\ddr3_parameter.vh` 第 5-23、42-55 行：

- Rank 1、Bank 3 bit、Row 14 bit、Column 10 bit；
- DQ x16、DQS x2；
- AXI ID 4 bit、地址 32 bit、数据 128 bit；
- CL6、CWL5、Burst 8；
- `ASYN_AXI_CLK=0`。

这些物理参数对应 256 MiB DDR3。软件 `embedded_sw\...\linker\default.ld` 第 7 行只配置从 `0x1000` 开始的 128 MiB可用区。

`src\tinyml\defines.v`：

- AXI 128 bit；
- Conv/Depthwise Conv 为 Standard；
- 输入并行度 4、输出并行度 1；
- Lite 并行度 4；
- ADD、LR、FC、MUL、MIN/MAX 为 Standard；
- FC 最大 640；
- Cache 开启，深度 1024。

### 3.5 时钟和时序

`Ti60F225_tinyml_helloworld.peri.xml` 和 `outflow\...pt.rpt` 表明：

- 25 MHz 参考时钟；
- core 100 MHz；
- `i_sysclk` 300 MHz；
- peripheral 100 MHz；
- DDR 多相时钟 400 MHz；
- 工程使用 2 个 PLL；
- MIPI/LVDS 信息为空，没有 HDMI。

时序必须单独看待：

- `outflow\Ti60F225_tinyml_helloworld.timing.rpt` 第 37 行目标约 300 MHz；
- 第 48 行给出最大可能频率 288.268 MHz；
- 第 64、94 行给出 setup slack `-0.136 ns`。

所以“last_run_flow=bitstream、pass”不等于所有时钟已经满足约束。后续可以先把 Sapphire system clock 降到可收敛值，再根据性能实测优化。

### 3.6 资源报告

分层资源来自 `outflow\Ti60F225_tinyml_helloworld.res.csv`：

| 模块 | FF | SRL | ADD | LUT | RAM | DSP |
|---|---:|---:|---:|---:|---:|---:|
| 全工程 | 23,257 | 840 | 5,622 | 27,734 | 145 | 47 |
| DDR3 | 2,621 | 712 | 288 | 3,030 | 22 | 0 |
| Sapphire | 5,613 | 7 | 649 | 4,785 | 51 | 4 |
| TinyML | 14,908 | 121 | 4,648 | 19,171 | 71 | 43 |
| AXI interconnect | 95 | 0 | 18 | 720 | 1 | 0 |

器件总体占用来自 `outflow\Ti60F225_tinyml_helloworld.place.rpt`：

| 资源 | 使用/总量 | 占比 |
|---|---:|---:|
| XLR | 44,027 / 60,800 | 72.41% |
| RAM | 145 / 256 | 56.64% |
| DSP | 47 / 160 | 29.37% |
| GBUF | 10 / 32 | 31.25% |

TinyML 的主要压力是逻辑和 RAM，不是 DSP。赛题一若保留这套 Standard 并行配置，再加入完整视频系统，逻辑余量会很紧。

### 3.7 软件入口

软件根目录：

```text
embedded_sw\sapphire_soc_tinyml\software\standalone
```

包含：`tinyml_ad`、`tinyml_fl`、`tinyml_imgc`、`tinyml_kws`、`tinyml_pdti8`、`tinyml_ypd`。每个应用入口均为 `src\main.cc`。

以 `tinyml_ypd\src\main.cc` 为例：

- 静态输入头文件：第 35-36 行；
- Tensor Arena 约 10 MiB：第 56 行；
- `GetModel`：第 69 行；
- `main()`：第 116 行；
- 把静态数组复制到输入 tensor：第 139-140 行；
- `Invoke()`：第 144 行；
- YOLO 后处理：第 194 行附近。

构建还链接预编译 `common\tinyml_lib.a`。Custom Instruction 软件封装位于 `src\platform\tinyml\ops\ops_api.h` 第 16 行；整数 Conv/FC 分别在 TFLM `reference\integer_ops\conv.h` 第 71 行和 `fully_connected.h` 第 60 行转入硬件驱动。

## 4. 模型生成样例能做什么、不能做什么

关键入口：

- `D:\contest\Demo\tinyml-main\tools\tinyml_generator\README.md`
- `D:\contest\Demo\tinyml-main\model_zoo\README.md`
- `D:\contest\Demo\创建和导出模型`

生成器适合：

- 导入全整型量化 TFLite；
- 分析受支持层并选择 Lite/Standard；
- 估算资源；
- 输出硬件 `defines.v`；
- 输出软件参数和模型 C/C++ 数组。

已明确支持的主要硬件算子是 Conv、Depthwise Conv、FC、Add、Mul、Min/Max。生成器和模型样例不能证明以下内容：

- 任意风格迁移网络都能映射；
- Resize、反卷积、动态 shape、复杂激活或自定义算子已支持；
- 实时摄像头帧能自动送入 TFLM；
- 生成器估算值等于 Efinity 最终 PnR 资源；
- 受保护 TinyML 核可在 Vivado xsim 内部仿真；
- 当前仓库包含 README 所称的完整 `tinyml_vision` 方案。

赛题一必须先用最终 `.tflite` 做逐算子审计：列出输入/输出 shape、量化参数、所有 op、tensor arena、权重和中间特征图峰值，再决定使用官方 TinyML、修改网络，还是自研特定层加速器。

### 4.1 `创建和导出模型` 只是转换冒烟样例

该目录中的两个 Python 脚本需要特别区分：

- `cretate_my_model.py`（文件名本身如此拼写）创建输入为 `192x192x3` 的 Keras 网络，主体只有一个 32 通道、3x3、`same` padding 的 `Conv2D` 和 `LeakyReLU`；权重为随机初始化，没有训练过程、训练数据、风格损失或画质指标。
- `convert.py` 加载 H5，使用 100 份随机数组作为 representative dataset，要求 TFLite built-in INT8、INT8 输入/输出，并导出 `.tflite` 后检查 dtype。

该样例能够证明的只有“H5 模型可以走通一次全整型 TFLite 转换”。它不能证明：

- 随机校准数据能够给真实摄像头图像提供合理量化 scale/zero-point；
- `LeakyReLU` 和当前输出布局一定受 TinyML Generator/加速器支持；
- `192x192x32` 输出可以直接作为 RGB 风格化帧；
- 模型已经训练、具有风格迁移效果或满足实时指标。

适配赛题一时可保留转换脚本的参数框架，但必须替换为真实训练模型和具有代表性的 100～500 张校准图像，并在生成 RTL 前检查每个 TFLite 算子、量化参数和输出张量含义。

## 5. 已解压视频工程

### 5.1 工程结构与快速入口

工程根目录：

```text
D:\contest\Demo\Ti60F225_IMX219_HDMI_1080P
```

实际目录包含 481 个文件，合计约 127.75 MB（十进制；约 121.83 MiB）。主要内容：

```text
Ti60_Demo.xml
Ti60_Demo.peri.xml
Ti60_Demo.pt.sdc
example_top.v
ip/
  csi_rx/
  DdrCtrl/
  dsi_tx/
  FIFO_W48R24/
  R0_FIFO*/
  W0_FIFO*/
src/
  axi/
  cmos_i2c/
  counter/
  dsi/
  hdmi_ip/
  isp/
  lvds/
  ddr_rw_ctrl/
  lcd_driver.v
  lcd_para.v
  lcd_display.v
  PWM/
  crop/
outflow/
work_pnr/
work_pt/
work_syn/
```

分析优先看以下入口，不必先阅读 481 个文件：

| 入口 | 用途 |
|---|---|
| `example_top.v` | 确认真正活动的数据通路和实例 |
| `Ti60_Demo.xml` | 工程版本、器件、顶层和加入工程的源/IP |
| `Ti60_Demo.peri.xml` | PLL、MIPI、DDR 和 HDMI serializer 的 Efinity 外设实现 |
| `ip/csi_rx/settings.json` | CSI RX 的 lane、byte clock、FIFO 等生成参数 |
| `ip/DdrCtrl/settings.json` | DDR3 控制器生成参数 |
| `src/axi/axi4_ctrl.v` | 固定帧写入、读出和四帧轮转逻辑 |
| `src/isp/VIP_RAW8_RGB888.v` | RAW8 Bayer 转 RGB 算法参考 |
| `src/lcd_driver.v`、`src/lcd_para.v` | 视频扫描时序 |
| `src/hdmi_ip/rgb2dvi.v`、`tmds_channel.v` | RGB 到 TMDS 10-bit symbol |
| `outflow/*.res.csv`、`*.place.rpt`、`*.timing.rpt` | 最后一次成功实现的资源和时序证据 |

以下行号均以该解压目录中的文件为准。

### 5.2 工程版本和器件

`Ti60_Demo.xml`：

- 第 2 行：Efinity `2024.2.294`，bitstream flow 为 pass；
- 第 4-6 行：Titanium `Ti60F225`，时序模型 `C4`；
- 第 9 行：顶层 `example_top`；
- 第 10-36 行：RTL 源；
- 第 47-79 行：CSI、DDR、DSI 和 FIFO IP；
- 综合为 Speed，Retiming 关闭。

IP 版本并不统一：

- `ip/csi_rx/settings.json`：CSI2 RX v5.7，由 Efinity 2024.2.294 生成；
- `ip/DdrCtrl/settings.json`：DDR3 soft controller v5.1，由 Efinity 2023.1.150 生成；
- `ip/dsi_tx/settings.json`：DSI TX v5.1，由 Efinity 2023.1.150 生成。

这些生成物应作为参数参考，不应直接搬到竞赛新工程。

### 5.3 传感器身份：目录名正确，SC2210 模块名误标

有效顶层 `example_top.v` 第 658-687 行实例化：

```text
i2c_timing_ctrl_reg16_dat8_wronly
I2C_SC2210_19201080_4Lanes_Config
```

不能仅凭这个名字判定传感器。检查模块内部的实际寄存器写入后，可以确认它是 Sony IMX219 配置：

- `0x30EB` 访问解锁序列；
- `0x0114 = 0x01`，对应 IMX219 的 2-lane 模式；
- `0x0160`～`0x0175` 为帧长、行长、裁剪、输出尺寸和 binning；
- `0x018C = 0x08`、`0x018D = 0x08`，对应 RAW8 输出；
- `0x030x` 为 PLL 配置；
- I²C 地址字节为 `0x20`，即 7-bit 地址 `0x10`。

这些地址和取值可与 [Linux upstream IMX219 driver](https://github.com/torvalds/linux/blob/master/drivers/media/i2c/imx219.c) 中的 IMX219 公共寄存器、lane mode 和 CSI data format 定义交叉核对。因此，工程名 `IMX219` 是实质正确的，错误的是 `I2C_SC2210_19201080_4Lanes_Config` 这个历史遗留文件名/模块名。

因此：

- 该 Demo 的有效配置是 **IMX219、2 Lane、RAW8、1920×1080**；
- 它不能直接初始化赛题一规定的 SC431HAI；
- 不应根据误标模块名把它当作 SC2210 或 4 Lane 工程；
- SC431HAI 的供电、复位、MCLK、I²C 地址、寄存器表、RAW bit depth、lane 数和 MIPI 速率都要从竞赛板资料重新确认。

### 5.4 有效链路是 2 Lane，四 Lane 只是遗留端口

表面上存在三层不一致：

1. 误标的传感器配置模块名写 `SC2210_..._4Lanes`；
2. `example_top.v` 第 906-919 行连接 D0-D3 四组物理 lane；
3. `ip/csi_rx/settings.json` 第 22 行却是 `NUM_DATA_LANE=2`。

但实际配置是自洽的：IMX219 表把 `0x0114` 写成 2-lane 模式，CSI RX 生成参数也是 2 Lane，资源层次只生成两个 lane FSM，最后一次综合警告还显示 lane 2/3 被移除或未连接。顶层的四组端口只是为旧 B2B 四 Lane 接口保留的宽模板。

旧扩展板的 15Pin Raspberry Pi 风格 FPC 也只引出 CLK、MD0、MD1，两 Lane 正好与该工程相符；B2B 扩展接口则另有 RX0-RX3。竞赛适配仍必须以新板连接器和 SC431HAI 模组为准，在 IP Manager 重新生成 lane 数，并用帧号、行长、CRC/ECC 错误和图像完整性验证。

### 5.5 视频数据路径与关键行

`example_top.v`：

- 顶层端口：第 6 行；
- 四个 PLL 锁定共同参与复位：第 377-383 行；
- `DdrCtrl`：第 528-603 行；
- DDR AXI 地址复用：第 611-635 行；
- 误标名称的 IMX219 I²C 配置：第 658-687 行；
- CSI 数据宽度声明：第 823 行；
- active `csi_rx`：第 892-993 行；
- 原 crop 实例：第 1023-1047 行，已注释；
- CSI 数据当前直接连接：第 1065-1068 行；
- 行/帧计数：第 1074-1085 行；
- DDR 帧控制 `axi4_ctrl`：第 1116-1160 行；
- 显示时序：第 1169-1187 行；
- RAW8 Bayer 到 RGB888：第 1195-1213 行；
- 白平衡：第 1220-1235 行；
- 两像素边界裁剪：第 1243-1256 行；
- HDMI `rgb2dvi`：第 1276-1296 行。

有效路径是：

```text
IMX219 2-lane MIPI CSI-2 RAW8
  --> CSI2 RX
  --> DDR 帧写入/读取
  --> RAW8 Bayer to RGB888
  --> 白平衡
  --> 2-pixel border crop
  --> LCD/video timing
  --> rgb2dvi + LVDS serializer
  --> HDMI
```

第 1023-1047 行的 crop 被注释；现有工程没有活动的通用 Resize。赛题一要求的至少 640×480@30 缩放要另做。

`axi4_ctrl` 是固定 1920×1080 帧流控制器，不是通用多主机 DDR fabric，也不是赛题二 BitBlt 引擎。

其实际工作方式是：CSI 侧把 64-bit 像素流经异步 FIFO 组装为 128-bit AXI 写数据，显示侧再把 128-bit AXI 读数据拆成 8-bit RAW 像素。AXI `AWLEN/ARLEN=127`，即每个 burst 为 128 beat；默认规划四个 `2^22` byte（4 MiB）帧槽，并以 frame index 轮转。它没有软件命令、二维 source/destination/stride、alpha、color key 或区域重叠处理能力。

### 5.6 时钟、DDR、MIPI 和 HDMI

视频工程使用 4/4 PLL：

| PLL | 主要输出 |
|---|---|
| System PLL | 96、74.4、148.8、744 MHz |
| DDR PLL | 384 MHz 多相 DDR 时钟、192 MHz core |
| DSI PLL | 48、42、168 MHz |
| LVDS PLL | 48、336 MHz；名为 `clk_27m/clk_54m` 的信号实际为 16/32 MHz |

`rgb2dvi` 以 `ENABLE_OSERDES=0` 实例化，只在 RTL 中生成时钟/数据通道的 10-bit TMDS symbols；真正的四路物理串行器位于 `Ti60_Demo.peri.xml` 的 Efinity LVDS block 中，使用约 744/148.8 MHz。RTL 注释中存在 74.25 MHz 等近似/旧值，应以生成 PLL 和 PT 报告为准。对 Vivado xsim，应验证像素时序和 10-bit symbols，不要试图用该工程直接证明 Efinix LVDS 物理发送。

CSI RX 配置：

- 2 Lane；
- HS Byte Clock 187 MHz；
- control clock 50 MHz；
- discontinuous clock；
- FIFO 2048。

顶层还保留一个看似用于 CSI RX 配置的 AXI-Lite 状态机，但 `r_axi_addr`、`r_axi_wdata`、`r_axi_sel` 只给初值而从未更新，状态机没有真正发出配置事务。最后一次综合警告也报告这些寄存器“never assigned”。当前 CSI IP 实际依赖生成时固化/默认配置，不存在 Sapphire 或其他 CPU 的运行时 CSI 配置。

DDR IP 配置：

- DDR3 soft controller v5.1；
- 384 MHz；
- x16、Rank 1、Bank 3、Burst 8、CL5；
- write leveling 关闭；
- `ROW_WIDTH=16`。

旧核心板实际 DDR 为 MT41J128M16JT-125，TinyML 工程按 Row 14 配置。视频 IP 的 Row 16 与旧板颗粒/另一个官方工程不一致，可能包含旧参数或控制器参数语义差异；必须在目标 Efinity 中按竞赛板实际颗粒重新生成，不能照抄。

DSI TX 虽被加入工程，但 HDMI 是有效显示出口。`example_top.v` 第 1262 行还提示 HDMI 时序与其他 LCD/LVDS/DSI 路径不应同时启用。适配赛题一/二时应删除未使用的 DSI/LVDS/LCD 分支，以释放 PLL、GBUF 和 RAM。

### 5.7 视频资源和时序

`outflow/Ti60_Demo.res.csv`：

| 模块 | FF | SRL | ADD | LUT | RAM | DSP |
|---|---:|---:|---:|---:|---:|---:|
| 全工程 | 4,056 | 557 | 1,061 | 5,487 | 62 | 1 |
| DDR controller | 2,191 | 514 | 472 | 2,451 | 27 | 0 |
| CSI RX | 987 | 0 | 161 | 2,099 | 15 | 0 |
| `axi4_ctrl` | 364 | 42 | 99 | 205 | 16 | 0 |
| Bayer | 253 | 1 | 139 | 206 | 4 | 1 |
| crop | 53 | 0 | 22 | 66 | 0 | 0 |
| `rgb2dvi` | 45 | 0 | 81 | 140 | 0 | 0 |

`outflow/Ti60_Demo.place.rpt`：

| 资源 | 使用/总量 | 占比 |
|---|---:|---:|
| XLR | 8,981 / 60,800 | 14.77% |
| RAM | 62 / 256 | 24.22% |
| DSP | 1 / 160 | 0.62% |
| GBUF | 15 / 32 | 46.88% |
| PLL | 4 / 4 | 100% |

`outflow/Ti60_Demo.timing.rpt` 使用 C4、typical 0～85 ℃、0.95 V ±30 mV 模型；DDR 384.025 MHz、core 192.012 MHz、system 95.997 MHz、pixel 148.810/744.048 MHz、CSI RX clock 166.667 MHz 等已分析时钟的 setup/hold 均为正。最薄的已列 setup 余量约 0.116 ns、hold 余量约 0.026 ns，说明这并不是可随意迁移频率/器件的宽松结果。它只能证明这份 C4 工程的旧实现，不证明竞赛 I3 新板、重生成 IP 或合并后的系统收敛。

该资源表的另一个重要信息是：活动层次中没有 DSI TX、LVDS LCD Resize、Sapphire 或 TinyML。项目 XML 中加入某个源文件/IP，不代表它进入最终层次；判断活动功能应以 `example_top.v` 实例和 `res.csv` 层次为准。

### 5.8 最后一次成功实现与警告的正确解释

`Ti60_Demo.xml`、route/bitstream 报告表明工程最后一次流程成功。但 `Ti60_Demo.err.log` 和 `warn.log` 会累积多次历史运行，不能因为日志中出现旧的 `FrameBoundCrop` 或 `w_rgb_pre_g` 错误，就断定最后一次构建失败。应从最后一个 synthesis/run 分段阅读。

最后一次成功综合仍留下需要适配会话主动清理的警告：

- DDR AXI ID 的实际/形式位宽为 4/8，不应继续依赖隐式补零或截断；
- CSI AXI-Lite 配置寄存器只保留初值，控制状态机没有实际工作；
- lane 2/3、旧 CMOS/DSI/LVDS/LCD 端口被移除、悬空或未驱动；
- `SerialClk` 在 `rgb2dvi` RTL 端未连接，这是 `ENABLE_OSERDES=0`、由 periphery 串行化的结果；
- `axi4_ctrl` 和若干 counter 有位宽截断/扩展警告，重构时要显式定义地址和计数位宽；
- 被注释 crop 相关线网仍有未驱动警告，但不在活动像素路径；
- `design_issue.xml` 还报告 HDMI/LVDS/DSI 附近的三个物理 coupling 风险。

这些问题不妨碍把它当结构参考，但足以说明应创建一个只保留目标接口的干净 I3 工程，不宜在旧顶层上继续堆功能。

### 5.9 现有 testbench 不能作为回归基线

- 根目录 `example_top_tb.v`、`example_top_tb2.v` 来源于更旧的 SC130GS/AR0135 工程，端口与当前顶层不一致，没有有效摄像头/DDR 数据闭环，而且未加入 `Ti60_Demo.xml`；
- `src/axi/axi4_ctrl_tb.v` 不是 self-checking，只提供简化 ready/valid 激励，没有真实 DDR 内容、随机背压或 golden scoreboard；
- `ip/csi_rx/Testbench` 和 `ip/DdrCtrl/Testbench` 的生成脚本面向 ModelSim/Questa 等工具；主工程 `DdrCtrl.v` 还含面向 Questa 的 IEEE-1735 保护块，不能假设 Vivado xsim 能直接展开。

因此两个设计会话都应新建 xsim 自检 testbench：用 CSI/像素流行为源替代 D-PHY，用带随机延迟和背压的 AXI memory model 替代 DDR PHY，用 TMDS symbol/timing checker 替代物理 LVDS serializer。旧 testbench 只能帮助识别历史接口，不能作为“Demo 已仿真通过”的证据。

## 6. 两块旧板原理图的适用边界

### 6.1 Ti60_F225_Core_V1.4 核心板

`D:\contest\Demo\Ti60_F225_Core_V1.4.pdf`，图纸日期 2023-09-14：

- Ti60F225，图纸未明确 C4/I3 后缀；
- 24 MHz 系统晶振和 25 MHz DDR 参考晶振；
- MT41J128M16JT-125，标注 `16M x 16 x 8`，即 2 Gbit/256 MiB DDR3 x16；
- DDR A0-A13 为实际颗粒地址，板上还布出 A14/A15 相关网名，不能据此把颗粒配置成 Row 16；
- 8 个 LED、JTAG、配置 Flash、P1/P2 B2B；
- Bank 3A 标注 1.2 V 用于 MIPI，普通 GPIO/其他 Bank 还有 1.8/3.3 V 配置关系。

它可以说明旧 Demo 为什么有 24/25 MHz、x16 DDR 和 P1/P2 信号，但不能代替竞赛新板的原理图、pinout、Bank 电压和器件速度等级。

### 6.2 Ti60-F225 Button Board V1.1

`D:\contest\Demo\Ti60-F225_Button_Board_V1.1_20230915.pdf`，图纸日期 2023-09-15/16：

- 电源：5 V、3.3 V、1.8 V 和 3.3 V sensor rail；
- 并行 CMOS 20Pin 接口；
- Raspberry Pi 风格 15Pin MIPI FPC，只引出两条数据 lane；
- B2B 扩展引出 MIPI RX/TX D0-D3；
- 7 英寸 LVDS LCD 接口；
- HDMI Type-A；
- CH340N USB-UART；
- TXS0108 等电平转换；
- 原理图明确 Bank 2A/2B 为 1.8 V、Bank 3A 为 1.2 V MIPI，MIPI control 为 1.8 V；
- DC3-40 用户接口默认 3.3 V，改电平涉及跳线/0 欧电阻和 FPGA I/O 方向约束。

这解释了旧视频 Demo 同时存在 CMOS、MIPI、DSI、LVDS 和 HDMI 分支，也说明旧工程不能默认匹配竞赛新板接口。尤其不要把旧板 15Pin 两 Lane 接口、B2B 四 Lane 接口和竞赛 SC431HAI 模组混为一谈。

### 6.3 C4 旧工程与竞赛 I3 的差异

更正版赛题指南把赛题一至三平台写为 Ti60F225I3。已解压视频工程则是 C4；旧核心板原理图只写 Ti60F225，不给速度后缀。必须按以下原则迁移：

- 新建/转换工程目标器件为竞赛板确切 I3 型号；
- 不复用 C4 的 final timing 数字作为设计余量；
- 根据新板原理图重新建立 pin assignment、I/O standard、Bank 电压和 MIPI/DDR primitive；
- 按新板晶振确认 PLL 输入，不能因旧板有 24/25 MHz 就直接假设新板相同；
- 所有 DDR、MIPI、LVDS/HDMI IP 在同一 Efinity 版本重新生成并重新 PnR/STA。

## 7. 复用矩阵

| Demo 组件 | 赛题一 | 赛题二 | 复用方式 | 主要限制 |
|---|---|---|---|---|
| Sapphire SoC 配置 | 高 | 高 | 参考 CPU/cache/UART/APB/DDR AXI 配置，重新生成 | 300 MHz 未收敛；地址图要重做 |
| Custom Instruction | 中 | 低/可选 | 题一推理 doorbell；题二可作快速 doorbell | 不能替代 AXI4 数据通路 |
| TinyML accelerator | 中到高，需模型审计 | 无 | 只有模型受支持且资源允许时使用 | 加密、xsim 不透明、算子有限 |
| TinyML Generator | 高 | 无 | 模型算子审计、参数和资源初估 | 仅全整型 TFLite，估算非 PnR |
| TFLM 软件骨架 | 高 | 低 | 初始化、Invoke、UART/BSP | 当前输入是静态数组 |
| AXI128 interconnect | 中 | 中 | 参考多主共享 DDR | 现有 S1 未驱动，需 QoS/仲裁重构 |
| TinyML DDR3 controller | 中 | 中 | 参数/校准流程参考 | 与视频 DDR 只能二选一并重生成 |
| CSI2 RX/PHY | 高 | 无 | 赛题一重新按 SC431HAI/lane/RAW 配置 | 当前 Demo 固定为 IMX219 2 Lane RAW8 |
| 误标名称的 IMX219 I²C 表 | 无 | 无 | 只复用 I²C 时序控制框架，不复用寄存器值 | 不是 SC431HAI 配置 |
| RAW8 Bayer/白平衡 | 中 | 无 | 传感器输出确为相同 Bayer/bit depth 时复用 | SC431HAI RAW 位深和 pattern 要重核 |
| crop | 低 | 无 | 边界裁剪参考 | 不是 Resize，且主要实例被注释 |
| 视频 DDR `axi4_ctrl` | 中 | 中 | 帧写入/scanout 时序参考 | 固定 1080p，不是通用 AXI fabric/BitBlt |
| LCD/video timing | 高 | 高 | 参数化后用于 HDMI timing | 注意实际像素时钟和同步极性 |
| `rgb2dvi`/LVDS serializer | 高 | 高 | 板级 HDMI 输出骨架 | 强依赖 Efinity primitive、PLL 和管脚 |
| DSI/LVDS LCD 分支 | 无 | 无 | 删除以释放资源 | 占 PLL/GBUF，和 HDMI 时序冲突 |
| 旧 `.peri.xml`/pinout | 仅参考 | 仅参考 | 查信号角色 | 禁止整份复制到 I3 新板 |
| C4 timing/bitstream | 无 | 无 | 只作旧工程证据 | 不适用于 I3 |

## 8. 赛题一适配路线

目标是把“摄像头视频系统”和“模型推理系统”在同一 DDR、同一时钟计划和同一软件调度下闭环。

### 阶段 A：先证明竞赛板基础设施

1. 确认竞赛板 I3 精确器件、晶振、DDR 颗粒、SC431HAI 接口和 HDMI 连接；
2. 选定统一 Efinity 版本，新建 I3 工程，不在 C4 工程上仅改器件下拉框；
3. 重生成 PLL、DDR3、CSI RX、HDMI/LVDS serializer；
4. 先做 LED/UART、DDR calibration/BIST、HDMI color bars；
5. 每项都独立保留可回退的板测工程和报告。

退出条件：DDR 长时间读写无错，HDMI 固定图案稳定，所有目标时钟在 I3 上收敛。

### 阶段 B：SC431HAI 输入

1. 获取官方 SC431HAI 模组寄存器表和上电时序；
2. 确认 lane 数、RAW8/10/12、Bayer pattern、分辨率、帧率和 MIPI byte clock；
3. 用可读寄存器、帧/行计数、CSI CRC/ECC 错误确认配置，不只看“屏幕有图”；
4. 先绕开 DDR，把 CSI 输出送测试统计/片上小缓存；
5. 再接 DDR ping-pong 帧写入。

退出条件：连续帧行长、帧长和像素格式符合预期，无稳定性错误。

### 阶段 C：视频预处理

1. 按传感器实际 RAW 格式实现 Bayer/RGB；
2. 单独实现至少 640×480@30 的 Resize，不把 crop 冒充缩放；
3. 统一 TinyML 输入格式、通道顺序、INT8 零点/scale 和归一化；
4. 用 Python/软件 golden 对 RAW、RGB、Resize、量化结果逐帧/逐像素比较；
5. 决定预处理放在流式链路还是 DDR reader 后。

### 阶段 D：模型可实现性闸门

1. 将候选风格迁移 `.tflite` 输入 TinyML Generator；
2. 导出完整 op/shape/量化列表，标出不支持算子；
3. 估算权重、中间 tensor、DDR 带宽和 Tensor Arena；
4. 先用离线静态图片复现软件输出；
5. 再用 TinyML bit-accurate/板上输出验证；
6. 若算子或资源不适合，立即选择轻量化网络、替代算子或自研关键层，而不是拖到全系统集成后才发现。

### 阶段 E：统一 DDR 和 AXI

推荐统一结构：

```text
CSI frame writer ----+
TinyML AXI master ----+--> one AXI fabric --> one DDR3 controller --> DDR3
HDMI frame reader ----+
Sapphire CPU ---------+
```

需要明确：

- 输入/输出双缓冲地址和对齐；
- CPU、CSI、推理、显示四个主机的优先级；
- HDMI reader 的实时保障和欠载策略；
- burst 长度、4 KiB 边界、AXI ID 和响应错误；
- 推理完成/帧完成中断和 ownership；
- 跨时钟 FIFO 与复位释放顺序。

### 阶段 F：资源和时钟收敛

TinyML 与视频报告简单相加约为：

- XLR：87.18%；
- RAM：80.86%；
- DSP：29.99%；
- GBUF：78.13%。

这只是上限感知，不是最终预测，因为统一 DDR/PLL 会去重，但 Resize、格式转换、AXI fabric 和调度又会新增资源。优先措施：

- 删除 DSI/LVDS LCD、旧 sensor、未实例化 DMA 和无关 FIFO；
- 只保留一套 DDR controller；
- 评估 TinyML Lite/较低并行度；
- 减小非关键 FIFO/cache；
- 共享或重新规划 PLL，不保留视频工程 4/4 PLL；
- 把 300 MHz Sapphire 降到能在 I3 收敛的频率；
- 每加入一个子系统就查看 Efinity `res/place/timing/cdc`，不要到最后一次性综合。

## 9. 赛题二适配路线

赛题二不需要摄像头和 TinyML。官方视频 Demo 最有价值的是“DDR 帧缓存到 HDMI”，TinyML Demo 最有价值的是“Sapphire 到 AXI/DDR”。

### 阶段 A：裁出显示最小系统

1. 从视频结构中保留 DDR、frame reader、video timing、`rgb2dvi` 和 HDMI serializer；
2. 删除 CSI、误标名称的 IMX219 I²C、Bayer、白平衡、DSI 和无关 LVDS LCD；
3. 将固定 1920×1080 参数化到赛题最低 640×480@60；
4. 重新生成 I3 的 PLL、DDR 和 HDMI 外围；
5. 用 DDR 中固定色条/棋盘格验证 scanout。

### 阶段 B：接入 Sapphire

1. 重生成 Sapphire，确认 AXI4/AXI4-Lite/APB 的实际接口；
2. 建立明确内存图：程序、framebuffer0/1、sprite/source、命令区；
3. CPU CSR 控制走 AXI4 体系，像素数据走 AXI4 Full burst；
4. Custom Instruction 只可作为 doorbell/快速状态，可不用，不能替代题目要求的 AXI4。

### 阶段 C：接入 BitBlt 引擎

视频 Demo 的 `axi4_ctrl` 只能作 scanout/固定帧搬运参考，不能直接充当渲染器。BitBlt 至少要补：

- 命令 FIFO/解析；
- Solid Fill、Block Copy；
- 源/目标 stride、矩形边界；
- 行级 AXI burst 读写；
- 内部读 FIFO/行缓存；
- 双缓冲和 vblank page flip；
- 完成/错误/性能寄存器；
- 高阶 Alpha、Color Key。

### 阶段 D：统一 DDR 仲裁

```text
Sapphire CPU ---------+
BitBlt source reader --+
BitBlt writer ---------+--> AXI arbiter/fabric --> one DDR3 controller
HDMI scanout reader ---+
```

显示读应具有可证明的实时保障。验证随机背压、AW/W 独立到达、AR/R burst、B response、WSTRB、4 KiB 边界、不同 ID、读写交叉和 scanout 欠载。

### 阶段 E：软件和演示闭环

1. 编写 RISC-V C 驱动：命令构造、提交、等待/中断、错误读取；
2. CPU 软件 Fill/Copy 和硬件 Fill/Copy 使用同一场景；
3. 渲染 inactive page，等待完成，在 vblank 翻页；
4. 屏上实时显示 CPU FPS 和 FPGA FPS；
5. 高阶再加入 Alpha、Color Key 和 Sprite 压力测试。

赛题二纯 RTL 和 AXI 功能大多可在 xsim 完成；最终板卡阶段主要解决 DDR calibration、实际 AXI 时钟/位宽、HDMI serializer/管脚、PnR 时序和软件 BSP。

## 10. Vivado xsim 验证策略

### 10.1 xsim 应负责的部分

- 纯 RTL 图像算法：Bayer、RGB/灰度、Resize、格式打包、BitBlt/Alpha/Color Key；
- AXI 协议 wrapper、仲裁、burst 拆分、4 KiB 边界、背压和错误响应；
- 帧地址、stride、双缓冲、vblank page flip；
- 跨时钟 FIFO 的通用 RTL 或行为模型；
- 视频 timing、DE/HS/VS、像素序列和分辨率；
- RISC-V 软件不可用时，用 CSR/CI BFM 模拟命令提交；
- 赛题一调度时，用 TinyML transaction model 模拟“读输入帧、延迟、写输出帧、完成中断”。

### 10.2 需要行为替身的 Efinix 内容

建议建立统一 wrapper，xsim 选择 behavioral model，Efinity 选择真实 IP：

| Efinity 内容 | xsim 替身 |
|---|---|
| PLL/GBUF | 普通时钟发生器、可控 `locked` |
| DDR3 PHY/controller | AXI memory model + calibration delay/error injection |
| MIPI D-PHY/CSI RX | RAW pixel/packet source，必要时建 packet-level BFM |
| LVDS/TMDS serializer | 在 serializer 前检查 10-bit symbol 或 RGB/DE/HS/VS |
| Sapphire | AXI/CSR/CI BFM；软件联调留给 Efinity BSP/板卡 |
| 受保护 TinyML accelerator | transaction-level 模型或预计算 golden 输出 |

不要把 Efinity `.peri.xml`、加密 primitive 或整份 post-layout netlist硬塞给 xsim 后，以“能否编译”判断算法 RTL 的正确性。

### 10.3 赛题一 xsim 分层

1. RAW 帧文件/生成器 → Bayer golden；
2. RGB → Resize → INT8 输入，与软件逐像素比较；
3. 预计算模型输出或 TinyML transaction model；
4. 输出反量化/格式化 → framebuffer；
5. framebuffer → HDMI timing scoreboard；
6. 随机 DDR latency/backpressure 下验证无越界、无死锁、无撕裂协议错误；
7. 最后才接 Efinity CSI/DDR/TinyML/HDMI IP 和板卡。

### 10.4 赛题二 xsim 分层

1. 每个命令对小尺寸内存做 golden 比较；
2. 覆盖重叠 copy、非对齐、stride、零尺寸、边界、Alpha 0/255、Color Key 命中/未命中；
3. 将抽象内存替换为 AXI BFM，随机通道背压；
4. renderer 与 display reader 同时访问，验证仲裁和显示优先；
5. 运行多帧 page flip，检查只在 vblank 生效；
6. 在仿真中计算命令周期和理论带宽，但把最终 FPS 标为“板上待测”。

### 10.5 xsim 不能证明的内容

- I3 的最终布局布线和时序；
- DDR PHY 校准、板级 SI 和长时间稳定性；
- MIPI lane 交换、极性、D-PHY margin、CRC/ECC；
- HDMI PLL/LVDS serializer 和不同显示器兼容性；
- 受保护 TinyML 核内部算子正确性；
- Efinity 资源打包、DSP 合并和 GBUF/PLL 可用性；
- RISC-V BSP、下载、缓存一致性和真实中断延迟。

## 11. 禁止直接复制的项目

以下内容只能读参数/结构，不能原样进入竞赛最终工程：

1. 已解压视频工程的整份 `Ti60_Demo.peri.xml`、pinout、C4 timing 和 bitstream；
2. TinyML 工程的整份 `.peri.xml`，尤其是未确认的新板 DDR/Bank/clock 管脚；
3. 误标为 SC2210 的 IMX219 寄存器表，用于 SC431HAI；
4. 仅根据四 Lane 顶层端口或误标模块名推断最终 lane 数；该 Demo 的有效配置已经确认是 2 Lane，但赛题一仍需核实 SC431HAI；
5. 视频 `DdrCtrl ROW_WIDTH=16`；旧核心板 MT41J128M16 的有效 Row 参数应按实际颗粒/IP 重新选择；
6. 两个工程的 DDR controller 同时实例化；
7. C4 timing pass 作为 I3 timing pass；
8. TinyML 的 bitstream pass 作为 300 MHz 时序通过；
9. TinyML top 第 683 行的 HyperRAM 注释；当前 Demo 没有活动 HyperRAM 系统；
10. `ip\dma`、hw_accel FIFO 或 `hw_accel` 源文件存在，作为“DMA/预处理已接通”的证据；
11. `0xE0000000` DDR 映射窗口，作为 3.5 GiB 物理容量；
12. 视频 `axi4_ctrl` 作为通用 AXI fabric 或 BitBlt；
13. crop 作为 Resize；
14. 静态输入 `main.cc` 作为实时摄像头软件；
15. TinyML Generator 的资源估计作为最终 Efinity 资源；
16. 混用 2023.1、2024.2、2025.1 生成 IP 而不重新生成和回归；
17. 旧扩展板的 15Pin MIPI、4-lane B2B、电平跳线和新竞赛板接口互相替代；
18. 任何旧板引脚、电压和复位极性，未查新板原理图就直接约束。

## 12. 快速检查清单

### 两个会话共同检查

- [ ] 已确认最终目标器件是竞赛板确切 `Ti60F225I3`；
- [ ] 已选定一个统一 Efinity 版本；
- [ ] 所有关键 IP 在该版本重新生成；
- [ ] 最终工程只有一个顶层、一个 `.peri.xml`、一个 DDR controller；
- [ ] 已确认竞赛板晶振频率和 PLL 输入；
- [ ] 已按新板原理图核对每个 Bank 电压和 I/O standard；
- [ ] 已区分物理 DDR 容量、CPU 映射窗口和 linker 可用区；
- [ ] 已定义统一地址图和 framebuffer 对齐；
- [ ] 已定义 reset/calibration/PLL locked 的释放顺序；
- [ ] 已保留纯 RTL/xsim 配置和 Efinity/IP 配置两个构建入口；
- [ ] 已对 AXI 随机背压、4 KiB 边界和错误响应做自检；
- [ ] 已查看 Efinity `res/place/timing/cdc`，不是只看 bitstream 是否生成。

### 赛题一额外检查

- [ ] 已获取 SC431HAI 正式寄存器表和上电时序；
- [ ] 已确认 2/4 Lane、RAW 位深、Bayer pattern 和 byte clock；
- [ ] 已实现真正 Resize，不是 crop；
- [ ] 已用软件 golden 验证 RAW→RGB→Resize→INT8；
- [ ] 已逐算子审计风格迁移 TFLite；
- [ ] 已证明模型不是依赖缺失的 `tinyml_vision` 文件；
- [ ] 已规划 CSI/TinyML/HDMI/CPU 的 DDR 仲裁；
- [ ] 已在资源预算中计入 Resize、AXI fabric、FIFO 和格式转换；
- [ ] 已释放视频 Demo 无关 DSI/LVDS PLL；
- [ ] 已把 TinyML 300 MHz 负裕量纳入降频/优化计划。

### 赛题二额外检查

- [ ] 已从视频系统删除 CSI、IMX219 I²C、Bayer、白平衡和 DSI；
- [ ] 已把显示参数切换并验证到至少 640×480@60；
- [ ] BitBlt 控制属于 AXI4 体系，DDR 像素数据为 AXI4 Full burst；
- [ ] Solid Fill/Block Copy 都是行级 burst，并有读 FIFO/行缓存；
- [ ] 双缓冲只在 vblank page flip；
- [ ] 显示 reader 有实时优先级和 underflow 计数；
- [ ] RISC-V C 驱动、CPU/HW FPS 对比和屏显均有实施计划；
- [ ] Alpha/Color Key 作为高阶功能与基础闭环分阶段完成。

## 13. 建议的第一天阅读顺序

### 赛题一会话

1. `D:\contest\Demo\tinyml-main\README.md`
2. `D:\contest\Demo\tinyml-main\tools\tinyml_generator\README.md`
3. `...\Ti60F225_tinyml_helloworld\src\tinyml_soc_top.v:372-720`
4. `...\src\tinyml\defines.v`
5. `...\ip\sapphire_soc\settings.json`
6. `...\outflow\Ti60F225_tinyml_helloworld.res.csv`
7. `...\outflow\Ti60F225_tinyml_helloworld.timing.rpt:37-64`
8. `D:\contest\Demo\Ti60F225_IMX219_HDMI_1080P\example_top.v:528-1296`
9. `D:\contest\Demo\Ti60F225_IMX219_HDMI_1080P\ip\csi_rx\settings.json`
10. 两份旧板 PDF 的核心板第 2/5/6/7 页、扩展板第 3/5/7 页

### 赛题二会话

1. `D:\contest\Demo\Ti60F225_IMX219_HDMI_1080P\example_top.v:528-635`，理解 DDR；
2. 同一文件第 1116-1296 行，理解 frame reader/时序/HDMI；
3. 解压工程中的 `src\axi`、`src\ddr_rw_ctrl`、`src\lcd_driver.v`、`src\lcd_para.v`、`src\hdmi_ip`；
4. TinyML `src\tinyml_soc_top.v:486-720`，理解 Sapphire/AXI/DDR；
5. `ip\sapphire_soc\settings.json` 和生成的 `source/soc_config`；
6. `outflow\Ti60F225_tinyml_helloworld.warn.log:255-266`，避免复制未驱动 AXI S1；
7. 旧板 PDF 的 HDMI、DDR、晶振页，仅用于理解旧 Demo；
8. `resource\官方补充资料概括与赛题二差异分析.md`，核对赛题二 AXI4/DDR3/HDMI 必做边界。

## 14. 最终选择建议

- 若赛题一使用官方 TinyML 核，应尽早把“模型是否支持、资源是否够、受保护 IP 如何验证”设为选题闸门。仅完成视频 Demo 适配并不等于完成风格迁移。
- 赛题二与现有纯 RTL/xsim 流程匹配度更高。可先在 xsim 完成 BitBlt、AXI、双缓冲和 timing 的大部分验证，再把官方 Demo 缩减为 I3 的 DDR+HDMI 壳。
- 两题最终都需要 Efinity 和板卡，但依赖程度不同：赛题一的 MIPI、TinyML、模型性能和多主 DDR 集成使板级关键路径更多；赛题二的算法/协议可离线验证得更完整，板级主要集中在 Sapphire、DDR 和 HDMI 收口。
