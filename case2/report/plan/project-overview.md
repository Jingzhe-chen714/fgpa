# 赛题二技术报告编写计划

## 基本信息

- 类型：FPGA 竞赛技术设计报告，不作为期刊投稿论文。
- 领域：RISC-V 与 FPGA 异构系统、二维图形加速、RTL 与总线设计。
- 暂定题目：基于 RISC-V 与 FPGA 的二维图形加速系统设计与验证。
- 输出：中文 Markdown 单文件，用户自行整理为 Word 比赛文档。
- 创建日期：2026-08-31。
- 状态：已完成经确认大纲的整稿写作、章节主审和合稿质量检查；本报告保留未完成工程的填写空位，不是整机验收结论。

## 写作目标

以当前 case2 实现为对象，沿 CPU 命令输入、寄存器与命令队列、矩形渲染、行级存储事务、AXI 适配、帧缓冲与显示输出的数据流解释设计。已实现 RTL、已有验证、理论估算和未来工作分开表述。

用户明确要求尚未完成的工作保留空位。因此真实 Sapphire/DDR3/HDMI IP 配置、CDC 实现、软件驱动、上板结果、最终资源/频率、FPS 与高负载游戏数据均保留可填写的位置，不生成模拟结果或猜测参数。

## 使用技能

使用 research-writing-assistant 的 using-research-writing、paper-orchestration、brainstorming-research 建立流程；确认后按 writing-chapters、writing-core 和相关证据/实验/验证技能执行。完整初稿的章节分派与主代理复核按 paper-orchestration 执行。

## 写作边界

本任务仅新增报告及写作支撑文件，不修改 RTL、不重新运行 EDA、不生成 Word、不改动 case1/case4。报告中的资源数字必须保留工具、目标器件、配置和黑盒裁剪限制；功能回归不能扩展成板级通过。
