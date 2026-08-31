# Case 4 BRAM/IP 适配边界（重点记录）

> **当前结论：算法契约已经与 Xilinx 存储器实现解耦，但本目录新增的
> `xilinx_bram_sdp_row.sv` 使用 Xilinx XPM，不能直接交给 Efinix Efinity
> 或其他 FPGA 工具链。后期更换板卡时必须替换对应的 BRAM wrapper/IP，
> 并重新验证读写冲突、读延迟和复位语义。**

## 1. 两条实现路径

| 路径 | 文件 | 用途 | 依赖 |
|---|---|---|---|
| 可移植参考路径 | `rtl/window3x3_gray.sv` | XSIM/算法回归、无厂商库的语义基准 | SystemVerilog 数组 |
| 当前 Xilinx 路径 | `rtl/xilinx_bram_sdp_row.sv`、`rtl/window3x3_gray_xilinx_bram.sv`、`rtl/case4_gray_sobel_core_xilinx_bram.sv` | Vivado/Xilinx BRAM 资源和同步读延迟验证 | Vivado `xpm_memory.sv` |

`case4_gray_sobel_core.sv` 和 `case4_gray_median_sobel_core.sv` 的
`WINDOW_BACKEND=0/1` 只选择上述两条路径；灰度定点、Sobel、阈值、中值和
Python Golden 的数值契约不随后端改变。中值级联会实例化两级窗口，因此目标
器件需要两组（共四行）BRAM。

## 2. Xilinx wrapper 的固定接口契约

`xilinx_bram_sdp_row` 当前按 640×8 默认配置实例化一行缓存，窗口模块使用两
个物理 bank（共 `2×640×8=10,240 bit`）：

* 单时钟同步双口：A 口写入当前行，B 口读取历史行；
* `READ_LATENCY_B=1`，即 `rd_en` 在第 N 个上升沿有效，数据在第 N+1 个上升沿
  进入窗口流水；`valid/x/y/sof/eol/eof` 同步延迟；
* 同地址读写采用 `WRITE_MODE_B="read_first"`，返回写入前的旧样本。当前行
  同时承担 y-2 读取和新像素写入，若改为 write-first，窗口会出现整行错位；
* `rst` 为高有效同步复位，只清 BRAM 读数据寄存器，不清整块存储内容。帧首
  之后旧内容会在 `y<2` 的无效窗口期间被覆盖，因此不依赖 RAM 初始化；
* 输入光栅顺序、`in_valid` 无 ready/back-pressure，稳态 II=1 pixel/clock；
* 外部仍遵守 `VALID_ONLY`：中心坐标 `(x,y)` 满足 `x>=1,y>=1` 且不越过
  `W-2,H-2` 才有完整窗口。

这些行为是**必须保留的抽象合同**，而不是 XPM 专属写法。

## 3. 后期换板卡时必须替换什么

适配 VF-Ti60F225/Efinix 或其他 FPGA 时，不能只把顶层参数改成另一种器件：

1. 用目标厂商的双口 RAM 原语、Efinity 生成的 memory IP，或经过综合确认的
   inferred RAM，替换 `xilinx_bram_sdp_row.sv`；必要时同步改写
   `window3x3_gray_xilinx_bram.sv` 的实例化层，但保持同样的端口和时序合同。
2. 明确目标 RAM 的 `read-during-write` 模式。有些器件只有
   `no-change`/`write-first`，需要额外 bypass/旧值寄存器才能恢复
   `read-first` 结果。
3. 明确同步读延迟（0/1/2 拍）、输出寄存器是否在 RAM 内部，以及复位是否清
   内容。任何延迟变化都必须连同 valid、坐标和帧侧带一起改，并重新跑小图
   tap scoreboard。
4. 重新确认深度非 2 的幂（640）时地址高位是否被截断，以及 RAM 的字节写使能、
   初始化和推断属性；不能以 Xilinx 的 `ADDR_WIDTH=$clog2(640)=10` 行为
   直接假定其他器件相同。
5. 在目标工具链中重新综合、布局布线并检查 BRAM/FIFO、时钟和 IO 资源；本目录
   的 Vivado 数字只用于验证结构，不是 Efinix 资源承诺。

## 4. 当前 Vivado 证据

Vivado 2023.1、`xc7a35tcpg236-1`、out-of-context 综合命令：

```powershell
& 'D:\vivado\vivado\Vivado\2023.1\bin\vivado.bat' `
  -mode batch -source .\case4\rtl\synth_check_xilinx_bram.tcl
```

得到：

* 2 个 `RAMB18E1`（1 个 BRAM tile）对应两行 640×8 缓存；
* 296 Slice LUT、404 Slice FF、0 DSP、0 LUT-as-distributed-RAM；
* 该报告没有 IO、PLL、摄像头、HDMI、DDR 和时序约束，不能外推完整板级设计。

中值级联资源可用下面的同类脚本复核：

```powershell
& 'D:\vivado\vivado\Vivado\2023.1\bin\vivado.bat' `
  -mode batch -source .\case4\rtl\synth_check_xilinx_bram_median.tcl
```

XSIM 可复现回归：

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\case4\scripts\run_xsim_xilinx_bram.ps1 -Full640
```

当前通过 `TB_WINDOW_XILINX_BRAM`、`TB_GRAY_SOBEL_CORE_XILINX_BRAM` 和
`TB_GRAY_SOBEL_CORE_640 PASS: 304964 valid windows`。中值级联额外通过
`TB_GRAY_MEDIAN_SOBEL_CORE PASS: 8 valid windows backend=1` 和
`TB_GRAY_MEDIAN_SOBEL_CORE_640 PASS: 302736 valid windows backend=1`。换用其他厂商 IP 后，
必须保留同一组测试，并增加目标器件的 RAM collision/latency 专项测试。

中值级联的同一 Vivado OOC 参考为 4 个 RAMB18E1、822 Slice LUT、610 Slice
FF、0 DSP；排序网络和第二级窗口的资源必须与目标器件重新评估。

## 5. 变更管理规则

* `rtl/window3x3_gray.sv` 永远保留为无厂商依赖的 reference backend；
* Xilinx-only 文件和脚本单独命名、单独回归，不把 XPM 源混入默认 portable
  `run_xsim.ps1`；
* 后续提交若改变 BRAM 读延迟或冲突模式，必须同时更新本文件、窗口侧带说明、
  小图 XSIM scoreboard 和资源报告；
* 算法 Golden 的 RGB565/RGB888 固定系数验证与 BRAM 适配分开，确保换 IP 不会
  改变 RGB 格式下的灰度量化误差（当前连续参考误差仍低于 1 LSB）。
