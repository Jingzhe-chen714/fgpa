# Task Packet: 6 板级系统集成与性能测试

- Scope：只写拟建方案并逐项留【待完成】空位：板型/型号/摄像头格式/工具版本/实物照片；DVP/MIPI输入，若RAW需额外处理非现有功能；合法时钟复位CDC、异步FIFO不能吸收持续帧率不匹配；全640x480显示补边/原灰度分屏/原RGB叠加按帧坐标对齐不是几拍寄存器；按键消抖同步阈值帧边界更新；可选DDR双buffer所有权/帧冻结；板级验证矩阵与Ti60资源/时序/帧率/延迟/功耗空位。不要预定目标器件具体硬核资源、pin、摄像头寄存器。
- Target chapter file and exclusive owner：D:/contest/2026FPGA/yilingsi/case4/report/chapters/06_integration.md；integration。
- Files to read：common.md（本目录）；../evidence-map.md；../notes.md；case4/report/plan/sources-excerpts.md; case4/rtl/case4_gray_sobel_core.sv; case4/BRAM_PORTABILITY.md; case4/report/plan/experiment-protocol.md（从项目根目录解析）。
- Files allowed to edit：仅上述章节文件。
- Required skills：按common.md路由，完整读取适用SKILL。
- Evidence/data inputs：[1][2][4][7]；第1章另读../chapter-blueprints/01-blueprint.md，第5章另读../experiment-protocol.md。
- Required artifacts：上述章节；不少于1000个正文非空白字符，连续论述而非堆表；具体论证链见Scope。
- Rejection checks：事实与RTL矛盾、虚构验证/性能、无有效证据引用、把规划写成实现、正文含编排过程、非法占位假数据。
- Validation commands：检查文件存在、章节结构、公式/代码指向；不要计算哈希。
- Handoff：status、file、论证链、未解决证据缺口、自审结果。

