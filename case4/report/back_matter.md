## 参考资料

[1] 易灵思. 全国大学生嵌入式芯片与系统设计竞赛'2026 FPGA赛道选题指南（易灵思）[R]. 2026. 赛题四见 PDF 第 12—17 页，平台信息见第 3—4 页。[原始选题指南](<D:/contest/2026FPGA/yilingsi/doc/全国大学生嵌入式芯片与系统设计竞赛'2026FPGA赛道选题指南-易灵思.pdf>)。

[2] 易灵思. 2026 FPGA 竞赛赛题指南解读：8.22 更正版[R]. 2026. 赛题四见 PDF 第 24—26 页，平台与问答见第 8、29 页。[更正版官方文档](<D:/contest/2026FPGA/yilingsi/resource/2026 FPGA竞赛赛题指南 -8.22(更正版).pdf>)。

[3] 本项目. Python Golden 算法及图像回归程序[CP]. 2026. [golden_edge.py](D:/contest/2026FPGA/yilingsi/case4/golden_edge.py)、[run_regression.py](D:/contest/2026FPGA/yilingsi/case4/run_regression.py)、[test_golden.py](D:/contest/2026FPGA/yilingsi/case4/test_golden.py)。

[4] 本项目. 赛题四图像算子与流式核心 RTL[CP]. 2026. [基础核心](D:/contest/2026FPGA/yilingsi/case4/rtl/case4_gray_sobel_core.sv)、[中值级联核心](D:/contest/2026FPGA/yilingsi/case4/rtl/case4_gray_median_sobel_core.sv)、[Sobel 与边缘操作](D:/contest/2026FPGA/yilingsi/case4/rtl/case4_sobel_edge_ops.sv)。模块索引见附录 A。

[5] 本项目. RTL 测试平台与仿真复核记录[CP/R]. 2026-08-31. [复核脚本](D:/contest/2026FPGA/yilingsi/case4/report/verification/run_report_checks.ps1)、[算子测试平台](D:/contest/2026FPGA/yilingsi/case4/tb/tb_image_operators.sv)、[跨语言向量测试平台](D:/contest/2026FPGA/yilingsi/case4/tb/tb_hex_core.sv)。各测试运行日志见表 5-2。

[6] 本项目. Vivado 2023.1 算法核心独立模块综合资源与时序报告[R]. 2026-08-23. [基础核心资源](D:/contest/2026FPGA/yilingsi/case4/rtl/core_xilinx_bram_utilization_xilinx.rpt)、[中值级联资源](D:/contest/2026FPGA/yilingsi/case4/rtl/core_xilinx_bram_median_utilization_xilinx.rpt)、[基础核心时序](D:/contest/2026FPGA/yilingsi/case4/rtl/core_xilinx_bram_timing_xilinx.rpt)、[中值级联时序](D:/contest/2026FPGA/yilingsi/case4/rtl/core_xilinx_bram_median_timing_xilinx.rpt)。参考器件为 xc7a35tcpg236-1，未设置有效用户时序约束。

[7] 本项目. 行缓存 BRAM 与厂商 IP 移植边界说明[R]. 2026. [BRAM_PORTABILITY.md](D:/contest/2026FPGA/yilingsi/case4/BRAM_PORTABILITY.md)。

[8] 本项目. 固定系数灰度规格、误差穷举程序与复核结果[CP/R]. 2026-08-31. [定点规格](D:/contest/2026FPGA/yilingsi/case4/fixed_point_spec.md)、[穷举程序](D:/contest/2026FPGA/yilingsi/case4/verify_fixed_gray.py)、[本轮数值结果](D:/contest/2026FPGA/yilingsi/case4/report/verification/fixed_gray_report.json)。

[9] 本项目. 经典图像测试材料来源记录[EB/OL]. 2026-08-23. [image_sources.md](D:/contest/2026FPGA/yilingsi/case4/image_sources.md)。该记录用于追溯输入来源，不构成图像版权许可或标注真值。

## 附录 A 工程文件与实现范围

表 A-1 给出报告所述设计对应的主要文件。Python 和 RTL 中已存在的独立叠加、边缘扩展算子，不代表显示链路、彩色像素延时对齐或整机顶层已经实现。

