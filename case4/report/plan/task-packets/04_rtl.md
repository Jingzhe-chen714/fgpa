# Task Packet: 4 RTL 实现与存储架构

- Scope：解释实现边界与接口、三个寄存器级的Sobel(部分和/梯度/幅值)加阈值级；避免含糊端到端cycle总数；两bank交替read_first覆盖y-2、一拍RAM读与侧带、无整块清零、参考路径三行数组不应冒充两BRAM物理实现；级联二组窗口(640/638)与有效区域；中值固定循环展开36比较交换不是跨周期串行、但组合深度待时序；Efinix迁移不能保证wrapper单改即可。
- Target chapter file and exclusive owner：D:/contest/2026FPGA/yilingsi/case4/report/chapters/04_rtl.md；rtl。
- Files to read：common.md（本目录）；../evidence-map.md；../notes.md；case4/rtl/case4_sobel_edge_ops.sv; case4/rtl/window3x3_gray.sv; case4/rtl/window3x3_gray_xilinx_bram.sv; case4/rtl/xilinx_bram_sdp_row.sv; case4/rtl/median3x3_u8.sv; case4/rtl/case4_gray_median_sobel_core.sv; case4/BRAM_PORTABILITY.md（从项目根目录解析）。
- Files allowed to edit：仅上述章节文件。
- Required skills：按common.md路由，完整读取适用SKILL。
- Evidence/data inputs：[4][5][6][7]；第1章另读../chapter-blueprints/01-blueprint.md，第5章另读../experiment-protocol.md。
- Required artifacts：上述章节；不少于1500个正文非空白字符，连续论述而非堆表；具体论证链见Scope。
- Rejection checks：事实与RTL矛盾、虚构验证/性能、无有效证据引用、把规划写成实现、正文含编排过程、非法占位假数据。
- Validation commands：检查文件存在、章节结构、公式/代码指向；不要计算哈希。
- Handoff：status、file、论证链、未解决证据缺口、自审结果。

