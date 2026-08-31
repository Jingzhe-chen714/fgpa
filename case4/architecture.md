# 赛题四系统框架分析（算子 RTL 已开始，系统顶层暂不实现）

## 1. 设计边界

赛题四的基础目标是 640x480 或以上的视频采集、灰度化、3x3 Sobel、阈值化和 HDMI/VGA 显示。高阶功能包括 3x3 中值滤波、动态阈值、DDR 帧缓存、Canny、彩色边缘叠加和简单目标识别。

当前已完成灰度、RGB565/RGB888 解包、3×3 窗口、中值、Sobel、阈值和 RGB565/RGB888
叠加的算子级 RTL，并用 Vivado XSIM 小帧回归；两行同步 BRAM 版本也已完成 XSIM
小图/640×480 吞吐验证和 Vivado OOC 参考综合。首版仍把“DVP/MIPI 输入适配”和
“HDMI/VGA 输出适配”定义成接口边界，暂不实现系统级摄像头/显示顶层。这样可以把
算法错误、窗口错位和板级接口错误分开定位。

## 2. 推荐的抽象数据流

```text
camera_adapter
  (DVP 或 Efinity MIPI/CSI-2 IP)
        |
        v
pixel_normalizer  ---- RGB565/RGB888 -> R8/G8/B8
        |
        v
gray_converter     ---- gray_acc(17b) -> gray8(8b)
        |
        v
line_buffer_2row + 3x3_window
        |
        +--> median3x3 (可选，9 x 8b)
        |
        v
sobel_pipeline     ---- partial -> Gx/Gy -> abs/magnitude -> threshold
        |
        +--> edge8 / edge_bit
        |
display_mapper     ---- split-screen 或 RGB overlay
        |
video_timing/HDMI_or_VGA
```

所有模块之间都建议用同一套侧带信号：

```text
valid, sof, eol, eof, frame_id, x, y
```

`x/y/frame_id` 主要用于仿真 scoreboard，后续综合时可以去掉或缩窄。算法模块不应依赖“某一拍恰好是第几个像素”，而应依赖有效像素和行/帧边界。

## 3. 输入格式层

赛题只规定 DVP 或 MIPI，不规定统一的像素格式，因此首先要固定一个内部格式：

* 推荐内部格式：每个颜色分量 8 bit 的 RGB888；
* 如果摄像头输出 RGB565：
  * `R8 = {R5, R5[4:2]}`；
  * `G8 = {G6, G6[5:4]}`；
  * `B8 = {B5, B5[4:2]}`；
* 如果摄像头输出 RAW10：另建 RAW 解包和 Bayer/Debayer 模块，不要把它混入 Sobel Golden Model。

输入层必须明确：PCLK 边沿、HS/VS 极性、行有效长度、帧有效长度、数据位序和 `sof/eol` 生成规则。

## 4. 灰度化

建议首版使用整数公式：

```text
gray_acc = 77*R8 + 150*G8 + 29*B8
gray8    = (gray_acc + 128) >> 8
```

最大累加值为 `256×255=65,280`，因此使用 17 bit 累加器；加 128 后右移 8 位仍落在 `0..255`，无需额外饱和。该公式对应 BT.601 的硬件友好近似，乘法可以进一步改写为移位加法或映射到 DSP。

Golden Model 同时保存浮点 BT.601、`gray_acc` 和 `gray_fixed`，以便区分“系数近似误差”和 RTL 截位错误。固定点版本应以 bit-exact 为目标；本次穷举显示相对连续浮点参考的最大误差小于 1 LSB。

## 5. 3x3 窗口与行缓存

### 5.1 基础 Sobel

对宽度 W 的灰度图，最小结构为两行存储器加当前行的 3 个水平移位寄存器：

```text
row[y-2][x]   row[y-1][x]   current[y][x]
       \          |          /
             3x3 window
```

在输入坐标 `(x,y)` 到达时，窗口中心对应 `(x-1,y-1)`。首版采用 VALID 语义：

```text
window_valid = (x >= 2) && (y >= 2)
```

边界像素始终输出 0，不做隐含的复制或随机填充。这样单级 3x3 算子的有效区域是 `(W-2) x (H-2)`，也更容易在 RTL 中处理帧首和帧尾。

### 5.1.1 当前 Xilinx BRAM 实现与迁移边界

参考数组窗口仍保留用于无厂商依赖的语义回归；当前 Vivado 路径使用
`window3x3_gray_xilinx_bram.sv`，内部为两个 `640×8` XPM simple-dual-port
RAM。每个输入像素同时读两行并写当前行，XPM 配置为同步读一拍、同地址
`READ_FIRST`，所以窗口的 valid、坐标和帧侧带也统一延迟一拍，II 仍为 1。

