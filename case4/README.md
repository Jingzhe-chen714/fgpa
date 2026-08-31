# 赛题四：实时图像边缘检测

本目录现在包含赛题四的算法分析、Python Golden Model、测试图像和第一版算子级
SystemVerilog RTL。摄像头协议、HDMI/VGA 时序、DDR 和最终板级顶层仍然留在
后续系统集成阶段。

目录结构：

```text
case4/
  golden_edge.py / verify_fixed_gray.py       Python Golden 与固定点穷举检查
  images/                                     经典测试图
  outputs/                                    PNG/NPY/HEX 回归结果
  rtl/                                        算子 RTL
  tb/                                         Vivado XSIM 自检 testbench
  scripts/run_xsim_xilinx_bram.ps1            Xilinx XPM/BRAM 专用回归
  BRAM_PORTABILITY.md                         Xilinx BRAM/IP 适配边界（重点）
  generate_rtl_vectors.py                     生成 Python→RTL HEX 向量
  fixed_point_spec.md                         RGB565/RGB888 固定点契约
```

## 1. 建议的算法基线

```text
输入帧
  -> RGB565/RGB888 解包（板上输入时）
  -> 灰度化：Y = (77R + 150G + 29B + 128) >> 8
  -> 可选 3x3 中值滤波
  -> 3x3 Sobel：Gx、Gy、|Gx|+|Gy|
  -> 阈值比较，输出二值边缘
  -> 可选：原图/灰度图/边缘图分屏或彩色边缘叠加
  -> HDMI/VGA 显示
```

中值级联的 RTL 入口为 `rtl/case4_gray_median_sobel_core.sv`；它在第一层
`VALID_ONLY` 窗口后把中值流重映射为 `(W-2)×(H-2)` 局部光栅，再使用第二层
窗口，最终有效区域为 `(W-4)×(H-4)`。Xilinx 入口为
`rtl/case4_gray_median_sobel_core_xilinx_bram.sv`。

当前 Golden Model 的默认约定：

* 灰度化使用 BT.601 的 8-bit 定点近似系数 `(77, 150, 29)`，除数为 256；RGB565 先按标准位复制扩展为 RGB888；对全部 RGB565 和 RGB888 组合穷举，连续量化误差分别为 0.931/0.945 LSB；
* Sobel 使用题目给出的 3x3 核，梯度幅值使用 `abs(Gx) + abs(Gy)`，不计算平方根；
* 梯度内部保留有符号 16-bit 以上精度，阈值在完整幅值范围 `0..2040` 上比较；
* 默认边界策略为 `zero`：边界窗口补 0，并把最终边界像素置为 0，便于后续和行缓存 RTL 对齐；
* 中值滤波默认使用 `replicate` 边界以便观察去噪效果；若要严格模拟 RTL，可改为 `zero`；
* 所有中间结果都会保存为 PNG（便于肉眼检查）和 HEX/NPY（便于后续 `$readmemh`/数值回归）。

## 2. 运行环境

使用 Codex 工作区自带 Python，依赖只有 NumPy 和 Pillow：

```powershell
$py = 'C:\Users\30982\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $py .\case4\golden_edge.py --input .\case4\images\lenna_color_512.tif --output-dir .\case4\outputs\lenna --median --threshold 320
```

不加 `--median` 即运行基础链路。阈值 320 是完整 Sobel L1 幅值的示例值，不是最终硬件参数。

批量运行已下载的图片：

```powershell
$py = 'C:\Users\30982\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $py .\case4\run_regression.py

# 固定系数穷举验证（RGB565 全码字 + RGB888 全颜色）
& $py .\case4\verify_fixed_gray.py --json .\case4\fixed_gray_report.json

# 算子级 Vivado XSIM 回归
powershell -ExecutionPolicy Bypass -File .\case4\scripts\run_xsim.ps1

# 可选：再跑完整 640×480 active frame throughput/count 检查
powershell -ExecutionPolicy Bypass -File .\case4\scripts\run_xsim.ps1 -Full640

# 可选：窗口+中值封装的独立 5×5 回归
powershell -ExecutionPolicy Bypass -File .\case4\rtl\tb\run_xsim.ps1

# Xilinx XPM/BRAM 版本（含基础链路和中值级联的 640×480 吞吐检查）
powershell -ExecutionPolicy Bypass -File .\case4\scripts\run_xsim_xilinx_bram.ps1 -Full640
```

