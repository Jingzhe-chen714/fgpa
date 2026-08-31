# 报告表格合同

| 表 | 目的 | 主要行 | 数据来源 | 空位策略 |
|---|---|---|---|---|
| 1 | 需求与当前响应 | 采/算/显/控制/进阶 | E01/E02/E16 | 不填假成绩 |
| 2 | 网络层组 | stage0—21 | E05 | 无空位 |
| 3 | 七客户端 | client0—6 | E02/E08 | 无空位 |
| 4 | 仿真证据 | Golden/QAT/handoff/native echo/SoC | E09—E13/E16 | 原始层级不可合并 |
| 5 | 资源与时序 | Vivado历史proxy、Efinity dot/DW/scheduler/packed | E14/E15 | C4/Artix/I3区别标注 |
| 6 | 最终系统测量 | I3资源、时序、DDR、FPS、功耗、画质 | 尚未产生 | 全部明确待实测，不插值 |
| A1 | 核心RTL索引 | top/control/video/cnn/dma/display/vendor | 当前源码 | 路径必须存在 |

已有数值集中记录于 `source-metrics.json`，不是本次新增FPGA实验。无需统计重复试验平均值或置信区间；ISP平均值口径是现有24个Bayer case。
