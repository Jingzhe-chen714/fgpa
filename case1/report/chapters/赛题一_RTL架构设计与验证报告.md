# 面向 RISC-V SoC 的 FPGA 图像风格迁移协处理器架构设计与验证

参赛队伍、作者及单位：【待补充 M01】

设计目标平台：易灵思 Titanium Ti60F225I3 开发板。

报告日期：2026 年 8 月 31 日。验证数据来自截至 2026 年 8 月 29 日的工程记录；本文中的理论计算与实测结果分别标注。

## 摘要

面向 FPGA 竞赛实时视频风格化任务，设计了一套由 RISC-V 控制、FPGA 执行图像处理与神经网络推理的协处理器架构。系统以 RAW10 像素流、APB 控制接口、AXI4-128 存储接口和并行视频接口为边界，将摄像头物理接收、DDR3 控制器及 HDMI 发送与可移植 RTL 分离。图像通路实现黑电平校正、Bayer 插值、白平衡增益、颜色校正、Gamma 和双线性缩放；推理通路采用包含 22 个执行阶段的 MicroStyle-24 网络，以 INT8 乘加、归一化折叠、逐通道重量化、残差和上采样完成图像变换。计算引擎通过三组外部张量存储区复用算术资源，并由帧所有权管理、参数原子提交和 AXI 安全排空维持任务一致性。现有验证覆盖 Python 整数参考模型、模块级仿真、小尺寸系统闭环及真实参数的有界层间交接，部分算术模块已完成 Efinity 隔离布局布线。当前成果构成板卡无关的功能基线；完整 Ti60F225I3 系统、原生分辨率真实网络、持续帧率与艺术画质尚待验证。报告给出这些边界及后续测量位置，为板级集成和性能优化提供依据。

关键词：RISC-V；FPGA；图像风格迁移；INT8 量化；AXI；软硬件协同

## 1 赛题需求与设计目标

### 1.1 应用背景与设计定位