## 3. 固定点和 RTL 接口契约

Golden Model 已把后续 RTL 需要固定的语义显式化：

| 项目 | 当前约定 |
|---|---|
| 像素顺序 | 行优先，左到右、上到下 |
| `sof` | 第一行第一个像素前产生 |
| `eol` | 每行最后一个有效像素同时标记 |
| 有效输出 | 中间流水线延迟后仍保持一个像素一个输出 |
| Sobel 边界 | 第一/最后一行、第一/最后一列输出 0 |
| 梯度位宽 | `Gx/Gy` 有符号，建议至少 12 bit；Golden HEX 用 16 bit 二补码 |
| 幅值位宽 | `0..2040`，建议 11 bit |
| 边缘输出 | 0 或 255 |

固定点的完整误差定义和穷举结果见 [fixed_point_spec.md](D:/contest/2026FPGA/yilingsi/case4/fixed_point_spec.md)。

当前 RTL 算子和接口说明见 [rtl/README.md](D:/contest/2026FPGA/yilingsi/case4/rtl/README.md)、
[README_rgb_gray.md](D:/contest/2026FPGA/yilingsi/case4/rtl/README_rgb_gray.md)。
算子 testbench 按坐标 sideband 对齐 Golden 结果，不依赖某个固定的总流水延迟。
`tb_hex_core.sv` 进一步直接读取 `generate_rtl_vectors.py` 生成的 HEX，完成
Python Golden 与 RTL 的跨语言 bit-exact 对照。

当前统一约定：

* RGB/灰度/窗口模块使用 `rst` 高有效同步复位；Sobel 算术文件保留 `rst_n` 低有效异步复位，串接时显式使用 `.rst_n(~rst)`；
* `window3x3_gray` 采用 `VALID_ONLY`，只输出完整 3×3 窗口，中心坐标为 `(in_x-1,in_y-1)`；
* Sobel 的 `in_valid` 表示窗口传输，`in_win_valid` 表示 3×3 算法有效；当前窗口模块可将两者都接到 `window.out_valid`；
* 后续若要保持完整视频时序，应并行延迟原始 RGB/灰度流，不能直接把 valid-only 窗口当作 HDMI 全帧流。

### Xilinx BRAM 版本（当前适配层）

已增加一条使用 Vivado XPM `xpm_memory_sdpram` 的同步双口 BRAM 路径：
`xilinx_bram_sdp_row.sv` + `window3x3_gray_xilinx_bram.sv`，并由
`case4_gray_sobel_core_xilinx_bram.sv` 提供显式入口。该版本使用两行
`640×8` 缓存、单拍同步读、`READ_FIRST` 同地址读写，稳态吞吐仍为
1 pixel/clock；小图 tap/sideband、打包 RGB888 核心、median→Sobel 级联和
640×480 count 已在 XSIM 通过。基础核心 Vivado OOC 综合显示 2 个 RAMB18E1、
296 LUT、404 FF、0 DSP；中值级联为 4 个 RAMB18E1、822 LUT、610 FF、0 DSP。

**重要：XPM 是 Xilinx 专用实现，不是赛题目标 Efinix 器件的最终 IP。** 后期
适配 VF-Ti60F225 或其他 FPGA 时，必须替换 BRAM wrapper/IP，并重新核对
`read-during-write`（当前为 `read_first`）、同步读延迟、复位和 640 深度地址行为；
灰度/Sobel/Golden 数值模块不应随之改动。详细边界和迁移清单见
[BRAM_PORTABILITY.md](D:/contest/2026FPGA/yilingsi/case4/BRAM_PORTABILITY.md)。

