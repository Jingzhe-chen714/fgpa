# 证据映射

| Source ID | Citation | Source type | Abstract-level finding | Usable fact | Supported claim | Citation slot | Risk |
|---|---|---|---|---|---|---|---|
| [1] | 易灵思，2026，原始选题指南 | 官方PDF全文相关页 | 原始功能约束 | 基础五项/高阶六项 | 当前任务含采集、处理、显示与交付 | 第1章需求段 | 总述/高阶中值层级有表述差异 |
| [2] | 易灵思，2026，8.22更正版指南解读 | 官方PDF全文相关页 | 算法要求不变 | 640×480与HDMI60Hz，Sobel L1 | 不需要因更正版重写算法 | 第1章版本段 | 板型统一与Q&A冲突；DDR IP省略非正式豁免证据 |
| [3] | 本项目，2026，golden_edge.py及run_regression.py | 源码 | 整数参考链 | 灰度/中值/Sobel/阈值/overlay | 提供可追踪的数值基准 | 第2/3/5章 | Golden不是板级证据；边界mask须单独核对 |
| [4] | 本项目，2026，case4/rtl/*.sv | RTL源码 | 算子与两条流式核心 | 坐标、侧带、窗口与流水线 | 已实现算法，不包含整机top | 第2/3/4/6章 | 吞吐设计能力不等于实测频率 |
| [5] | 本项目，2026，case4/tb及scripts | 测试源码与可复现命令 | 模块/小图/计数覆盖 | 指定scoreboard与输入范围 | 覆盖范围应按TB而非标题判断 | 第5章 | 现有记录与本轮重跑分开 |
| [6] | 本项目，2026，case4/rtl/*utilization*.rpt及*timing*.rpt | Vivado OOC原始报告 | Xilinx代理资源 | 基础296LUT404FF2RAMB18；中值822/610/4；DSP0 | 算法核心参考资源 | 第5章 | 无用户时序约束，不是Ti60或整机 |
| [7] | 本项目，2026，BRAM_PORTABILITY.md | 迁移契约 | 厂商边界 | READ_FIRST与1拍同步读 | Efinix移植需语义验证 | 第4/6章 | 具体目标RAM可用模式尚待确认 |
| [8] | 本项目，2026，verify_fixed_gray.py及fixed_gray_report.json | 穷举脚本与报告 | 连续误差界 | 65536/16777216样本，0.931/0.945LSB | 既定参考域小于1LSB | 第3/5章 | RGB565源量化不计入；浮点也舍入可差1码 |
| [9] | 本项目，2026，image_sources.md及images | 图像来源记录 | Lena/Peppers等经典输入 | 图像集合与既有输出 | 视觉检查材料 | 第5章 | 无像素标注，不可推出检测准确率 |

无外部文献空白论断，无学术优先权声称；项目事实直接由代码与报告支撑。

