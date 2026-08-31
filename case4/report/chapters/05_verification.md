## 5 仿真验证与资源评估

### 5.1 验证基准与图像回归

本项目将算法数值、流接口行为和器件映射分开验证。Python Golden 用于确定灰度、中值、Sobel 梯度、阈值及叠加的整数参考结果；RTL 测试平台按输出坐标读取参考值，检查已产生的有效输出；综合报告用于观察指定器件上的逻辑和存储映射。这三类证据对应不同问题：软件图像结果不能代替 RTL 比较，功能仿真通过也不能证明目标器件上的时序已经收敛。[3][5][6]

2026 年 8 月 31 日通过[报告复核脚本](D:/contest/2026FPGA/yilingsi/case4/report/verification/run_report_checks.ps1)重新运行了 5 项 Golden 检查、两种像素格式的定点灰度穷举和 12 个既有 XSIM 测试顶层。该次运行使用 Vivado 2023.1，仿真产物与日志独立保存在报告验证目录中；本章所述本轮通过结论均以该目录的原始输出为依据，没有重新运行综合。[Golden 检查日志](D:/contest/2026FPGA/yilingsi/case4/report/verification/golden_tests.log)记录了黑白灰度极值、水平与垂直阶跃的梯度符号和幅值、分组差分重构、单点脉冲中值结果以及阈值单调性和有效区域尺寸共 5 项通过结果。其覆盖的是指定断言，不是所有输入与边界条件的完整证明。[3][5]

图像回归采用 Cameraman、Lena 灰度图、Lenna 彩色图、Mandrill 和 Peppers，并保留棋盘格、斜坡、单点脉冲和方块等合成输入。图像来源见[来源记录](D:/contest/2026FPGA/yilingsi/case4/image_sources.md)；[图像回归脚本](D:/contest/2026FPGA/yilingsi/case4/run_regression.py)对经典图像分别生成无中值和加入中值的结果，统一使用阈值 320。现有输出包含定点灰度、滤波图、梯度、幅值、边缘图、叠加图和有效掩码，适合追踪某一像素从输入到输出的变化，但这些既有图像产物不属于本轮重新生成的结果。[3][9]

既有 Mandrill 记录中，无中值与加入中值的非零边缘像素数分别为 28,038 和 7,489，见[无中值数据](D:/contest/2026FPGA/yilingsi/case4/outputs/mandril_color/no_median/metrics.json)和[中值数据](D:/contest/2026FPGA/yilingsi/case4/outputs/mandril_color/median/metrics.json)。Cameraman 的对应数量为 10,513 和 8,999，见[无中值数据](D:/contest/2026FPGA/yilingsi/case4/outputs/cameraman/no_median/metrics.json)和[中值数据](D:/contest/2026FPGA/yilingsi/case4/outputs/cameraman/median/metrics.json)。这些数字说明同一阈值下两条算法链产生的边缘数量不同，不能据此判定哪条链具有更高检测准确率。两条链的有效区域也不同，512×512 输入下分别为 260,100 和 258,064 个像素；现有 `edge_density` 使用整幅图像作为分母，包含置零边界。因此，后续进行滤波对照时还需统一比较区域，并区分被抑制的是噪声响应还是所需细节。[3][9]

图 5-1 给出既有 Peppers 回归的输入与两条路径输出。三幅图均为512×512，边缘阈值为320；基础路径比较范围为内部510×510，中值路径为内部508×508，数组外侧无效位置显示为黑色。图中可观察到轮廓及局部纹理响应的差异，但没有使用标注真值评估优劣。该图来自Python Golden的既有输出，不是RTL输出或实板照片。[3][9]

| （a）输入图像 | （b）灰度后Sobel | （c）中值后Sobel |
|---|---|---|
| ![Peppers输入图像](D:/contest/2026FPGA/yilingsi/case4/outputs/peppers/no_median/input_rgb.png) | ![Peppers基础Sobel边缘](D:/contest/2026FPGA/yilingsi/case4/outputs/peppers/no_median/edge.png) | ![Peppers中值后Sobel边缘](D:/contest/2026FPGA/yilingsi/case4/outputs/peppers/median/edge.png) |

图 5-1 Peppers图像的Python Golden边缘处理示例。输入来源见参考资料[9]，原始参数分别见[基础路径记录](D:/contest/2026FPGA/yilingsi/case4/outputs/peppers/no_median/metrics.json)和[中值路径记录](D:/contest/2026FPGA/yilingsi/case4/outputs/peppers/median/metrics.json)。

