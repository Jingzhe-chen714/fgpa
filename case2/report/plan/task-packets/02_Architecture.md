# Task Packet：第02章 系统总体架构与数据流

## Scope

为已确认的比赛技术报告起草本章；用户已授权一次性整稿，无需逐章确认。

## Files allowed to edit

仅 case2/report/chapters/02_Architecture.md。独占owner=report_architecture，不得编辑RTL、其他章节、共享plan或报告合稿。

## Files to read

先读本报告plan/outline.md、project-overview.md、notes.md、chapter-architecture.md、evidence-map.md。技术输入（路径以仓库根为准，plan/与tables/相对于case2/report）：case2/architecture.md；case2/rtl/system/c2_renderer_system.sv；case2/rtl/system/c2_csr_cmd_bridge.sv；case2/rtl/ip/README.md。不存在的文件请rg定位，不猜测内容。

## Required skills

完整读取C:/Users/30982/.codex/skills/research-writing-assistant/skills/writing-chapters/SKILL.md与writing-core/SKILL.md。第1章另读evidence-driven-writing，第5/6/7章另读experiment-results-planning。主代理已读取技能并建立所需规划，用户已明确覆盖逐章确认要求；子代理不再询问。

## Argument chain

从CPU提交矩形到DDR写完成，再到vblank预取与视频输出，解释控制/数据/显示三条路径、模块职责、配置与IP边界。必须明确CPU共享DDR需要外部AXI互连，generic top不是板级top。不生成正式图形，可保留一处架构图待补充。

## Deliverable and style

以“## 2 系统总体架构与数据流”开始，小节为### n.m；至少1800非空白字符，至少6段超过80字符的实质叙述。正文以连贯中文段落为主，表格只承担确切映射/比较，不使用加粗或项目符号堆砌。公式可用单独行Markdown数学式；不生成图像/图表工具产物。采用[R1]等统一引用标签，本章允许R3,R4,R5,R6,R7。不新增未核实引用。

## Rejection checks

不编造板测、FPS、加速比、DSP映射或IP连接；不把4×2仿真/NOP AXI shell/裁剪map说成实板通过。未完成项统一【待补充：……】，数据表用待实测，符合用户要求。不写“实验目的/讨论提示/表位/图位/请用户/写作要求”等流程话语，不用首先/其次/最后/此外/另外/接下来/总之等模板过渡（协议末拍写末拍）。报告是工程设计，不宣传首创或保证获奖。只用apply_patch编辑，不算文件哈希，不运行EDA。

## Validation commands

写后读取本章，统计非空白字符和实质段落，核对关键字段与实际源码/记录。主代理会复验。

## Handoff

返回DONE或DONE_WITH_CONCERNS、唯一改动路径、论证链摘要、实际核对源码/记录、未解决证据缺口及自审结果。不要产生其他文件。
