# 已确认章节架构

用户于2026-08-31确认上轮大纲及整稿连续编写，无需逐章确认。采用竞赛技术报告结构，不套用SCI模板。每章独立新代理起草，主代理核验后合并；摘要、总结和附录由主代理补写。

## Required chapter files

- chapters/01_Requirements.md | min_chars=1300 | agent=required | owner=report_requirements | placeholders=yes | role=设计任务与平台约束
- chapters/02_Architecture.md | min_chars=1800 | agent=required | owner=report_architecture | placeholders=yes | role=系统总体架构与数据流
- chapters/03_Renderer.md | min_chars=2700 | agent=required | owner=report_renderer | placeholders=yes | role=二维渲染协处理器RTL设计
- chapters/04_Interfaces.md | min_chars=2400 | agent=required | owner=report_interfaces | placeholders=yes | role=总线显示与软硬件协同设计
- chapters/05_Results.md | min_chars=2200 | agent=required | owner=report_results | placeholders=yes | role=验证方法与已有结果
- chapters/06_Board.md | min_chars=1500 | agent=required | owner=report_board | placeholders=yes | role=板级实现与性能测试
- chapters/07_Discussion.md | min_chars=1500 | agent=required | owner=report_discussion | placeholders=yes | role=设计特点局限与后续完善

以上min_chars为非空白字符下限，正文须有至少6段实质叙述，不能以表格填满篇幅。未完成项允许【待补充：……】；主代理另行检查真实实现/实测边界。支持章节放sections/，成品按摘要、1—8章、参考资料及附录顺序汇总为单一Markdown。
