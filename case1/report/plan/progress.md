# 架构报告写作进度

## 2026-08-31：S0 范围与结构确认

- 用户已明确：为当前赛题一架构编写中文 Markdown 比赛报告，后续自行转为 Word。
- 已使用科研写作助手入口、paper-orchestration 和 brainstorming-research，读取结构模板。
- 已检查项目中的既有报告计划，未发现本次报告的已确认大纲。
- 已拟定题目、篇幅、八节正文及参考资料/RTL 索引，写入 `project-overview.md` 与 `outline.md`。
- 已定向检查 `case1/IMPLEMENTATION_STATUS.md` 前 121 行与 `case1/ARCHITECTURE.md` 前 69 行，确认当前功能与证据边界。
- 本节为最初范围确认记录；用户随后回复“按当前框架写，可以对尚未完成的工作预留空位”，范围门禁已满足。
- S0 时尚未编写正文；本轮最终状态见下文。

### Capability-use audit

- 应用技能：research-writing-assistant、using-research-writing、paper-orchestration、brainstorming-research。
- 实际使用：上述四项；读取 brainstorming 的 `templates.md` 以确定工程报告采用适配结构。
- 仅预读未执行：writing-chapters；其正文门禁尚未满足，未据此撰写正文。
- 已消费资料：用户当前请求、已明确的赛题一开发上下文、现有实现状态和架构文档的定向片段。
- 暂未使用资料：大型仿真/综合日志、波形和 checkpoint；本阶段不需要，也避免不必要读取。详细 RTL、固定点规格和资源表留在结构确认后核对。
- 产物：本目录的项目概览、拟定大纲、进度和范围任务包。
- 验证方式：检查计划文件存在、Markdown 标题和未确认状态；不计算哈希。
- 剩余风险：报告结构尚未由用户确认；既有文档含不同日期和不同层级的验证结果，正式写作必须逐项核对，不能混用。

## 2026-08-31：确认后完成 S2/S4/S5

- S2 证据准备完成：按源码、算法规格、模型 manifest 和紧凑结果文件建立 E01—E19 工程证据映射。对更正版赛题指南的赛题一页进行文字提取与页面目视检查。必要学术背景仅查询三项原始论文摘要及书目信息。
- S4 正文编写完成：唯一正文为 `chapters/赛题一_RTL架构设计与验证报告.md`；包含八节正文、摘要、资料来源、24 项核心 RTL 索引以及 12 个获准保留的空位。
- S5 复核完成：独立证据审核发现的范围问题已修订，主代理再核对源码和数字；详见 `review/final-report-review.md`。
- 交付定位：供后续编辑为 Word 的比赛技术报告初稿，不是已完成板级验收的正式实验报告。
- 本轮没有修改 RTL、训练模型或运行 Vivado/Efinity/iverilog；没有读取大型波形、checkpoint 或整份仿真综合日志。

### 本轮 Capability-use audit

| 适用能力 | 实际使用与依据 | 产物或验证 |
|---|---|---|
| research-writing-assistant、using-research-writing | 根据用户调用论文编写技能的要求进入写作流程 | 已确认概览、大纲及范围 |
| paper-orchestration、brainstorming-research | 按单一工程报告组织八节内容，用户已确认结构；使用一个有界独立证据复核代理 | task-packets、blueprint、独立复核与 provenance |
| writing-chapters、writing-core | 在确认后编写单一主稿，区分实现、已有结果、目标和计划 | 唯一 chapters 文件，正文约 7,322 中文字 |
| evidence-driven-writing、literature-review | 先核对工程事实，再对前馈风格迁移、深度可分离卷积与整数量化添加必要文献支持 | evidence-map、22 项工程/学术来源；不扩展为综述章 |
| experiment-results-planning | 预定义原生网络、帧率、带宽、画质与功耗的后续测量口径；不生成虚构结果 | experiment-protocol、table-schema、source-metrics、traceability |
| figures-diagram | 形成可追溯的数据流图及后续矢量图绘制要求 | 正文 ASCII 架构图、architecture_prompt、data-manifest；未调用图像生成 |
| peer-review、verification | 规范审查、独立事实审查、修订后质量门禁与定向检查 | review 文档、verify_report.ps1；命令和结果见最终复核记录 |
| pdf | 读取更正版指南赛题一，核对页码、表格和图文 | 定向文本及第 10—13 页目视检查；渲染图仅为临时检查材料 |

已消费资料：当前核心 RTL 的定向片段、接口/定点规格、Python Golden 与 manifest、ISP/QAT 的小型 JSON、既有 Vivado/Efinity 简报、用户提供板卡信息、更正版指南赛题一及三篇原始论文摘要。所有关键事实按来源分层，没有把不同平台和测试规模的结果拼接为系统验收结论。

刻意未使用：大型仿真临时目录、波形、设计 checkpoint、完整工具日志；不需要新运行结果即可完成架构报告。未使用 LaTeX、Word、PPT 和图片生成能力，因为用户只要求 Markdown，且已允许未完成图表预留空位。未计算文件哈希。

本轮验证：自定义检查通过，确认 8 节、55 个有效本地链接、22 项参考资料、12 个独立占位、正文 7,322 中文字；ISP/QAT/model 数据与既有源 JSON 一致。写作技能草稿质量门禁通过；语言检查 1—5b 项均为 OK，过滤表格、公式与代码图后的段落间距问题为 0。

剩余工程风险：I3 全系统资源与时序尚无闭合证据；真实原生尺寸网络、持续 15 fps、板级 IP/CPU 集成、模型泛化画质和多风格切换尚待实现或测试。正文保留这些问题及对应占位，不因报告交付而标记硬件任务完成。