## 4. Python 与 XSIM 验证顺序

1. 纯灰度化：比较浮点 BT.601 与定点 `(77,150,29)` 的误差；
2. 3x3 窗口：用合成棋盘格、斜坡、单点脉冲检查窗口顺序；
3. Sobel：先不加中值滤波，确认 Gx/Gy 符号和幅值；
4. 阈值：扫过多个阈值，记录边缘密度；
5. 中值滤波：加入椒盐噪声，比较噪声抑制与细边缘损失；
6. 彩色叠加/分屏：只处理显示映射，不改变边缘判定；
7. Xilinx BRAM 路径及中值→Sobel 两级窗口已通过小帧和 640×480 XSIM 自检，并
   完成 Vivado OOC 资源参考综合；下一步转入显示/输入适配和 Efinity IP 替换。

已完成的 XSIM 回归：

```powershell
# 固定灰度：xvlog/xelab/xsim 运行 tb_gray_rgb.sv
# 窗口、中值、Sobel、阈值、RGB888/RGB565 叠加：运行 tb_image_operators.sv
# 打包 RGB → 灰度 → 窗口 → Sobel → 阈值：运行 tb_gray_sobel_core.sv
# 同一打包核心的 RGB565 路径：运行 tb_gray_sobel_core_565.sv
# Python Golden HEX 与 RTL 逐样本对照：运行 tb_hex_core.sv
# 中值→Sobel 级联：运行 tb_gray_median_sobel_core.sv（最终有效区 (W-4)×(H-4)）
```

默认 testbench（含中值→Sobel 级联）均在 Vivado 2023.1 XSIM 下通过；此外，窗口+中值封装的独立
5×5 回归 `case4/rtl/tb/tb_window3x3_median.sv` 也已通过。可使用
[tb_gray_rgb.sv](D:/contest/2026FPGA/yilingsi/case4/tb/tb_gray_rgb.sv)、
[tb_image_operators.sv](D:/contest/2026FPGA/yilingsi/case4/tb/tb_image_operators.sv) 和
[tb_gray_sobel_core.sv](D:/contest/2026FPGA/yilingsi/case4/tb/tb_gray_sobel_core.sv)、
[tb_gray_sobel_core_565.sv](D:/contest/2026FPGA/yilingsi/case4/tb/tb_gray_sobel_core_565.sv)、
[tb_hex_core.sv](D:/contest/2026FPGA/yilingsi/case4/tb/tb_hex_core.sv)、
[tb_gray_median_sobel_core.sv](D:/contest/2026FPGA/yilingsi/case4/tb/tb_gray_median_sobel_core.sv)
作为后续仿真的起点。

## 5. 板卡相关但暂不实现的模块

基础版本建议优先走 VF-Ti60F225 的 DVP 输入，避免一开始引入 MIPI D-PHY/CSI-2。仍需在 Efinity/实板阶段验证：

* 将当前 Xilinx XPM 两行缓存替换为 Efinity/目标器件的 BRAM 或 memory IP，并
  重新验证同步读延迟、读写冲突模式和资源映射（见
  [BRAM_PORTABILITY.md](D:/contest/2026FPGA/yilingsi/case4/BRAM_PORTABILITY.md)）；
* DVP 传感器寄存器初始化、PCLK/HS/VS 极性和 RGB565 位序；
* HDMI/VGA 像素时钟、PLL、引脚约束和显示器兼容性；
* 若做 DDR 帧缓存，再加入 Efinity DDR 控制器和帧同步；
* 若改用 MIPI 摄像头，再加入 Efinity MIPI D-PHY/CSI-2 IP。

## 6. 当前测试图来源

见 `image_sources.md`。Lenna、Cameraman、Peppers、Mandrill 来自公开的标准测试图仓库；这些文件只作为算法回归输入，后续公开展示时应保留来源和许可说明。