### 5.2 定点灰度误差与输入域覆盖

定点灰度验证采用第3章定义的连续加权参考值，以定点整数输出与该参考值之差的绝对值作为误差。[穷举脚本](D:/contest/2026FPGA/yilingsi/case4/verify_fixed_gray.py)遍历全部 RGB565 码字，并按位复制展开为 RGB888；RGB888 则按 R 通道分块遍历全部三通道组合。这一分块方式改变内存占用，不减少输入组合数量。本轮[量化结果](D:/contest/2026FPGA/yilingsi/case4/report/verification/fixed_gray_report.json)与既有报告的数值一致，结果列于表 5-1。[8]

表 5-1 定点灰度全输入域穷举结果

| 输入格式与参考域 | 样本数 | 最大连续误差/LSB | 平均绝对连续误差/LSB | 与舍入参考的最大码差 | 舍入后不一致样本数 |
|---|---:|---:|---:|---:|---:|
| RGB565 位复制展开后的 RGB888 | 65,536 | 0.931 | 0.277799 | 1 | 9,218 |
| RGB888 全部组合 | 16,777,216 | 0.945 | 0.276317 | 1 | 2,243,412 |

在上述输入域和参考定义下，最大连续误差均小于 1 LSB；该结论包含定点系数近似和输出取整造成的误差，但不包含源图像压缩为 RGB565 时已发生的颜色量化损失。脚本还将连续参考经 `np.rint` 舍入后作比较，两种独立取整的结果可能落在半码边界两侧，因此“连续误差小于 1 LSB”并不等于“与舍入后的浮点结果逐码相同”。表中的非零不一致样本数与连续误差结论并不矛盾。[8]

数值公式的穷举与 RTL 输入覆盖也应分开表述。[灰度测试平台](D:/contest/2026FPGA/yilingsi/case4/tb/tb_gray_rgb.sv)向 RGB565 实例送入全部 65,536 个码字，同时向 RGB888 实例送入这些码字展开后的对应颜色，并检查灰度值、累加值、坐标与行帧标记。该测试完成了 RGB565 路径的全码字检查，却只覆盖 RGB888 全域中的 65,536 种颜色；RGB888 的 16,777,216 组合穷举属于 Python 数学实现层面的证据，尚不是 RTL 全域穷举。[5][8]

### 5.3 RTL 逐输出比较与大帧计数

小帧测试采用 8×6 的确定性输入，使每个有效窗口的 9 个像素都可由坐标直接索引。算子测试分别检查窗口抽头、中值、Sobel、阈值、RGB888/RGB565 叠加和 8 位边缘扩展；其中中值与 Sobel 由同一原始窗口分别驱动，不能把该算子测试当作中值后 Sobel 的级联验证。级联功能由独立的中值—Sobel 测试平台验证，先计算整幅中值参考，再对其内部窗口计算梯度。基础链产生 24 个有效结果，级联链产生 8 个有效结果，分别对应 `(8−2)×(6−2)` 和 `(8−4)×(6−4)`。[5]

跨语言比较由[HEX 测试平台](D:/contest/2026FPGA/yilingsi/case4/tb/tb_hex_core.sv)读取既有 Python Golden 向量，比较 48 个灰度输出和 24 个有效位置的Gx、Gy、L1 幅值及边缘位。向量的[元数据](D:/contest/2026FPGA/yilingsi/case4/tb/vectors/metadata.json)限定了 8×6、阈值 100、无中值这一配置。它使软件参考与硬件实现之间形成可追踪的逐码对照，但尚未覆盖真实图像全帧，也没有覆盖中值级联的大帧逐码比较。[3][5]

表 5-2 本轮 XSIM 测试及其实际检查范围

