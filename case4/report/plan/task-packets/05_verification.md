# Task Packet: 5 仿真验证与资源评估

- Scope：核对Golden/图像/误差记录与TB覆盖。写固定点穷举记录，RGB56565536与RGB88816777216连续误差0.931/0.945；分开小图数值与640输出计数，单级638x478=304964、级联636x476=302736；既有XilinxOOC296/404/2RAMB18/0DSP,中值822/610/4/0；无时钟约束故无Fmax。尚未根目录本轮确认的仿真结果写既有记录而非本轮通过。留表位实图RTL全帧/多帧随机空拍/时序/鲁棒覆盖。禁止编PSNR对照提升、检测准确率、功耗、Ti60资源。
- Target chapter file and exclusive owner：D:/contest/2026FPGA/yilingsi/case4/report/chapters/05_verification.md；verification。
- Files to read：common.md（本目录）；../evidence-map.md；../notes.md；case4/run_regression.py; case4/test_golden.py; case4/results_summary.md; case4/fixed_gray_report.json; case4/rtl/*utilization*.rpt; case4/rtl/*timing*.rpt; case4/tb; case4/report/plan/experiment-protocol.md（从项目根目录解析）。
- Files allowed to edit：仅上述章节文件。
- Required skills：按common.md路由，完整读取适用SKILL。
- Evidence/data inputs：[3][5][6][8][9]；第1章另读../chapter-blueprints/01-blueprint.md，第5章另读../experiment-protocol.md。
- Required artifacts：上述章节；不少于1400个正文非空白字符，连续论述而非堆表；具体论证链见Scope。
- Rejection checks：事实与RTL矛盾、虚构验证/性能、无有效证据引用、把规划写成实现、正文含编排过程、非法占位假数据。
- Validation commands：检查文件存在、章节结构、公式/代码指向；不要计算哈希。
- Handoff：status、file、论证链、未解决证据缺口、自审结果。

