# Task Packet：第04章 总线显示与软硬件协同设计

## Scope

为已确认的比赛技术报告起草本章；用户已授权一次性整稿，无需逐章确认。

## Files allowed to edit

仅 case2/report/chapters/04_Interfaces.md。独占owner=report_interfaces，不得编辑RTL、其他章节、共享plan或报告合稿。

## Files to read

先读本报告plan/outline.md、project-overview.md、notes.md、chapter-architecture.md、evidence-map.md。技术输入（路径以仓库根为准，plan/与tables/相对于case2/report）：case2/rtl/system/c2_csr_cmd_bridge.sv；case2/rtl/bus/c2_axi4lite_csr_adapter.sv；case2/rtl/bus/c2_mem_to_axi4_adapter.sv；case2/rtl/system/c2_display_path.sv；case2/rtl/video/c2_page_flip_ctrl.sv；case2/rtl/video/c2_video_timing_gen.sv；case2/efinity_smoke/GUI_HANDOFF.md。不存在的文件请rg定位，不猜测内容。

## Required skills

完整读取C:/Users/30982/.codex/skills/research-writing-assistant/skills/writing-chapters/SKILL.md与writing-core/SKILL.md。第1章另读evidence-driven-writing，第5/6/7章另读experiment-results-planning。主代理已读取技能并建立所需规划，用户已明确覆盖逐章确认要求；子代理不再询问。

## Argument chain

由CSR提交语义解释AXI-Lite独立AW/W与B/R背压，再解释宽AXI适配、显示固定光栅、page提交/预取和软件页所有权。CPU缓存处理/CDC/软件为约定待实现，不冒充已完成驱动。

## Deliverable and style

以“## 4 总线显示与软硬件协同设计”开始，小节为### n.m；至少2400非空白字符，至少6段超过80字符的实质叙述。正文以连贯中文段落为主，表格只承担确切映射/比较，不使用加粗或项目符号堆砌。公式可用单独行Markdown数学式；不生成图像/图表工具产物。采用[R1]等统一引用标签，本章允许R3,R5,R6,R7,R11。不新增未核实引用。

## Rejection checks

不编造板测、FPS、加速比、DSP映射或IP连接；不把4×2仿真/NOP AXI shell/裁剪map说成实板通过。未完成项统一【待补充：……】，数据表用待实测，符合用户要求。不写“实验目的/讨论提示/表位/图位/请用户/写作要求”等流程话语，不用首先/其次/最后/此外/另外/接下来/总之等模板过渡（协议末拍写末拍）。报告是工程设计，不宣传首创或保证获奖。只用apply_patch编辑，不算文件哈希，不运行EDA。

## Validation commands

写后读取本章，统计非空白字符和实质段落，核对关键字段与实际源码/记录。主代理会复验。

## Handoff

返回DONE或DONE_WITH_CONCERNS、唯一改动路径、论证链摘要、实际核对源码/记录、未解决证据缺口及自审结果。不要产生其他文件。