| 测试对象 | 检查范围 | 本轮结果与日志 |
|---|---|---|
| 灰度前端 | 全部 RGB565 码字及对应展开 RGB888；灰度、累加值、侧带信号、结束空拍 | 通过，[灰度日志](D:/contest/2026FPGA/yilingsi/case4/report/verification/tb_gray_rgb.log) |
| 独立图像算子 | 8×6；窗口、中值、Sobel、阈值、叠加及边缘扩展数值 | 通过，[算子日志](D:/contest/2026FPGA/yilingsi/case4/report/verification/tb_image_operators.log) |
| 基础集成核心 | 8×6；参考后端 RGB888 格式灰度输入、RGB565 彩色输入及 XPM 后端 RGB888 格式灰度输入 | 均通过，[参考后端](D:/contest/2026FPGA/yilingsi/case4/report/verification/tb_gray_sobel_core.log)、[RGB565](D:/contest/2026FPGA/yilingsi/case4/report/verification/tb_gray_sobel_core_565.log)、[XPM 后端](D:/contest/2026FPGA/yilingsi/case4/report/verification/tb_gray_sobel_core_xilinx_bram.log) |
| Python—RTL 向量对照 | 8×6；48 个灰度结果、24 个有效 Sobel 和阈值结果 | 通过，[HEX 日志](D:/contest/2026FPGA/yilingsi/case4/report/verification/tb_hex_core.log) |
| XPM 窗口 | 8×6；9 个抽头及输出坐标索引对应、预期位置的行帧标记 | 通过，[窗口日志](D:/contest/2026FPGA/yilingsi/case4/report/verification/tb_window3x3_gray_xilinx_bram.log) |
| 中值—Sobel 级联 | 8×6；8 个有效结果的数值、坐标范围及预期位置的行帧标记 | 均通过，[参考后端](D:/contest/2026FPGA/yilingsi/case4/report/verification/tb_gray_median_sobel_core.log)、[XPM 后端](D:/contest/2026FPGA/yilingsi/case4/report/verification/tb_gray_median_sobel_core_xilinx_bram.log) |
| 基础核心大帧 | 640×480；304,964 个输出、有效限定、坐标范围和末坐标 | 均通过，[参考后端](D:/contest/2026FPGA/yilingsi/case4/report/verification/tb_gray_sobel_core_640.log)、[XPM 后端](D:/contest/2026FPGA/yilingsi/case4/report/verification/tb_gray_sobel_core_xilinx_bram_640.log) |
| XPM 中值级联大帧 | 640×480；302,736 个输出、有效限定、坐标范围、末坐标及预期位置的行帧标记 | 通过，[级联大帧日志](D:/contest/2026FPGA/yilingsi/case4/report/verification/tb_gray_median_sobel_core_xilinx_bram_640.log) |

640×480 测试连续输入一帧确定性彩色斜坡，随后送入空拍排空流水线。基础链输出区域为 638×478，共 304,964 个有效窗口；中值级联输出区域为 636×476，共 302,736 个有效窗口。上述计数与两条链的 VALID 几何关系一致，可以检查真实行宽下是否出现输出数量、范围或末坐标异常。[基础大帧测试平台](D:/contest/2026FPGA/yilingsi/case4/tb/tb_gray_sobel_core_640.sv)没有比较每个位置的梯度或边缘值，也未对行帧标记作断言；[中值大帧测试平台](D:/contest/2026FPGA/yilingsi/case4/tb/tb_gray_median_sobel_core_640.sv)增加了预期位置的标记存在性检查，但仍不是完整的坐标唯一性和逐拍时序断言。因此，本轮结果支持既定连续输入场景下的大帧功能检查，不扩展为任意输入节奏、所有标记组合或实图全帧逐码一致性证明。[5]

### 5.4 Xilinx OOC 资源与时序边界

资源评估引用 2026 年 8 月 23 日的既有 Vivado 2023.1 独立模块综合报告。综合目标为 `xc7a35tcpg236-1`，顶层分别为基础 Sobel 核心和中值—Sobel 级联核心，采用默认 640×480、RGB565 参数及 Xilinx XPM 行缓存。两份报告的设计状态均为 `Synthesized`，资源范围只包含所选算法核心，不含摄像头、显示、跨时钟域或 DDR 控制系统。原始结果见[基础资源报告](D:/contest/2026FPGA/yilingsi/case4/rtl/core_xilinx_bram_utilization_xilinx.rpt)与[级联资源报告](D:/contest/2026FPGA/yilingsi/case4/rtl/core_xilinx_bram_median_utilization_xilinx.rpt)。[6]

表 5-3 既有 Xilinx OOC 综合资源结果

| 核心配置 | Slice LUT | Slice FF | RAMB18E1 | Block RAM Tile | DSP |
|---|---:|---:|---:|---:|---:|
| 灰度—Sobel—阈值 | 296 | 404 | 2 | 1 | 0 |
| 灰度—中值—Sobel—阈值 | 822 | 610 | 4 | 2 | 0 |

