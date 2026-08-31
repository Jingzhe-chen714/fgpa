# `window3x3_gray` / `median3x3_u8` 设计说明

本文档补充 `case4/rtl/README.md` 中的窗口、行缓存和中值实现细节。

## 统一流接口

模块采用：

```text
valid/sof/eol/eof/x/y
```

坐标是 active image 内的零基坐标。输入必须按光栅顺序提供，`in_valid=1`
时每拍一个灰度像素；当前模块不提供 ready/back-pressure，`in_valid=0` 时
内部行缓存和移位寄存器保持不变。`in_sof` 应与 `(0,0)` 同拍，`in_eol`
与一行最后一个像素同拍，`in_eof` 与最后一帧像素同拍。若 `in_eol` 没有
提供，模块还会用 `in_x == IMG_WIDTH-1` 作行尾 fallback。

## `window3x3_gray`

窗口输出排列为：

```text
p00 p01 p02    // y-2
p10 p11 p12    // y-1
p20 p21 p22    // y
```

输入 `(in_x,in_y)` 补齐当前窗口时，窗口中心是 `(in_x-1,in_y-1)`。输出
寄存器在这个时钟沿更新，因此相对于采样输入增加一个时钟；稳态吞吐为
1 pixel/clock（II=1）。

当前边界策略为 `VALID_ONLY`：

```text
out_valid = in_valid && (in_x >= 2) && (in_y >= 2)
```

前两行及每行前两列不产生窗口，避免人为的 zero/replicate 边缘。第一个
有效窗口中心为 `(1,1)`，`out_sof` 在输入 `(2,2)` 时脉冲；`out_eol/eof`
与最后一个有效中心对齐。`out_valid=0` 时 p00..p22 保持旧值，消费者必须
忽略这些数据。若显示链必须保留完整画面 timing，应另外延迟原始 RGB/灰度
流，或增加一个 transfer-valid 与 window-valid 分离的适配层。

## 三行循环缓存的读写时序

内部有 `row0/row1/row2` 三个深度为 `IMG_WIDTH` 的数组和一个旋转指针：

```text
cur_bank=0: current=row0, previous-1=row2, previous-2=row1
cur_bank=1: current=row1, previous-1=row0, previous-2=row2
cur_bank=2: current=row2, previous-1=row1, previous-2=row0
```

输入时钟沿之前，组合读取得到两个历史行的当前列；同一沿将当前像素写入
`current` 行。每一行另有两个列移位寄存器保存 `x-2` 与 `x-1`，在 `x=0`
时清除上一行残留。因为写入行与读取的两个历史行互不相同，不依赖 RAM 的
read-during-write 模式。

portable reference 实现使用数组组合读，优先保证 Vivado XSIM 的逐周期可解释性。综合到
板卡时可替换成同步 BRAM wrapper；若 BRAM 读增加一拍，必须把 valid、坐标和
所有帧标记一起延迟一拍。

当前已提供 Xilinx 适配版本 `window3x3_gray_xilinx_bram.sv`：它用两行
`xilinx_bram_sdp_row.sv`（XPM simple-dual-port，单拍同步读，
`READ_FIRST` 冲突）实现同一 `VALID_ONLY` 窗口，窗口输出和所有 sideband
统一增加一拍。该文件只适用于 Vivado/Xilinx；换到 Efinix 或其他 FPGA 时，
需要在同一接口合同下替换 BRAM/IP wrapper，并重新执行小图 tap 与 640×480
吞吐测试。迁移规则集中记录在 `case4/BRAM_PORTABILITY.md`。

## `median3x3_u8`

模块对九个无符号样本执行固定边界的 compare/swap 排序，输出排序后第 5
个样本（索引 4）。默认 `REGISTER_OUTPUT=1`，在 `in_valid` 后增加一拍，
仍保持 II=1；设为 0 时为组合输出。它不定义边界填充，通常直接接
`window3x3_gray` 的有效窗口。

## 复位

`window3x3_gray`、`median3x3_u8` 及 RGB/灰度前端使用高有效同步 `rst`；
`case4_sobel_edge_ops.sv` 使用低有效异步 `rst_n`。顶层必须显式做极性转换
（例如 `rst_n = ~rst`），并在需要时同步释放复位。

## 资源估算（640 像素宽）

三行 8-bit 缓存约为 `3×640×8=15,360 bit`；中值排序和窗口移位主要使用
LUT/寄存器，不使用 DSP。基础 Sobel 的 Xilinx BRAM 路径只保留两行缓存，
`2×640×8=10,240 bit`，Vivado OOC 参考映射为 2 个 RAMB18E1；中值与 Sobel
串接仍需第二级窗口，保守按 4 行缓存估算。最终映射应以目标 Efinity/Vivado
报告为准。

## XSIM 自检

```powershell
powershell -ExecutionPolicy Bypass -File .\case4\scripts\run_xsim.ps1
```

统一回归会运行 `case4/tb/tb_image_operators.sv`，期望包含：

```text
TB_IMAGE_OPERATORS PASS: window/median/Sobel/threshold
PASS: tb_window3x3_median (27 cycles)
```

该小帧测试逐项检查九个 tap、中心坐标、有效区域、SOF/EOL/EOF 以及中值
流水延迟。

## 中值→Sobel 级联入口

`case4_gray_median_sobel_core.sv` 已把本窗口封装接入第二级 3×3 窗口：第一
级有效中心 `(1..W-2,1..H-2)` 先重映射为局部 `(W-2)×(H-2)` 光栅，第二级
输出再加回坐标偏移，最终有效区域为 `(W-4)×(H-4)`。这一步需要第二组
行缓存，不能把单级窗口的坐标直接复用。`tb_gray_median_sobel_core.sv`
逐样本检查中值后的 Gx/Gy/幅值/阈值；Xilinx BRAM 入口和 640×480 吞吐测试
由 `scripts/run_xsim_xilinx_bram.ps1 -Full640` 执行。
