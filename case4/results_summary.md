# Golden Model 首轮验证结果

运行命令：

```powershell
$py = 'C:\Users\30982\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $py .\case4\test_golden.py
& $py .\case4\run_regression.py
```

## 自动化检查

`test_golden.py` 当前通过 5 项检查：

* 黑白极值灰度化；
* 垂直/水平阶跃的 Sobel 符号和幅值；
* 部分差分重构 Gx/Gy；
* 3x3 中值去除单点椒盐；
* 阈值单调性和 VALID 有效区域尺寸。

## 经典图像回归（threshold=320）

下表的 edge density 是输出边缘图中非零像素比例；median 列使用 3x3 中值，边界按串接算子 VALID 语义置零。

| 图像 | 无中值 | 加中值 |
|---|---:|---:|
| Cameraman | 0.04010 | 0.03433 |
| Lena 灰度 | 0.02481 | 0.01765 |
| Lenna 彩色转灰度 | 0.02481 | 0.01767 |
| Mandrill | 0.10696 | 0.02857 |
| Peppers | 0.02651 | 0.02007 |

这些数字只用于观察参数趋势，不代表算法精度评分；阈值改变后应重新比较。Mandrill 的纹理密集，加入中值后边缘数量下降明显，适合作为中值滤波的压力测试。

## 输出目录

每张图同时输出 `no_median/` 和 `median/`：

* `gray_float.png`、`gray_fixed.png`、`gray_acc.npy`；
* `window9.npy`、`filtered.png`；
* `gx.npy`、`gy.npy`、`magnitude.npy`、`edge.png`；
* `overlay.png`、`valid_mask.png`；
* `gray_fixed.hex`、`filtered.hex`、`gx_s16.hex`、`gy_s16.hex`、`magnitude_u11.hex`、`edge.hex`。

HEX 文件按行优先、一值一行保存，后续可以直接转换为 `$readmemh` 向量。

## 固定点与 RTL 阶段追加结果

`verify_fixed_gray.py` 已穷举验证：

| 格式 | 样本数 | 最大连续 BT.601 误差 |
|---|---:|---:|
| RGB565 展开到 RGB888 | 65,536 | 0.931 LSB |
| RGB888 | 16,777,216 | 0.945 LSB |

Vivado 2023.1 XSIM 算子回归已通过：

```text
TB_GRAY_RGB PASS
TB_IMAGE_OPERATORS PASS: window/median/Sobel/threshold/overlay/edge8
TB_GRAY_SOBEL_CORE PASS
TB_GRAY_SOBEL_CORE_565 PASS
TB_HEX_CORE PASS: Python Golden vectors match RTL
TB_GRAY_SOBEL_CORE_640 PASS: 304964 valid windows
PASS: tb_window3x3_median (27 cycles)
CASE4_SOBEL_EXTREMES_PASS
CASE4_SOBEL_EDGE_OPS_PASS
```

其中 640×480 检查的有效窗口数为 `(640-2)×(480-2)=304,964`，用于验证
真实尺寸下的行缓存边界、坐标和稳态一像素/时钟吞吐。

portable reference RTL 仍采用组合数组读的三行缓存。Vivado Xilinx 参考综合报告见
`rtl/core_utilization_xilinx.rpt`（574 Slice LUT、375 FF、259 LUT as Memory、0 DSP、0 BRAM）；
仅 Sobel/threshold/overlay 算术流水线的参考报告约为 219 Slice LUT、334 FF、0 DSP、0 BRAM；
Efinix 最终资源映射需要在 Efinity 中重新综合。

## Xilinx BRAM 适配路径（本轮新增）

`scripts/run_xsim_xilinx_bram.ps1 -Full640` 显式编译 Vivado 的
`xpm_memory.sv`，并验证 `xilinx_bram_sdp_row.sv`、
`window3x3_gray_xilinx_bram.sv` 和打包核心入口：

```text
TB_WINDOW_XILINX_BRAM PASS: taps/coords/sideband
TB_GRAY_SOBEL_CORE_XILINX_BRAM PASS
TB_GRAY_SOBEL_CORE_640 PASS: 304964 valid windows
CASE4 XSIM XILINX BRAM PASS: window + packed core + 640x480 throughput
```

中值→Sobel 级联（两级窗口、坐标重映射）追加结果：

```text
TB_GRAY_MEDIAN_SOBEL_CORE PASS: 8 valid windows backend=0
TB_GRAY_MEDIAN_SOBEL_CORE PASS: 8 valid windows backend=1
TB_GRAY_MEDIAN_SOBEL_CORE_640 PASS: 302736 valid windows backend=1
```

其中 `302,736=(640-4)×(480-4)`，确认第一层中值图的 `(W-2)×(H-2)` 局部
光栅能正确驱动第二级 BRAM 窗口，行尾、帧尾和原坐标偏移没有丢失。

同一 Xilinx 适配核心用 Vivado 2023.1、`xc7a35tcpg236-1` 做 OOC 综合：

| 资源 | 数量 |
|---|---:|
| Slice LUT | 296 |
| Slice FF | 404 |
| RAMB18E1 | 2（1 个 BRAM tile） |
| LUT as distributed RAM | 0 |
| DSP | 0 |

报告为 `rtl/core_xilinx_bram_utilization_xilinx.rpt` 和
`rtl/core_xilinx_bram_timing_xilinx.rpt`。这是 Xilinx XPM 的结构性参考，
不是 VF-Ti60F225 的资源承诺。后期换板卡必须替换 BRAM/IP，并保持一拍同步读、
`READ_FIRST` 同地址读写、复位和 sideband 延迟合同；详见
`BRAM_PORTABILITY.md`。

中值级联的 Xilinx OOC 参考为 4 个 RAMB18E1、822 Slice LUT、610 Slice FF、
0 DSP（报告见 `rtl/core_xilinx_bram_median_utilization_xilinx.rpt`）。坐标
重映射和 Xilinx 级联实现已经完成，下一步转入显示时序/输入适配及 Efinity
IP 替换；目标器件仍需保持同一 memory-wrapper 合同。