| 文件 | 功能及范围 |
|---|---|
| [golden_edge.py](D:/contest/2026FPGA/yilingsi/case4/golden_edge.py) | 整数灰度、中值、Sobel、阈值、有效区域与叠加参考；零阈值边界问题见 5.5 节 |
| [gray_rgb_stream.sv](D:/contest/2026FPGA/yilingsi/case4/rtl/gray_rgb_stream.sv)、[rgb_unpack_stream.sv](D:/contest/2026FPGA/yilingsi/case4/rtl/rgb_unpack_stream.sv)、[gray_bt601_stream.sv](D:/contest/2026FPGA/yilingsi/case4/rtl/gray_bt601_stream.sv) | RGB 格式解包及固定系数灰度前端 |
| [window3x3_gray.sv](D:/contest/2026FPGA/yilingsi/case4/rtl/window3x3_gray.sv) | 行存储数组参考后端；用于功能对照，不代表目标 BRAM 映射 |
| [window3x3_gray_xilinx_bram.sv](D:/contest/2026FPGA/yilingsi/case4/rtl/window3x3_gray_xilinx_bram.sv)、[xilinx_bram_sdp_row.sv](D:/contest/2026FPGA/yilingsi/case4/rtl/xilinx_bram_sdp_row.sv) | Xilinx 同步双行缓存及 XPM 存储封装；目标平台需要适配 |
| [median3x3_u8.sv](D:/contest/2026FPGA/yilingsi/case4/rtl/median3x3_u8.sv)、[window3x3_median.sv](D:/contest/2026FPGA/yilingsi/case4/rtl/window3x3_median.sv) | 3×3 中值运算及窗口组合封装 |
| [case4_sobel_edge_ops.sv](D:/contest/2026FPGA/yilingsi/case4/rtl/case4_sobel_edge_ops.sv)、[case4_edge_expand.sv](D:/contest/2026FPGA/yilingsi/case4/rtl/case4_edge_expand.sv) | Sobel 流水线、阈值及独立叠加/边缘扩展模块 |
| [case4_gray_sobel_core.sv](D:/contest/2026FPGA/yilingsi/case4/rtl/case4_gray_sobel_core.sv) | 灰度—Sobel—阈值算法核心 |
| [case4_gray_median_sobel_core.sv](D:/contest/2026FPGA/yilingsi/case4/rtl/case4_gray_median_sobel_core.sv) | 灰度—中值—Sobel—阈值级联核心 |
| [基础 Xilinx 封装](D:/contest/2026FPGA/yilingsi/case4/rtl/case4_gray_sobel_core_xilinx_bram.sv)、[级联 Xilinx 封装](D:/contest/2026FPGA/yilingsi/case4/rtl/case4_gray_median_sobel_core_xilinx_bram.sv) | 固定选择 XPM 后端的参考器件验证入口 |
| [architecture.md](D:/contest/2026FPGA/yilingsi/case4/architecture.md)、[BRAM_PORTABILITY.md](D:/contest/2026FPGA/yilingsi/case4/BRAM_PORTABILITY.md) | 既有架构及迁移说明；具体状态以当前源码和本报告证据边界为准 |

## 附录 B 复核方法与记录位置

本报告复核脚本使用已安装的 Vivado 2023.1 和 Python，Python 环境需要 NumPy 与 Pillow。脚本默认路径对应当前工作环境，可通过 `-VivadoBin` 与 `-Python` 参数指定本机路径。以下命令重新执行 Golden 单元检查、定点灰度穷举以及表 5-2 对应的 12 个 XSIM 测试顶层；不会执行综合、布局布线或实板下载。

```powershell
powershell -ExecutionPolicy Bypass -File "D:\contest\2026FPGA\yilingsi\case4\report\verification\run_report_checks.ps1"
```

复核结果保存在 `case4/report/verification/`。`golden_tests.log` 记录 5 项单元检查，`fixed_gray.log` 和 `fixed_gray_report.json` 记录两种输入域的量化误差，`tb_*.log` 记录测试顶层运行结果，`*_elab.log` 记录展开过程。运行会更新同目录下的同名日志；需要保留某次实验记录时，应在重跑前另存该次记录。上述命令不重生成第 5 章的经典图像输出，也不包含 5.5 节零阈值问题的修复；该问题的独立诊断结果保存在[known_zero_threshold_boundary.log](D:/contest/2026FPGA/yilingsi/case4/report/verification/known_zero_threshold_boundary.log)。

既有参考综合分别由[基础核心综合脚本](D:/contest/2026FPGA/yilingsi/case4/rtl/synth_check_xilinx_bram.tcl)和[中值级联综合脚本](D:/contest/2026FPGA/yilingsi/case4/rtl/synth_check_xilinx_bram_median.tcl)描述，结果日期为 2026 年 8 月 23 日。脚本未提供有效用户时序约束，复用时不能将“综合完成”写成“达到目标频率”。后续用于性能评估的工程应单独记录器件、工具版本、IP 配置、输入尺寸、像素格式、时钟及 I/O 约束，并在布局布线后补充时序与资源结果。

## 附录 C 待完成事项索引

表 C-1 汇总需要继续研发或补充材料的事项。具体结果应填写到对应章节的【待完成】位置；本表不预估完成比例，不把尚无证据的计划计为已实现功能。

| 编号 | 待完成事项 | 预期补充材料 | 对应章节 |
|---|---|---|---|
| C01 | Golden 零阈值无效边界修正及阈值边界回归 | 修正后的有效掩码行为、阈值 0/1/临界值比较结果 | 3、5 |
| C02 | 真实图像 RTL 全帧比较 | 两条链、两种像素格式的逐输出数值、坐标及错误统计 | 5 |
| C03 | 流接口压力与复位测试 | 多帧、随机空拍、复位中断、动态配置及双向标记断言 | 4、5 |
| C04 | Ti60 存储 IP 替换与受约束实现 | RAM 配置、读写语义、后端回归、时钟约束、布局布线报告 | 4、5、6 |
| C05 | 摄像头采集、时钟与复位系统 | 型号、接线、配置表、视频解包、跨域设计和采集证据 | 6 |
| C06 | 显示重建及整机顶层 | 边界补齐、灰度/彩色旁路对齐、显示时序、HDMI 输出与模式控制 | 6 |
| C07 | 帧缓存或 DDR 路径（按最终方案与官方确认实施） | 容量、带宽、缓冲区所有权、读写调度及实际 IP 信息 | 1、6 |
| C08 | 板级闭环与性能测量 | 稳定采集、显示帧率、延迟、资源、功耗、接线照片和演示视频 | 6 |
| C09 | 选做高阶功能 | 仅对实际选做的控制、冻结、增强或检测功能补充实现与结果 | 1、6、7 |
| C10 | 竞赛成稿信息与附件 | 队伍信息、最终板型确认、实测结论、约束文件及交付清单 | 封面、1、6、7 |