这部分是**存储器实现边界**，不是算法边界：Efinix/VF-Ti60F225 或其他器件必须
替换 `xilinx_bram_sdp_row.sv` 为目标 BRAM/IP wrapper，并确认同地址冲突、读延迟、
复位和非 2 次幂深度地址行为。详细迁移规则、回归命令和报告见
`BRAM_PORTABILITY.md`。当前 Xilinx OOC 参考为 2 个 RAMB18E1、296 LUT、404 FF、
0 DSP；不包含摄像头、显示、PLL、DDR 或 IO 资源。

### 5.2 中值滤波串接

中值滤波和 Sobel 都需要 3x3 窗口。若直接串接，建议在第一阶段和第二阶段分别保留行缓存，按保守预算约需要 4 行灰度缓存；不要假设两个阶段可以无条件共享同一块 RAM。

9 个 8-bit 输入的 Golden 中值是 `sorted(window9)[4]`。RTL 可选 19～25 个 compare-swap 单元的部分排序网络，按 5～7 级流水实现；具体网络必须先用随机向量和重复值验证，不能用“各行取中值再取中值”的非等价简化。

串接中值后，最终有效区域应进一步收缩为：

```text
valid_after_median_sobel = (x >= 3) && (x < W-2)
                         && (y >= 3) && (y < H-2)
```

也就是中心区域约 `(W-4) x (H-4)`；外圈 2 像素输出 0。

当前 `case4_gray_median_sobel_core.sv` 已按这个坐标契约实现：第一层窗口/中值
输出的原图中心坐标 `(1..W-2,1..H-2)` 先减一，形成连续的 `(W-2)×(H-2)`
局部光栅；第二层窗口输出后再把中心坐标加一，最终输出 `(2..W-3,2..H-3)`。
这一步不能直接把原坐标送进第二个窗口，否则行尾判断和 bank 旋转会在每行少两
个像素的地方错位。当前 portable 和 Xilinx BRAM 两条路径均有 8×6 逐样本测试，
Xilinx 路径另有 640×480 `302,736=(640-4)×(480-4)` 吞吐检查。

## 6. Sobel 数值路径

题目给定的核可拆为差分和移位：

```text
gx = (p02-p00) + 2*(p12-p10) + (p22-p20)
gy = (p20-p00) + 2*(p21-p01) + (p22-p02)
mag = abs(gx) + abs(gy)
edge = (mag >= threshold) ? 8'hff : 8'h00
```

建议位宽：

| 信号 | 建议位宽 |
|---|---:|
| 窗口像素 | unsigned 8 bit |
| 单项差分 | signed 10～11 bit |
| Gx/Gy | signed 12 bit，范围约 -1020～1020 |
| `abs(Gx)+abs(Gy)` | unsigned 11 bit，范围 0～2040 |
| threshold 寄存器 | 11 bit（可选扩展到 12 bit），限制在 0～2040 |

注意不能让 8-bit unsigned 像素先相减再转换为 signed，否则 `0-255` 会先回绕。必须先扩展到足够宽的有符号数再计算。

推荐四级流水：

1. 读取窗口，形成水平/垂直部分差分；
2. 求完整 Gx/Gy；
3. 求绝对值和幅值；
4. 阈值比较并输出。

每一级都要同步延迟 `valid/sof/eol/eof/x/y/frame_id`。题目中的“零延迟”应解释为“无整帧等待、稳态 initiation interval 为 1”，而不是零时钟延迟。

## 7. 阈值和显示层

基础版本可先固定 threshold；高阶版本再加入按键调节。建议使用：

* `threshold_shadow`：按键改变；
* `threshold_active`：在 SOF 或 VSYNC 时提交；
* 按键步长 16 或 32，范围 0～2047；
* 10～20 ms 消抖。

这样一帧内阈值不变化，不会出现同一帧上下半部分边缘密度不同。

显示层先做最简单的分屏：

* 左侧：延迟对齐的灰度图；
* 右侧：`edge ? 8'hff : 8'h00`；
* 之后再增加红色边缘叠加：`edge ? 24'hFF0000 : delayed_rgb`。

640x480@60 可采用标准 800x525 时序、约 25.175 MHz 像素时钟。若采集和显示不同频，使用双时钟 FIFO；不要用组合逻辑跨时钟域。

## 8. 高阶算法的优先级

建议顺序如下：

1. 灰度 + Sobel + 阈值；
2. 红色边缘叠加；
3. 按键动态阈值；
4. 3x3 中值滤波；
5. DDR 帧缓存/冻结/回放；
6. Canny；
7. 形状识别。

Canny 的高斯滤波、方向量化、非极大值抑制、双阈值和滞后连接会显著增加缓存和状态，暂不纳入第一版 Golden/RTL 门槛。可以在 Sobel 链稳定后，用 OpenCV 或其他软件实现作为离线对照。

## 9. 验证层次

### 数值 bit-exact

* 灰度：`gray_acc`、`gray8`；
* 中值：9 个输入和输出中值；
* Sobel：6 个部分差分、Gx、Gy、绝对值、幅值；
* 阈值：`edge == (mag >= threshold)`。

### 图像指标

