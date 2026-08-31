# 2026 FPGA 竞赛工程

本仓库保存当前 FPGA 竞赛工程源码、测试平台、Python Golden 参考模型和设计报告。当前重点工程为 `case4`（实时图像边缘检测）。

## 目录结构

```text
case4/
├─ rtl/                 RTL 算子、流式核心及存储后端封装
├─ tb/                  XSIM/通用 SystemVerilog 测试平台与输入向量
├─ scripts/             仿真和回归脚本
├─ images/              Golden 回归使用的经典测试图像
├─ outputs/             Python Golden 生成的图像结果和指标
├─ report/              设计与验证报告、证据映射及复核脚本
├─ *.py                 Golden 算法、回归和定点误差验证
└─ *.md                 算法规格、架构及 BRAM 移植说明
```

## case4 当前状态

- 已实现 RGB565/RGB888 固定系数灰度、3×3 中值、Sobel、阈值和边缘叠加算子。
- 已提供数组参考窗口和 Xilinx XPM BRAM 参考后端；迁移至易灵思 Titanium Ti60 时需要替换目标存储 IP 并重新验证读写语义。
- 已完成 Python Golden 回归、固定系数误差穷举及既有 XSIM 测试复核。
- 摄像头、HDMI、DDR、Ti60 目标工程和板级闭环仍在报告中以 `【待完成】` 标记。

详细设计、验证数据和后续工作请阅读 [case4/report/赛题四_系统设计与验证报告.md](case4/report/赛题四_系统设计与验证报告.md)。

## 工具链文件排除说明

仓库不提交 Vivado/Efinity 生成的工程缓存、仿真数据库、波形文件、综合/时序报告和临时日志。`.gitignore` 保留可复用的 RTL、测试平台、脚本、报告和输入/输出样例；本地运行工具链后生成的文件不会进入提交。