加入中值后增加 526 个 Slice LUT、206 个 FF 和 2 个 RAMB18E1。RAM 数量由两块增为四块，与级联链需要两组独立窗口行缓存相符；逻辑与寄存器的增量同时包含中值运算、第二级窗口及坐标重映射等开销，不能全部归为单个中值算子的资源。两种配置的分布式 RAM 均为 0，但各有 19 个 LUT 被用于移位寄存器，故“使用 BRAM 行缓存”不等于“不使用任何 LUT 存储资源”。这些数据可用于比较当前 Xilinx 后端的结构代价，不可直接换算成 Ti60 的逻辑单元数量或目标板资源占比。[6]

[基础时序报告](D:/contest/2026FPGA/yilingsi/case4/rtl/core_xilinx_bram_timing_xilinx.rpt)和[级联时序报告](D:/contest/2026FPGA/yilingsi/case4/rtl/core_xilinx_bram_median_timing_xilinx.rpt)均明确说明没有用户时序约束，WNS、TNS 等字段为 `NA`，并列出未约束时钟和端点。这意味着已有报告没有给出有效的时序达标结论，也不能据此推算 Fmax。大帧测试平台中的 4 ns 仿真时钟周期只是事件驱动仿真的激励设置，不是综合或布局布线后实现 250 MHz 的证据。目标 Ti60 上的资源、时钟频率和性能结论必须等待 Efinity 工程、存储 IP、时钟与 I/O 约束以及布局布线报告完成后再形成。[5][6]

### 5.5 已知局限与补充验证

现有 Golden 的无效区域处理存在阈值为零时的边界缺口。[参考实现](D:/contest/2026FPGA/yilingsi/case4/golden_edge.py)先把无效位置的梯度和幅值置零，再对整幅幅值图执行“大于等于阈值”的判断；由于边缘图没有再次与 `valid_mask` 相与，当阈值为 0 时，无效位置的零幅值也会生成 255。5×5 全黑输入中，无中值链的 16 个无效位置和中值链的 24 个无效位置都会出现这一结果，而阈值为 1 时这些位置均为零。该问题不影响表 5-1 的灰度误差统计，却限制了 Golden 作为全阈值范围边界参考的适用性；现有 5 项单元检查没有检测此项，故其全部通过不能消除这一已知缺口。[3][5]

上述零阈值行为已用同一5×5输入独立复现，记录见[边界诊断日志](D:/contest/2026FPGA/yilingsi/case4/report/verification/known_zero_threshold_boundary.log)。该记录用于保留已知问题，不计作修复后的通过结果。

当前小帧和大帧测试主要采用单帧连续输入及帧尾排空，尚不足以评价帧中随机空拍、无间隔多帧、复位中断或动态阈值更新。中值级联内部由窗口裁剪产生的有效间隙，不能代替对外部任意空拍的随机验证。后续应把数值与流接口两类检查共同扩展到这些场景，并为所有有效输出建立坐标唯一性、顺序及标记的双向断言，使重复输出、漏输出与多余标记能够分别定位。目标厂商 RAM 的同址读写、同步读延迟和复位语义也需在替换 XPM 后重新验证，现有 Xilinx 仿真不能覆盖 Efinix 存储实现。[5][6]

表 5-4 尚待完成的验证项目

| 项目 | 需要形成的证据 | 状态 |
|---|---|---|
| 真实图像 RTL 全帧比较 | 两条算法链、两种像素格式的有效区域逐码差异及首次错误坐标 | 【待完成：全帧数值对照结果】 |
| 阈值与流接口边界 | 零阈值有效掩码、阈值临界值、动态更新、连续多帧、随机空拍和帧中复位测试 | 【待完成：新增测试及错误统计】 |
| Ti60 存储后端 | 实际 RAM IP 配置、同址读写语义、读延迟和复位后预热验证 | 【待完成：目标后端仿真与实测】 |
| 受约束实现与板级性能 | 时钟和 I/O 约束、布局布线时序、实际帧率、端到端延迟及功耗 | 【待完成：实现报告与板级测量】 |

这些补充项决定报告结论能否从“指定输入与后端的算子级验证”扩展到“目标板实时图像系统验证”。在相关证据形成前，本项目已经确认的是上述数值公式、测试用例下的 RTL 输出以及既有 Xilinx 核心资源记录，不将检测准确率、Ti60 时序收敛、整机帧率或功耗列为已验证结果。