* 灰度定点相对浮点：最大误差、MAE、PSNR；
* 边缘图：边缘像素数、IoU、Precision、Recall、F1；
* 中值滤波：椒盐噪声前后误边缘数和噪声残留；
* 阈值扫描：threshold 增大时 edge_count 应单调不增加。

### 流协议

* 每行恰好 W 个有效像素；
* `eol` 后下一有效像素的 x 回到 0；
* `sof` 后 frame_id 递增；
* 无丢像素、重复像素、坐标错位；
* 稳态 II=1 pixel/clock，固定 pipeline latency；
* FIFO 不溢出、不下溢。

`golden_edge.py` 已输出 PNG、NPY 和 `$readmemh` 风格 HEX；当前 `tb_hex_core.sv`
已按坐标逐样本对齐灰度、Gx/Gy、幅值和 edge，而不是只比较最终 PNG。

## 10. 资源初估（640 宽，灰度 8 bit）

* 两行灰度缓存：`2 x 640 x 8 = 10,240 bit`，约 2 个 10-Kbit 块（按 RAM 宽度和读延迟可能更多）；
* 中值串接 Sobel：保守按 4 行缓存，约 2～6 个存储块；
* Sobel 的 `×2` 使用移位，通常不占 DSP；
* 灰度化若用移位加法可不占 DSP，若用并行乘法约 3 个 DSP；
* 中值排序网络主要消耗比较器和寄存器，远小于 MIPI/DDR/HDMI IP。

真正需要 Efinity 综合确认的，是摄像头/显示 IP、异步 FIFO、PLL、IO 约束和布局布线，而不是 Sobel 算术本身。

### 当前 Vivado 原型的实测参考

对 `case4_gray_sobel_core` 使用 Vivado 2023.1、器件 `xc7a35tcpg236-1` 做了
out-of-context 综合，结果约为：574 Slice LUT、375 FF、0 DSP、0 Block RAM。
portable reference 的三行数组因为采用组合读，Vivado 将其推断为分布式 RAM（报告为 259 个 LUT
as Memory），这只是验证用原型，不应直接当作 Ti60F225 的最终映射。若 Efinity
需要把行缓存压入片上块 RAM，应改成同步双口 RAM wrapper，并为读延迟增加相同
数量的窗口和 sideband 流水寄存器；这会改变延迟，但不改变算法数值契约。

### Xilinx BRAM 路径实测参考

对 `case4_gray_sobel_core_xilinx_bram`（同一器件和 OOC 条件）综合得到：

| 资源 | 数量 |
|---|---:|
| Slice LUT | 296 |
| Slice FF | 404 |
| RAMB18E1 | 2（1 个 BRAM tile） |
| DSP | 0 |
| LUT as distributed RAM | 0 |

报告文件为 `rtl/core_xilinx_bram_utilization_xilinx.rpt` 和
`rtl/core_xilinx_bram_timing_xilinx.rpt`。这是 Xilinx 结构性证据；不能把
RAMB18、Slice 等名称直接换算成 Efinix 的 EBR/ALM，目标板仍需 Efinity 重新综合。

中值级联的 Xilinx OOC 参考（`case4_gray_median_sobel_core_xilinx_bram`）为：

| 资源 | 数量 |
|---|---:|
| Slice LUT | 822 |
| Slice FF | 610 |
| RAMB18E1 | 4（2 个 BRAM tile；第一/第二级各两行） |
| DSP | 0 |

逻辑存储量为 `2×640×8 + 2×638×8 = 20,448 bit`；由于 Xilinx BRAM 的深度/宽度
粒度，综合实际使用 4 个 RAMB18E1，而不是按比特数线性折算。

中值排序网络是当前额外的 LUT/FF 主要来源；后续若提高时钟频率，应把 9 点
排序网络拆成多级 compare-swap pipeline，而不是改变 Golden 的中值定义。

## 11. 建议的实施里程碑

1. **已完成**：Python Golden、经典图/合成图回归、RGB565/RGB888 固定点穷举；
2. **已完成**：固定 8×6 小图逐周期检查 3×3 窗口、坐标和边界；
3. **已完成**：灰度、窗口、中值、Sobel、阈值、RGB565/RGB888 叠加算子 RTL；
4. **已完成**：Python Golden HEX 接入 RTL scoreboard；RGB888/RGB565 的 8×6
   逐样本对照和 640×480 有效窗口吞吐/count 检查均通过；
5. **已完成（Xilinx 适配）**：两行同步双口 BRAM、读延迟/`READ_FIRST` 合同、
   小图与 640×480 XSIM、Vivado OOC 资源检查；
6. **已完成**：中值滤波级联的第二级窗口/行缓存、坐标重映射、portable/Xilinx
   小图验证和 Xilinx 640×480 吞吐检查；
7. 在 Efinity 中替换 BRAM/IP 并重新综合；
8. 接入显示时序/分屏；
9. Efinity 彩条和 HDMI；
10. DVP 直通；
11. 将中值级联接入完整显示链（按资源/帧率决定是否启用）；
12. 最后再考虑 MIPI、DDR、Canny 和形状识别。