实时视频风格化既需要保持输入内容的空间结构，又需要在有限延迟内完成图像变换。前馈卷积网络将图像变换表示为一次网络推理，是降低逐帧处理复杂度的一条技术路线；Johnson 等的研究将感知损失与前馈图像变换网络结合，展示了这种方法用于风格迁移的可行性。[R01：Johnson 等，2016](https://arxiv.org/abs/1603.08155)。本项目采用面向硬件约束设计的小型网络，但不将该文的性能或画质结果作为本系统的实现结果。

赛题一要求在 RISC-V 与 FPGA 异构平台上完成摄像头采集、图像预处理、轻量化风格迁移、DDR 帧缓存及 HDMI 对比显示。更正版指南规定采集与预处理的最低目标为 640×480、30 fps，显示最低支持 720p、60 Hz 或 1080p、30 Hz，并要求在 640×480 下稳定达到 15 fps 以上及显示当前 FPS。卷积、激活以及 BN 或 IN 的近似运算属于加速器基本功能。[E01]

上述任务同时受到运算量、外存服务能力和视频时序约束。只证明卷积模块数值正确，不能说明完整系统能够持续输出；同样，HDMI 输出达到 60 Hz，也不能说明每秒产生了 60 张新的风格图像。因此，本设计分别组织采集、计算和显示任务，以明确的帧身份及缓冲所有权连接三者，并将功能正确性、物理实现和实时性能作为不同的验证层级。

### 1.2 需求分解与工程目标

表 1 给出赛题要求与当前架构的对应关系。当前工程选择 720p60 作为显示格式，以 640×480 为网络原生尺寸。网络输出可以低于显示刷新率，显示端在没有新完整结果时重复上一对图像；这一机制用于保持显示连续性，不作为处理帧率达标的依据。

表 1　赛题要求与架构响应

| 项目 | 指标或要求 | 当前架构响应及状态 |
|---|---|---|
| 摄像头输入 | SC431HAI、MIPI CSI-2、最低 640×480@30 fps | RAW10 并行输入与 ISP 已实现；实际传感器、CSI/D-PHY 适配待完成 |
| 神经网络 | 卷积、激活、归一化近似及 DDR 访问 | 3×3/1×1/DW、ReLU、BN 折叠与整数重量化、张量访存已实现 |
| 存储与调度 | 双缓冲、总线稳定交互 | 扩展为三输入双输出帧槽及三张量 bank；原生并发压力仍待验证 |
| 视频输出 | 720p60 或 1080p30，对比显示 | 已实现 720p 时序、原图/风格图/分屏；TMDS 与物理输出待接 |
| CPU 协作 | 初始化、权重部署、任务及中断 | 已定义 APB、IRQ 与软件接口；实际 Sapphire/BSP 集成待完成 |
| 基础性能 | 640×480 下稳定 15 fps 以上、FPS 叠加 | 尚未达成验收证据；现有 OSD 为状态与告警，并非实时 FPS |
| 进阶功能 | 多风格、快速切换、更高分辨率、轻量模型 | 参数更新接口可作为基础；多风格画质与切换延迟尚待实测 |

## 2 系统总体架构与软硬件分工

### 2.1 主顶层及数据流

当前主组合顶层为 `c1_r1_portable_soc`，其内部不直接实例化 Efinix 加密 IP。顶层向板级工程暴露 APB、IRQ、camera RAW10、并行 RGB 视频以及单一 AXI4-128 主接口。这样，图像算术、帧调度和总线协议能够在行为存储模型下验证，而器件相关的时钟、引脚和物理收发由外层负责。[E02]

图 1 展示当前源码的数据路径。摄像头并行 RAW10 经跨时钟缓存和 ISP 后写入输入帧槽；输入 DMA 再读取帧数据，通过 Resize 和 C8 编码送入推理系统。共享引擎与张量适配器共同完成逐阶段执行，中间特征存入 DDR，最终 RGB 结果由输出 DMA 写入结果帧槽。显示子系统同时持有原图与对应风格图，从 DDR 预取后合成输出。

图 1　当前便携 RTL 数据流与板级边界

```text
RISC-V/Sapphire（待接） ── APB/IRQ ── CSR、参数控制、帧生命周期管理

CSI/D-PHY（待接）
      │ 已解包 RAW10、坐标、SOF/EOL/EOF
      ▼
 camera CDC → ISP → Capture DMA → DDR 输入帧槽
                                      │
                                  Input DMA
                                      ▼
                              Resize/C8（当前恒等）
                                      ▼
              张量适配器 ⇄ 共享 MicroStyle 计算引擎
                   │                 ▲       │
         可选行缓存/AXI bridge    参数调度器   最终 RGB
                   │                 ▲       ▼
             DDR 三张量 bank    参数装载器  Output DMA
                                     │       │
                                DDR 参数区  DDR 结果帧槽

 DDR 原图/结果帧槽 → 双路显示预取 → 合成/OSD/720p → HDMI wrapper（待接）

 各存储客户端 → 七客户端 AXI128 仲裁器 → DDR3 Controller/PHY（待接）
```

图 1 矢量版：【待补充 M02：保持上述连接和可选功能边界的系统框图】。

### 2.2 CPU 控制面与硬件数据面

RISC-V 负责摄像头配置、参数在 DDR 中的部署、任务启动、状态读取、中断处理和显示模式选择。FPGA 负责逐像素 ISP、缩放、张量寻址、卷积与帧搬运，避免以 CPU 指令循环执行高频像素操作。CPU 与加速器的关系由外设寄存器和内存接口定义，不依赖特定自定义指令；移植到其他 RISC-V 软核时，主要需要处理总线桥、地址映射、中断和缓存一致性，而非修改 CNN 算术。

本架构采用共享计算与逐阶段执行，并非 22 层各自常驻的全流水网络。早期算法规格曾规划层间直接流式传输；当前实现则以外部张量 bank 换取较少的同时常驻计算资源，并为后续缓存、突发与供数优化保留边界。网络结构可描述不代表任意网络均可执行：现有 tensor adapter 固定了 MicroStyle 的阶段关系和残差 bank 路由，对不同拓扑仍需重新检查调度、算子与存储生命周期。[E05—E08]

## 3 图像处理与 INT8 风格迁移算法

### 3.1 RAW10 与图像信号处理

CSI-2 RAW10 将四个 10 bit 像素编码为五个字节。工程提供 `c1_raw10_unpack4` 处理这一格式，但当前主顶层接收的是已经解包的 10 bit 像素及位置标记，而非直接接收 CSI 字节包。因此，板级适配器需要根据实际 CSI IP 输出格式完成解包连接、行长与包错误处理；不能将顶层的 RAW10 输入视为已经实现 MIPI 协议接收。[E02—E04]

ISP 的处理顺序为黑电平校正、双线性 Debayer、白平衡通道增益、颜色校正矩阵和 Gamma。黑电平按 R、Gr、Gb、B 四种相位独立配置，输出为原始值减去对应黑电平后限制到非负范围。Bayer 识别同时考虑 RGGB、BGGR、GRBG、GBRG 排列和 ROI 起点奇偶性，保证裁剪不会改变颜色解释。R 点的绿色由上下左右四邻域平均，蓝色由四个对角邻域平均；其他相位采用对应的双线性关系。

Debayer 保持 10 bit 精度，边界只输出具有完整 3×3 窗口的像素，宽、高各减少 2。该边界不同于 CNN 中使用的复制填充，不能以普通边缘复制代替 Bayer 相位处理。当前采集默认配置采用 `SENSOR_WIDTH=FRAME_WIDTH+2`、`SENSOR_HEIGHT=FRAME_HEIGHT+2`，即 642×482 输入对应 640×480 有效图像；这一尺寸是便携验证配置，不意味着真实 SC431HAI 已被配置为该输出模式。[E03]

白平衡硬件执行已配置的 Q2.14 增益乘法，当前不含完整的自动统计与增益搜索闭环。其输出保留到 12 bit，随后由 signed Q3.13 的 3×3 CCM 与偏置完成颜色变换，再饱和至 10 bit。Gamma 使用 1024 项 u8 查找表映射为 RGB888。各项可以采用恒等参数建立初始基线；真实镜头与传感器的黑电平、色彩和白平衡校准仍需采集数据。坏点、镜头阴影和 RAW 降噪未计入当前必需路径。

### 3.2 几何变换与输入表示

Resize 使用中心对齐双线性插值。软件预先计算 Q16.16 坐标步进和初相位，RTL 通过相位累加得到采样坐标，不在逐像素路径中执行除法。四个邻点来自两行缓存，插值权重为 Q0.12；水平和垂直两次插值分别进行半向上舍入，以确保 RTL 与整数 Golden 一致。以水平方向为例：

\[
h=\left\lfloor\frac{(4096-w)p_0+w p_1+2048}{4096}\right\rfloor .
\]

当前 Resize 位于 compute ingress，即输入帧从 DDR 读出之后。主顶层把 x/y 步进固定为 1.0、初相位固定为 0，当前组合使用恒等缩放；采集子系统本身先做 ISP，再直接写入帧槽。若真实传感器输出高于当前帧槽尺寸，应选择合法的传感器 ROI/裁剪模式，或增加采集前缩放并重新配置帧表。独立缩放叶模块默认支持最大行宽 2048，但主顶层以 `FRAME_WIDTH` 向下传递行宽上限，当前为 640；已有通用叶模块不等于整个 SoC 已支持 2048 宽输入。

RGB888 经中心化得到有符号激活值：

\[
a=\operatorname{int}(p)-128,\qquad p\in[0,255],\quad a\in[-128,127].
\]

该转换在二补码字节表示下等价于异或 `0x80`。每次数据传输包含八个通道，称为 C8；RGB 放在前三个 lane，其余补零。中间特征按像素、通道组、组内 lane 排列，通道数不足 8 的倍数时保留填充 lane，避免不同层之间采用隐含的数据排布。

### 3.3 MicroStyle-24 网络结构

网络由两层 stride-2 编码卷积、三个倒残差块、两级上采样解码和输出卷积构成。低分辨率特征承担主要风格变换，解码端逐步恢复空间尺寸。深度可分离卷积将空间过滤与通道混合分开，是轻量嵌入式网络常用的计算分解方式。[R02：Howard 等，2017](https://arxiv.org/abs/1704.04861)。本项目借鉴这种算子组合，但网络不是标准 MobileNet 的直接部署。

表 2 的尺寸按“宽×高×通道”表示，MAC 指一次乘法及一次累加，不含偏置、激活、残差加法与插值。22 个阶段中既包括卷积，也包括残差、上采样和输出编码，不能将阶段数理解为 22 个卷积层。

表 2　MicroStyle-24 原生 640×480 网络

| 阶段编号 | 运算 | 输出尺寸 | 卷积权重数 | MAC/帧 |
|---|---|---:|---:|---:|
| 0 | 3×3 Conv，stride 2，3→12 | 320×240×12 | 324 | 24,883,200 |
| 1 | 3×3 Conv，stride 2，12→24 | 160×120×24 | 2,592 | 49,766,400 |
| 2—5 | PW 24→48、DW 3×3、PW 48→24、残差/ReLU | 160×120×24 | 2,736 | 52,531,200 |
| 6—9 | 第二个同结构倒残差块 | 160×120×24 | 2,736 | 52,531,200 |
| 10—13 | 第三个同结构倒残差块 | 160×120×24 | 2,736 | 52,531,200 |
| 14—16 | 上采样×2、DW C24、PW 24→16 | 320×240×16 | 600 | 46,080,000 |
| 17—19 | 上采样×2、DW C16、PW 16→8 | 640×480×8 | 272 | 83,558,400 |
| 20 | 3×3 Conv，8→3，输出饱和 | 640×480×3 | 216 | 66,355,200 |
| 21 | s8→RGB888 | 640×480×3 | 0 | 0 |
| 合计 | 22 个执行阶段 | 输入输出同尺寸 | 12,212 | 428,236,800 |

原生网络要求输入宽、高为 4 的倍数。3×3 卷积使用 SAME_REPLICATE，stride-2 窗口中心对应输入的偶数坐标；上采样采用 `out[y,x,c]=in[y>>1,x>>1,c]`。残差分支保持相同量化尺度，并在较宽位数中相加后饱和。卷积 INT8 权重本身占 12,212 B，加入偏置、重量化参数和对齐后的单风格 parameter arena 为 16,896 B；22 条 64 B 描述符另占 1,408 B。该容量较小，但不能由参数量直接推出视频推理速度。[E05]

### 3.4 量化、归一化与功能训练

网络量化将训练过程与整数推理联系起来，这种协同设计可降低浮点推理在嵌入式硬件上的实现成本。[R03：Jacob 等，2017](https://arxiv.org/abs/1712.05877)。本工程采用明确的 s8 激活、s8 权重、s32 累加和逐输出通道重量化合同，其具体位宽、零点和舍入规则由项目固定点规格决定。

BN 在推理时使用固定统计量，可写为通道仿射变换。令 \(\alpha=\gamma/\sqrt{\sigma^2+\epsilon}\)，则卷积与 BN 可合并为 \(W'=\alpha W\)、\(b'=\alpha(b-\mu)+\beta\)。导出流程冻结这些参数，RTL 不计算运行时均值、方差或平方根，而是执行卷积累加和定点仿射：

\[
z_o=b_o+\sum_i a_iw_{o,i},\qquad
q_o=\operatorname{sat}_{s8}\!\left(\operatorname{round}_{away}\left(\frac{z_oM_o}{2^{s_o}}\right)\right).
\]

\(M_o\) 为有符号 18 bit 乘数，\(s_o\) 为移位量；中点舍入采用远离零方向，负数不能直接套用无符号加半后右移。ReLU 在饱和结果上限制负值，末层 hard-tanh 对应 s8 饱和。该实现以“离线归一化折叠、在线整数仿射”对应赛题的归一化近似要求，其等价性和定点误差需要随部署参数保留证据。

当前已有一套单风格功能训练工件。记录使用六张内容图、64×64 patch、240 步浮点训练和 80 步 QAT；损失包含风格调色板监督、低频内容、固定 RGB/Sobel/Laplacian 特征的 Gram 与颜色统计、边缘及 TV 项。它建立了优化、量化和 RTL 参数导出的闭环，尚不是经过独立数据集评估的比赛级画质模型，也不等同于已经完成 VGG 教师蒸馏。第二种风格、独立视频集及标准网络对照均需补充。[E10—E11]

## 4 RTL 子系统设计与模块协作

### 4.1 采集、配置生效与帧恢复

`c1_r1_capture_frontend` 在 camera 时钟域接收像素及帧行标记，通过异步 FIFO 向 core 域传递完整语义。`c1_r1_capture_subsystem` 将其连接到 R1 ISP、帧表读取器和 XRGB writer。帧管理器分配有效槽位后才允许发布一次采集任务；出现溢出、取消或输出错误时，前端恢复到安全帧边界，避免把半帧作为新图像写入后续处理链。

ISP 配置采用 shadow/commit 机制，使 Bayer、黑电平和色彩参数按受控边界生效。未 armed 或单次采集结束后的输入可以被静默排空；因资源不足而主动丢弃的帧另行计数。这样的处理将恢复动作与正常帧接纳区分开，但 FIFO 只提供有限弹性，无法让物理摄像头无限停顿。真实 CSI 接收端的不可回压行为仍需由板级缓存和错误处理配合。

### 4.2 参数装载与一致性屏障

`c1_r1_parameter_subsystem` 从 DDR 读取描述符与参数 arena，经双 bank 缓存完成完整批次装载。成功后发布新的 active generation；失败或中断的装载不污染正在使用的参数。`c1_r1_c8_parameter_scheduler` 再按 OIHW 顺序遍历当前层权重，将 128 bit arena word 重排到固定 Conv lane bank 或 DW lane bank，减少大范围动态选择网络。[E06]

`c1_r1_microstyle_system_bridge` 将同一描述符快照交给 engine 和 tensor adapter。二者配置屏障均满足后，才能接收首个计算像素，避免算子参数与张量地址来自不同配置。配置缓存的代际提交与单个帧任务是两个状态过程：失败任务不会误启动，但提前成功提交的配置不必随帧任务错误回滚，软件应读取有效代际和状态后决定下一次调度。

### 4.3 共享计算引擎

`c1_r1_microstyle_engine` 负责阶段解码、参数准备以及卷积、DW、残差、上采样和输出阶段控制。普通卷积与点卷积使用 `c1_dot8x8_requant_core`，一次向八个输出通道提供八输入 lane 的点积计算，形成 64 个乘法位置；更多输入通道与 3×3 tap 通过多拍累加完成。DW 路径由独立的 C8 深度卷积核心执行，各通道不进行相互混合。

64 个乘法位置不等于每拍都完成 64 个有效 MAC。参数读取、输入 group、窗口等待、部分通道填充、重量化及输出回压都会产生利用率损失。engine 与存储调度分离后，可以在保持算术合同不变的情况下研究权重预取、输出缓存和计算重叠，但当前默认版本仍以可追溯执行和错误恢复为优先目标。

### 4.4 张量适配与阶段交接

`c1_r1_microstyle_tensor_adapter` 将阶段形状和输出坐标转换为输入窗口、C8 group、残差来源及读写地址。其当前接口每次允许一个 64 bit 请求在途，读写请求均等待完成响应，并在回压时保持请求内容不变。卷积窗口的越界坐标按复制边界映射，上采样按输出坐标右移获得源位置；最终阶段把 RGB 直接送入输出通路，不再写回中间 tensor bank。

三个 bank 的使用顺序是当前网络的一部分。普通阶段在输入与输出 bank 之间切换，倒残差块则保留 skip bank，直到相加完成才允许覆盖。描述符中的 tensor offset 和行跨度目前沿用流式图配置的零值，实际地址由 adapter 的固定调度与形状生成，不能把零值当成可直接访问的物理 DDR 地址。若更换网络拓扑，需要重新定义 bank 生命周期，而不只是替换权重文件。[E07]

### 4.5 输出帧与显示协作

输出 XRGB writer 完成结果写回后，帧管理器将其与对应输入帧组成 display pair。`c1_r1_display_subsystem` 对原图和风格图分别预取，经双时钟 line store 连接到像素域，在帧边界切换已准备好的 pair。两张图不能独立切换，否则会产生原图与结果的时间错配；未完成结果也不能提前发布给显示端。

显示支持风格图、原图、左右分屏与保留模式黑屏，并可叠加十六进制状态和告警。`c1_video_timing_720p` 使用 1280×720 有效区及 1650×750 总时序，标准 60 Hz 对应 74.25 MHz 像素时钟。当前输出为 RGB、DE、HSYNC、VSYNC，并不包含 TMDS 编码、串行化或 HDMI 物理发送。FPS 测量与文字叠加也尚未完成，不能由已有 OSD 推定比赛显示要求已经全部满足。[E18]

## 5 存储、总线、时钟域与帧调度

### 5.1 存储格式与容量

帧缓存采用 XRGB8888，每像素 4 B，640×480 单帧为 1,228,800 B。128 bit AXI beat 可容纳四个像素，有利于连续帧读写。三输入、双输出共五个帧槽占 6,144,000 B；三张量 bank 各预留 8 MiB，总计 24 MiB，二者合计 31,309,824 B，约 29.86 MiB。板卡标称 256 MB DDR3 在容量上可容纳这些区域，但还需为 CPU 程序、堆栈、参数、对齐和保留区域分配空间。[E17]

设 \(G=\lceil C/8\rceil\)，像素坐标为 \((y,x)\)，C8 组号为 \(g\)，则张量地址按以下形式生成：

\[
A=A_{base}+b\times 8\ \mathrm{MiB}+8\big[(yW+x)G+g\big],\qquad b\in\{0,1,2\}.
\]

最大原生中间特征之一为 640×480×16，其 C8 存储量为 4,915,200 B，低于单 bank 预留。bank 保留大小不等于每层实际有效数据量；片上行缓存也不能替代这 24 MiB 外部空间。实际 DDR 地址由最终 SoC 内存映射分配，必须避免与 Sapphire 程序和其他 DMA 区域重叠。

### 5.2 AXI 客户端与事务完成

主顶层通过 `c1_axi_n_serial_arbiter_128` 汇集七个客户端，表 3 给出其用途。默认仲裁按事务锁定所有者，读事务在完成 RLAST 等终止条件后释放，写事务在完成响应后释放。读写方向可独立推进，但不具备通用 AXI ID 乱序返回能力；“七客户端”不意味着七路读事务能够任意并发在途。[E02、E08]

表 3　主顶层 AXI 客户端分配

| Client | 来源 | 方向 | 数据内容 |
|---:|---|---|---|
| 0 | frame job 子系统 | 读/写 | 帧表、输入帧、输出帧 |
| 1 | capture writer | 写 | ISP 后的 XRGB 帧 |
| 2 | parameter subsystem | 读 | 描述符与参数 arena |
| 3 | capture table reader | 读 | 采集帧槽描述 |
| 4 | original display reader | 读 | 原图预取 |
| 5 | styled display reader | 读 | 风格图预取 |
| 6 | tensor/cache client | 读/写 | 输入特征、中间张量和残差 |

帧 reader/writer 采用最高 16 beat 的突发并处理行尾、4 KiB 边界与错误响应；默认 tensor bridge 则把单个 64 bit 事务映射到 128 bit beat，通过地址半字选择和 WSTRB 处理有效数据。工程已有 packing、行缓存 refill、多 outstanding 和读写 burst 的候选模块，但不同模块的独立通过不能替代它们在主顶层的共同验证。当前主要性能开关默认关闭，集成后的队列深度、取消行为和显示服务质量仍需统一检查。

### 5.3 帧所有权与软件可见状态

三输入双输出结构用于同时容纳正在采集、等待计算、正在计算及显示持有的图像。帧槽在可用、采集中、待计算、计算中、待显示及显示占用等状态之间转换，只有完整图像及对应结果可以成为显示 pair。原图在生成结果后仍需供对比显示，因此不能在 CNN 读完时立即无条件复用；相比简单 ping-pong，额外输入槽减少了采集与显示持有同一帧时的冲突。

软件先写 shadow CSR，再发出 START。控制器锁存帧表、参数、张量基址、尺寸和模式，运行期间的后续配置只影响下一任务。APB 地址窗口区分主 CSR 与 ISP 配置，完成、错误和事件通过中断与状态寄存器反馈。CPU 使用数据缓存时，应在 DMA 读取前清理相关缓存、读取 DMA 输出前执行失效与内存屏障；当前外设接口本身不提供硬件缓存一致性。

收到终止中断并不必然意味着所有总线访问已经排空。软件释放帧槽、参数区或 tensor arena 前，仍需确认 BUSY 清零及取消/显示 flush 完成。否则，已提交的写响应或显示预取可能访问已被下一任务复用的内存，造成难以由单模块算术仿真发现的帧损坏。

### 5.4 跨时钟域与取消恢复

系统区分 camera、core 和 pixel 三个时钟域，数据跨域通过 FIFO 或双时钟 line store，事件与复位采用对应同步机制。板级复位释放还必须受 PLL 锁定、DDR 校准和 IP ready 约束；当前便携顶层不能凭自身复位同步器保证外部存储已经可用。若 DDR UI 与 core 时钟不同，还需完整 AXI 跨时钟桥，而不是分别同步地址和数据线。

abort 的设计原则是停止新任务进入，并完成已经对总线承诺的事务。已呈现的 VALID 及载荷在握手前保持稳定，已接受的读突发继续接收或丢弃剩余响应，已提交写事务完成 W/B 排空。像素、参数和帧所有权在安全边界统一恢复，使后续 START 能从一致状态重新开始。该机制是当前功能基线的一部分，但仍需在真实 DDR 的长延迟和多客户端并发下补充压力测试。

## 6 仿真验证与综合资源评估

### 6.1 软件参考与数值一致性

验证链由浮点网络、QAT/整数 Golden、RTL 算术、存储协议和系统生命周期逐层组成。ISP 的公开默认测试集包含六张图像及四种 Bayer 排列，共 24 个 case。已有结果的最低 PSNR 为 29.3864 dB，case 平均值为 31.7270 dB；参考对象是 RGB 合成 RAW10 后的恒等 ISP 重建与缩放，不能用该数值表示风格迁移质量。[E09]

功能 QAT 工件在六张 64×64 图像上的整数输出与 QAT 输出最大绝对误差为 0，说明当前导出参数与整数计算合同一致。内容图与功能训练来源重合，尚未构成独立泛化评估。训练记录、量化参数、RTL 验证和艺术效果应分别报告：位精确是部署必要条件，但并不能证明输出已经达到预期画风。[E10—E11]

### 6.2 RTL 分层验证

表 4 将已保存的验证结果按对象和尺寸拆开。Icarus 全源编译检查只能证明被检查配置下的语法和展开；模块或小帧 PASS 只能支持对应的算术及协议边界。真实参数交接、零参数生命周期与 CNN echo 采用不同激励，其结果不合并为一次完整原生网络测试。

表 4　已有验证结果及结论边界

| 验证对象 | 尺寸/配置 | 已记录结果 | 可支持的结论 |
|---|---|---|---|
| ISP Python Golden | 六图、四 Bayer | 24 case；最低/平均 PSNR 29.3864/31.7270 dB | 合成 RAW 的 ISP/Resize 重建 |
| QAT 对整数模型 | 六张 64×64、单风格 | 最大逐像素误差 0 | 功能工件的量化一致性 |
| Icarus RTL 编译 | 127 个 `.sv` 源文件 | 编译检查通过 | 当前检查入口的源码组合可编译 |
| 训练参数 stage 0—21 handoff | 8×8 scaled、有界逐阶段交接 | operands=896，results=836，final=64，stage_done=22，abort=0 | 真实参数 bank、张量来源、地址与有限交接正确 |
| portable SoC 动态回归 | 8×8、16×8、64×48 等小帧，主要为零参数生命周期配置 | 64×48 两帧记录 done=2、descriptors=44、swaps=2、drops=0 | 小尺寸控制/访存/帧配对闭环 |
| native boardless frame job | 640×480，外部 CNN echo | 输入/输出各 307,200 像素，每方向 4,800 AXI burst | 原生尺寸 DMA、回压与任务接口，不含真实 CNN 算术 |
| native portable SoC | 640×480 | xvlog/xelab 通过 | 原生层次展开，不是完整动态推理 |

stage 0—21 handoff 使用真实参数 arena，并对 producer bank、窗口读序、写入地址和最终 RGB 数量进行检查。它比仅观察 DONE 更严格，但仍是有界缩放测试，不代表 640×480 的所有中间像素、七客户端并发和实时期限均已验证。当前原生 boardless 测试台明确使用一槽 CNN echo，因此报告将它作为数据搬运证据，而非网络推理结果。[E12—E13、E16]

### 6.3 Vivado 与 Efinity 实现结果

Vivado 用于便携 RTL 的仿真和 Artix-7 结构代理综合；Efinity 用于检查目标厂商的语法、存储推断、DSP 映射与布局布线。二者资源单位和器件结构不同，不能把 Xilinx LUT、BRAM tile 与 Ti60 XLR、memory block 一一等价。表 5 保留了各结果的目标与层次，不给出缺乏完整工程依据的整机利用率。[E14—E16]

表 5　历史结构代理与 Efinity 隔离实现

| 对象及条件 | 资源记录 | 时序记录 | 适用范围 |
|---|---|---|---|
| Vivado CNN 重排版历史代理，2026-08-24，Artix-7 | 28,298 LUT；11,168 FF；2 BRAM36；35 DSP | 100 MHz 约束下 WNS=-4.965 ns | 综合/报告流程完成；非时序闭合，非当前完整 SoC |
| Efinity dot/requant 独立核心，Ti60F225/C4 | 80/160 物理 DSP | PNR 推算 Fmax=189.717 MHz | 独立算术核心，不含系统互连和视频 IP |
| Efinity DW 小 IO、重复内部激励 wrapper，C4 | 该壳测得 28/160 物理 DSP | 该壳 PNR 推算 Fmax=271.592 MHz | 部分输出数据不可观测，不能代表完整 C8 DW 核资源 |
| Efinity parameter scheduler，C4 | 1/160 DSP；RAM=0 | PNR 推算 Fmax=236.855 MHz | 只反映参数读取/调度控制 |
| Efinity 22-stage packed-affine 窄壳候选，C4 | 不作为整网资源统计 | map/PNR 流程通过；不引用该壳的频率作性能指标 | 仅作前端兼容性证据 |
| 当前完整 Ti60F225I3 板级系统 | 【待实测补充 P01】 | 【待实测补充 P02】 | 必须包含 CPU、DDR、MIPI、HDMI、约束和完整负载 |

DW 窄壳使用重复输入和权重，并将 64 bit 输出参与 32 bit 观察寄存器更新，高 32 bit 数据缺少完整可观测性，因此存在算术被优化裁剪的条件。28 DSP 只属于该壳，不能与 CPU 和 dot 核的数字相加形成整机资源上界。默认 unpacked affine 配置的完整 engine/CNN top 曾在 Efinity map 前端触发访问违例，因而没有可信的 full-top 资源结果。可选 `PACKED_AFFINE_CACHE=1` 在部分窄壳完成 map/PNR，并通过对应的功能 A/B；完整 portable SoC 的限时 map 探针仍未得到最终资源与 PNR 结果。此状态不能解释为已证明资源超限，也不能凭窄壳通过宣称全板可实现。

### 6.4 原生吞吐下界与优化方向

原生网络每帧包含 428,236,800 MAC，15 fps 对应 6.423552 GMAC/s。若将所有算子统一抽象为每拍 64 个有效 MAC，且没有任何停顿，则该模型的计算周期下界为：

\[
C_{MAC}=\frac{428236800}{64}=6691200\ \text{cycles/frame}.
\]

100 MHz、15 fps 的理想单帧预算约为 6,666,667 cycle，与上述模型值接近。真实引擎还有独立 DW 路径，其 C8 核包含 8×9 个乘积位置，因此不能将统一 64 MAC 模型视为当前混合架构不可突破的绝对下界。实际帧周期必须按层计算 initiation interval（II）、通道填充、配置、重量化及存储等待，再与实测频率共同评估。

现有结构模型对默认 tensor adapter 得到 21,388,800 次 64 bit 逻辑请求，每次经单拍 128 bit bridge 传输后，AXI 数据拍流量为 342,220,800 B/帧，15 fps 对应约 5.133 GB/s。板卡 x16、800 MT/s DDR3 的标称数据面峰值为 1.6 GB/s，且实际服务还受刷新、读写转换与仲裁损失影响。这个差距表明重复窗口读取和半 beat 利用率是结构瓶颈，不能依靠提高时钟约束消除。[E17]

模型中采用全局读复用因子 9、两个 C8 请求合并到一个 AXI beat、四个 outstanding 的理想敏感性场景，可得到约 47.548 MB/帧，即 15 fps 时约 713.216 MB/s。字节数下降来自复用与 packing，outstanding 只影响等待周期估算；上述统计还未包含 capture、帧输入/输出、display 和参数等其他 DDR 流量。全局复用因子并不等价于当前行缓存的真实命中率或逐层可实现调度，不能当作达标证据。实际优化应按层统计窗口复用、突发效率和等待，将 cache/refill、packing、多 outstanding、输出缓存与计算重叠在同一配置下验证。

独立 dot/requant 核心的 80 个物理 DSP 已占器件一半，直接复制完整阵列会挤压 DW、颜色处理、Resize 和 CPU 的空间。当前更合理的工程顺序是提高已有阵列的有效利用率，并评估存储映射与总线质量，再决定是否调整 MAC 并行度。全系统还需验证显示 underflow 和帧截止时间，不能仅以平均 DDR 带宽评价实时性。

### 6.5 最终系统结果预留

表 6 中尚未产生的数据保持为空位，目标值不作为测量值填入。对处理 FPS，应记录一定时间内完成并成功发布的风格帧数；对显示刷新率，则记录像素时钟与帧时序，两者独立计量。画质对照需要注明内容图、风格参考或教师输出，不能直接以“输出更接近原图”判断风格更好。

表 6　板级与最终模型结果

| 测量项 | 必须记录的条件/单位 | 结果 |
|---|---|---|
| I3 全板资源 | 工程配置、XLR/LUT、FF、RAM、物理 DSP、PLL | 【待实测补充 P01】 |
| I3 全板时序 | core/pixel/DDR 时钟、setup/hold、时序例外 | 【待实测补充 P02】 |
| 原生真实 CNN 完整推理 | 640×480、模型版本、逐层/最终误差 | 【待实测补充 P03】 |
| 稳态帧率与延迟 | 测量时长、有效帧数、平均/最大延迟、丢弃帧 | 【待实测补充 P04】 |
| DDR 服务能力 | 并发客户端、MB/s、突发长度、等待周期 | 【待实测补充 P05】 |
| 采集与显示稳定性 | CSI 错误、FIFO overflow、display underflow | 【待实测补充 P06】 |
| 风格画质对照 | 独立内容/视频集、参考定义、PSNR/SSIM及视觉样例 | 【待实测补充 P07】 |
| 板级功耗 | 电源测量位置、空闲/运行条件、W | 【待实测补充 P08】 |
| 双风格在线切换 | 两套已验证权重、切换 ms、是否影响在途帧 | 【待实测补充 P09】 |

真实板卡原图与风格图对比画面：【待补充 M03】。

## 7 Efinity 板级集成方案与关键问题

### 7.1 摄像头与显示物理边界

板级工程应在便携顶层外生成并连接 SC431HAI 对应的 CSI/D-PHY、传感器配置和像素适配器。需要冻结 lane 数、数据类型、Bayer 排列、有效区、帧行标记及不可回压溢出策略。官方视频 Demo 的传感器寄存器和 RAW8 通路不能直接用于当前 RAW10 系统；其作用主要是提供 IP 连接、时钟和物理接口的参考，而非替代已有 ISP。[E19]

HDMI 侧保留当前 RGB/DE/同步输出和图像合成，新增适合 I3 工程的 TMDS 编码、serializer 与引脚约束。调试应从内部色条确认时序和物理链路，再接 DDR scanout 及算法输出。官方 Demo 已有较高 PLL 使用量，合并 CPU、DDR、CSI 和 HDMI 时应重新规划统一时钟树，不能简单拼接两套工程的 periphery 文件。

### 7.2 DDR 与 Sapphire 接入

DDR3 应采用与板卡颗粒和布线匹配的控制器、PHY、初始化与校准参数。便携顶层使用分离的 AXI AW/AR 通道及无 ID 的返回合同；若生成的 Efinity 控制器采用合并地址通道或带 ID 的接口，需要显式桥接并验证次序、响应和取消行为。CPU 访问 DDR 还会新增系统级主设备，不能把当前加速器内部七客户端仲裁器视为已经解决所有 SoC 多主访问。

Sapphire 接入后，应由生成的 BSP、启动代码、链接脚本和实际 APB 地址替换软件中的平台占位。基本验证顺序为 CPU 启动与 UART、APB 寄存器读写、IRQ 清除、DDR 内存测试，再启动小帧加速任务。现有 `c1_sapphire_apb_master_adapter` 与 IRQ adapter 提供可复用的接口基础，但尚不能替代真实 CPU 与缓存开启条件下的联调。

### 7.3 兼容性、实时性与验收边界

当前 RTL 通过将 ISP、算术、张量调度和厂商边界分离，降低了平台迁移时对核心算法的影响。需要继续处理的重构主要集中于 Efinity 可推断存储、控制关键路径和高效供数，而不是直接以官方 TinyML Demo 替换已验证的参数与算术合同。任何候选开关成为默认前，都应同时保留数值、abort/drain、资源、时序和长帧服务质量证据。

30 fps 采集与 15 fps 处理之间存在持续速率差。有限帧缓存只能吸收短期波动，无法无限保存所有未处理帧；当前的接纳、丢弃和重复显示策略需要在验收中明确计数。若“不丢帧”被定义为所有 30 fps 采集帧都必须经过风格化，则计算服务速率也必须达到至少 30 fps，不能以三缓冲结构保证。链路异常丢帧、主动采样帧和新结果缺失应分别报告。

后续验证应从 I3 的最小外设工程逐层扩展到完整系统，在相同模型、相同尺寸和同一内存服务条件下比较性能配置。高阶多风格功能还需两套独立训练并验证的权重、帧边界参数切换以及小于 100 ms 的实测切换记录。现阶段保留这些目标与接口，但不把预留机制视为已完成的进阶成绩。

## 8 设计总结与后续工作

本设计已形成以可移植 RTL 为核心的图像风格迁移协处理器：预处理使用明确的定点规则，计算部分采用共享 INT8 引擎与逐阶段张量调度，控制部分通过参数原子提交和帧所有权维持一致性，数据搬运部分以 AXI 和可排空事务连接 DDR 与视频通路。这样的划分使算术验证、协议验证和厂商 IP 集成能够在不同层次开展，也为后续替换 CPU、调整存储接口和改进供数效率保留了边界。

已有证据支持软件量化一致性、多个 RTL 子模块、小帧系统生命周期以及真实参数的有界层间交接；部分 Efinity 算术与兼容性探针也已完成隔离布局布线。尚未闭合的工作是完整 Ti60F225I3 物理工程、原生真实网络长帧验证、DDR 与显示并发服务、最终艺术画质及稳定帧率。后续应以这些可测量目标补充本报告，而不是将局部 PASS 或理论带宽模型扩大为整机验收结论。

## 参考文献与工程资料

### 学术参考文献

[R01] JOHNSON J, ALAHI A, FEI-FEI L. Perceptual Losses for Real-Time Style Transfer and Super-Resolution[EB/OL]. 2016. [作者预印本，arXiv:1603.08155](https://arxiv.org/abs/1603.08155).

[R02] HOWARD A G, ZHU M, CHEN B, et al. MobileNets: Efficient Convolutional Neural Networks for Mobile Vision Applications[EB/OL]. 2017. [作者预印本，arXiv:1704.04861](https://arxiv.org/abs/1704.04861).

[R03] JACOB B, KLIGYS S, CHEN B, et al. Quantization and Training of Neural Networks for Efficient Integer-Arithmetic-Only Inference[EB/OL]. 2017. [作者预印本，arXiv:1712.05877](https://arxiv.org/abs/1712.05877).

### 赛题与内部工程证据

[E01] 易灵思. [2026 FPGA 竞赛赛题指南，8.22 更正版](<D:/contest/2026FPGA/yilingsi/resource/2026 FPGA竞赛赛题指南 -8.22(更正版).pdf>)，第 10—13 页。

[E02] 项目 RTL：[c1_r1_portable_soc.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/top/c1_r1_portable_soc.sv)。

[E03] 项目 RTL：[采集子系统](D:/contest/2026FPGA/yilingsi/case1/rtl/top/c1_r1_capture_subsystem.sv)、[计算输入与 Resize](D:/contest/2026FPGA/yilingsi/case1/rtl/cnn/c1_r1_compute_ingress.sv)。

[E04] 项目规范：[FIXED_POINT_SPEC.md](D:/contest/2026FPGA/yilingsi/case1/FIXED_POINT_SPEC.md)、[R1 ISP Golden](D:/contest/2026FPGA/yilingsi/case1/golden/r1_isp.py)。

[E05] 项目模型：[microstyle_model.py](D:/contest/2026FPGA/yilingsi/case1/model/microstyle_model.py)、[microstyle_layout.py](D:/contest/2026FPGA/yilingsi/case1/model/microstyle_layout.py)、[功能参数 manifest](D:/contest/2026FPGA/yilingsi/case1/model/microstyle24_starry_functional/manifest.json)。

[E06] 项目 RTL：[共享 engine](D:/contest/2026FPGA/yilingsi/case1/rtl/cnn/c1_r1_microstyle_engine.sv)、[参数 scheduler](D:/contest/2026FPGA/yilingsi/case1/rtl/cnn/c1_r1_c8_parameter_scheduler.sv)。

[E07] 项目 RTL：[tensor adapter](D:/contest/2026FPGA/yilingsi/case1/rtl/cnn/c1_r1_microstyle_tensor_adapter.sv)。

[E08] 架构资料：[ARCHITECTURE.md](D:/contest/2026FPGA/yilingsi/case1/ARCHITECTURE.md)、[RTL_FILE_GUIDE.md](D:/contest/2026FPGA/yilingsi/case1/RTL_FILE_GUIDE.md)。

[E09] ISP 原始结果：[R1 自然图验证 metrics.json](D:/contest/2026FPGA/yilingsi/case1/outputs/r1_validation/metrics.json)。

[E10] 功能训练：[train_microstyle_qat.py](D:/contest/2026FPGA/yilingsi/case1/model/train_microstyle_qat.py)、[training_metrics.json](D:/contest/2026FPGA/yilingsi/case1/outputs/microstyle_qat/training_metrics.json)。

[E11] 量化对照：[validation_metrics.json](D:/contest/2026FPGA/yilingsi/case1/outputs/microstyle_qat/validation/validation_metrics.json)。

[E12] 定向回归：[STAGE8_21_HANDOFF_PREFLIGHT.md](D:/contest/2026FPGA/yilingsi/case1/STAGE8_21_HANDOFF_PREFLIGHT.md)。

[E13] 原生 DMA 测试：[tb_c1_r1_native_boardless_job.sv](D:/contest/2026FPGA/yilingsi/case1/sim/tb_c1_r1_native_boardless_job.sv)。

[E14] 历史综合与验证汇总：[TEST_RESULTS.md](D:/contest/2026FPGA/yilingsi/case1/TEST_RESULTS.md)。

[E15] Efinity 隔离结果：[RESOURCE_MAP_RESULTS_20260829.md](D:/contest/2026FPGA/yilingsi/case1/efinity/RESOURCE_MAP_RESULTS_20260829.md)；资源可观测性对应源码：[DW 窄壳](D:/contest/2026FPGA/yilingsi/case1/efinity/c1_ti60_dw_leaf_wrapper.sv)、[packed CNN 窄壳](D:/contest/2026FPGA/yilingsi/case1/efinity/c1_ti60_cnn_top_packed_wrapper.sv)。

[E16] 截至 2026-08-29 的实现状态：[IMPLEMENTATION_STATUS.md](D:/contest/2026FPGA/yilingsi/case1/IMPLEMENTATION_STATUS.md)。

[E17] 结构模型与板卡配置：[tensor_perf_model.py](D:/contest/2026FPGA/yilingsi/case1/model/tensor_perf_model.py)、[TI60F225_BOARD_PROFILE.md](D:/contest/2026FPGA/yilingsi/case1/efinity/TI60F225_BOARD_PROFILE.md)。

[E18] 显示源码：[display subsystem](D:/contest/2026FPGA/yilingsi/case1/rtl/top/c1_r1_display_subsystem.sv)、[720p timing](D:/contest/2026FPGA/yilingsi/case1/rtl/display/c1_video_timing_720p.sv)。

[E19] 已审计参考工程分析：[OFFICIAL_DEMO_ADAPTATION_GUIDE.md](D:/contest/2026FPGA/yilingsi/OFFICIAL_DEMO_ADAPTATION_GUIDE.md)、[OFFICIAL_RESOURCE_UPDATE_ANALYSIS.md](D:/contest/2026FPGA/yilingsi/OFFICIAL_RESOURCE_UPDATE_ANALYSIS.md)。

## 附录 A 核心 RTL 与接口索引

表 A1 保留报告主线所需的核心模块。完整 127 文件索引见资料 E08，其中还包含历史 R0、局部实验壳及可选性能模块；这些文件不全部同时进入默认数据路径。

| 核心文件 | 功能 | 主要上下游 |
|---|---|---|
| [c1_r1_portable_soc.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/top/c1_r1_portable_soc.sv) | 便携系统主顶层 | APB、camera、video、AXI128 |
| [c1_r1_soc_control.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/top/c1_r1_soc_control.sv) | 生命周期及调度 | CSR、frame manager、capture、job、display |
| [c1_apb_csr.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/control/c1_apb_csr.sv) | 软件寄存器与状态 | APB→START/config/IRQ |
| [c1_apb_isp_config.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/control/c1_apb_isp_config.sv) | ISP 配置提交 | APB→Bayer/BLC/AWB/CCM/Gamma |
| [c1_frame_manager.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/control/c1_frame_manager.sv) | 帧槽及 pair 所有权 | capture、NN、display |
| [c1_r1_capture_subsystem.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/top/c1_r1_capture_subsystem.sv) | 完整采集写回路径 | RAW10/CDC→ISP→XRGB DDR |
| [c1_r1_isp_pipeline.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/video/c1_r1_isp_pipeline.sv) | RAW 到 RGB 处理 | BLC→Debayer→色彩处理 |
| [c1_r1_resize_pipeline.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/video/c1_r1_resize_pipeline.sv) | 坐标、行采样与双线性插值 | 输入 RGB→目标尺寸 RGB |
| [c1_r1_compute_ingress.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/cnn/c1_r1_compute_ingress.sv) | Resize 与中心化 C8 | input DMA→CNN/tensor |
| [c1_r1_parameter_subsystem.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/top/c1_r1_parameter_subsystem.sv) | 参数读取与代际提交 | DDR→active parameter bank |
| [c1_r1_microstyle_system_bridge.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/top/c1_r1_microstyle_system_bridge.sv) | 帧任务与推理系统桥接 | config/frame job↔engine/adapter |
| [c1_r1_microstyle_cnn_top.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/cnn/c1_r1_microstyle_cnn_top.sv) | 阶段配置与 engine 封装 | dispatcher→engine→结果 |
| [c1_r1_microstyle_engine.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/cnn/c1_r1_microstyle_engine.sv) | 共享 INT8 阶段计算 | 参数与操作数→结果 |
| [c1_r1_microstyle_tensor_adapter.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/cnn/c1_r1_microstyle_tensor_adapter.sv) | 窗口、group、bank 寻址 | engine↔64 bit 存储事务 |
| [c1_dot8x8_requant_core.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/cnn/c1_dot8x8_requant_core.sv) | 普通/点卷积点积与重量化 | 激活、权重→八通道结果 |
| [c1_dwconv3x3_c8_requant_core.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/cnn/c1_dwconv3x3_c8_requant_core.sv) | C8 深度卷积 | 窗口、DW 权重→结果 |
| [c1_tensor_mem_axi128_bridge.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/dma/c1_tensor_mem_axi128_bridge.sv) | 64 bit 请求映射 AXI128 | tensor adapter→共享 AXI |
| [c1_tensor_window_cache_axi_client.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/dma/c1_tensor_window_cache_axi_client.sv) | 可选窗口缓存客户端 | adapter/cache→client 6 |
| [c1_axi_xrgb_frame_reader.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/dma/c1_axi_xrgb_frame_reader.sv) | 帧突发读取 | DDR→像素流 |
| [c1_axi_xrgb_frame_writer.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/dma/c1_axi_xrgb_frame_writer.sv) | 帧突发写回 | 像素流→DDR |
| [c1_axi_n_serial_arbiter_128.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/dma/c1_axi_n_serial_arbiter_128.sv) | 多客户端事务仲裁 | 七 client→单 AXI128 |
| [c1_r1_display_subsystem.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/top/c1_r1_display_subsystem.sv) | 显示预取、合成、OSD及时序 | DDR pair→RGB/DE/HS/VS |
| [c1_sapphire_apb_master_adapter.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/vendor/c1_sapphire_apb_master_adapter.sv) | CPU APB 适配 | Sapphire→便携 CSR |
| [c1_sapphire_irq_adapter.sv](D:/contest/2026FPGA/yilingsi/case1/rtl/vendor/c1_sapphire_irq_adapter.sv) | 中断边界适配 | 加速器事件→CPU IRQ |

## 附录 B 待补充资料索引

| 标识 | 后续材料 | 对应位置 |
|---|---|---|
| M01 | 队伍、作者、学校/单位 | 文首 |
| M02 | 依据实际连接绘制的矢量系统框图 | 图 1 |
| M03 | 真实板卡原图/风格图及显示照片 | §6.5 |
| P01—P02 | 完整 I3 工程资源与时序报告 | 表 5、表 6 |
| P03—P06 | 真实 CNN、FPS/延迟、DDR 与视频稳定性记录 | 表 6 |
| P07—P09 | 独立画质对照、功耗及双风格切换记录 | 表 6 |
