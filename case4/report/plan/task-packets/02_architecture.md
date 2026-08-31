# Task Packet: 2 总体架构与数据流

- Scope：按输入RGB->灰度->窗口->Sobel->阈值输出介绍两条已实现数据流；中值链为窗口1->median->重基坐标->窗口2->Sobel，不能共享一个窗口。描述valid/sof/eol/eof/x/y、无ready、栅格有空拍、VALID_ONLY和有行延迟非零延迟。拟建camera/display分开表述。不要重复算术细节。
- Target chapter file and exclusive owner：D:/contest/2026FPGA/yilingsi/case4/report/chapters/02_architecture.md；architecture。
- Files to read：common.md（本目录）；../evidence-map.md；../notes.md；case4/rtl/case4_gray_sobel_core.sv; case4/rtl/case4_gray_median_sobel_core.sv; case4/rtl/window3x3_gray_xilinx_bram.sv（从项目根目录解析）。
- Files allowed to edit：仅上述章节文件。
- Required skills：按common.md路由，完整读取适用SKILL。
- Evidence/data inputs：[3][4][7]；第1章另读../chapter-blueprints/01-blueprint.md，第5章另读../experiment-protocol.md。
- Required artifacts：上述章节；不少于1000个正文非空白字符，连续论述而非堆表；具体论证链见Scope。
- Rejection checks：事实与RTL矛盾、虚构验证/性能、无有效证据引用、把规划写成实现、正文含编排过程、非法占位假数据。
- Validation commands：检查文件存在、章节结构、公式/代码指向；不要计算哈希。
- Handoff：status、file、论证链、未解决证据缺口、自审结果。

