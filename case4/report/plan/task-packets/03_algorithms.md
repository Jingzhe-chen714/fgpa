# Task Packet: 3 图像处理算法与定点设计

- Scope：从RGB565位复制/RGB888输入推导Q8灰度，系数误差的连续参考口径、17bit是留裕量并非最小必需；3x3中值数学定义；Sobel两个核、signed运算范围、L1幅值保守上界2040(不是可同时达到的精确上界)、11bit幅值；>=阈值和valid_mask的独立职责；RGB红色叠加与原图对齐前提。公式可用独立$$块，编号简洁，不用在Markdown表格内写裸竖线。
- Target chapter file and exclusive owner：D:/contest/2026FPGA/yilingsi/case4/report/chapters/03_algorithms.md；algorithms。
- Files to read：common.md（本目录）；../evidence-map.md；../notes.md；case4/golden_edge.py; case4/rtl/gray_rgb_stream.sv; case4/rtl/case4_sobel_edge_ops.sv; case4/rtl/median3x3_u8.sv; case4/fixed_point_spec.md; case4/fixed_gray_report.json（从项目根目录解析）。
- Files allowed to edit：仅上述章节文件。
- Required skills：按common.md路由，完整读取适用SKILL。
- Evidence/data inputs：[1][2][3][4][8]；第1章另读../chapter-blueprints/01-blueprint.md，第5章另读../experiment-protocol.md。
- Required artifacts：上述章节；不少于1600个正文非空白字符，连续论述而非堆表；具体论证链见Scope。
- Rejection checks：事实与RTL矛盾、虚构验证/性能、无有效证据引用、把规划写成实现、正文含编排过程、非法占位假数据。
- Validation commands：检查文件存在、章节结构、公式/代码指向；不要计算哈希。
- Handoff：status、file、论证链、未解决证据缺口、自审结果。

