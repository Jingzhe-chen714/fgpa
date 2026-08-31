# 章节代理与审阅记录

各章由独立新代理负责，主代理保留最终修改权。以下记录包括主代理的全文审阅，不以代理自行报告替代事实检查。

- chapters/02_Architecture.md | agent=/root/report_architecture | packet=plan/task-packets/02_Architecture.md | inputs=R3,R4,R5,R6,R7 | status=ACCEPTED | prompt=独立核查源码并按输入到输出解释总体架构 | review=主代理全文审阅及源码抽查，阶段/IP边界明确
- chapters/03_Renderer.md | agent=/root/report_renderer | packet=plan/task-packets/03_Renderer.md | inputs=R3,R4,R7 | status=ACCEPTED | prompt=命令到行写提交的RTL方法和限制 | review=主代理全文审阅，复核Fill容量例外/Alpha整数语义/计数器真实口径
- chapters/04_Interfaces.md | agent=/root/report_interfaces | packet=plan/task-packets/04_Interfaces.md | inputs=R3,R5,R6,R7,R11 | status=ACCEPTED | prompt=总线握手显示与软件交接边界 | review=主代理全文审阅并修正摘要表中的执行错误名称，核对CSR/CDC/显示launch代码
- chapters/01_Requirements.md | agent=/root/report_requirements | packet=plan/task-packets/01_Requirements.md | inputs=R1,R2,R7 | status=ACCEPTED | prompt=依已核官方要求和板卡截图写需求约束 | review=主代理全文审阅，来源边界与容量公式正确
- chapters/05_Results.md | agent=/root/report_results | packet=plan/task-packets/05_Results.md | inputs=R8,R9,R10,R7 | status=ACCEPTED | prompt=直接核对日志和报告，区分已有证据/理论估算/未知实测 | review=主代理全文核对，补统一数学排版及访问流量措辞，数值与原始报告一致
- chapters/06_Board.md | agent=/root/report_board | packet=plan/task-packets/06_Board.md | inputs=R1,R7,R11 | status=ACCEPTED | prompt=为未完成板级实施留下配置与测量空位，给出评价条件 | review=主代理全文审阅并复核underflow清除与错误计数源码，补固化启动空位；没有虚构测量
- chapters/07_Discussion.md | agent=/root/report_discussion | packet=plan/task-packets/07_Discussion.md | inputs=R1,R4,R5,R6,R7,R8,R9 | status=ACCEPTED | prompt=已实现特点与吞吐/软件契约/真实IP限制，不拔高创新性 | review=主代理全文审阅，确认优化为提案而非既有结果，完成/欠载/换页口径与前文一致，未宣称实板性能
