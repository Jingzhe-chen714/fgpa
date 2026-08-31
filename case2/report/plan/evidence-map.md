# 证据—论点映射

来源以用户提供的官方文件、板卡截图、当前源码和已有原始记录为限。无需以未读论文填充研究现状，不生成DOI。各章用[R1]等标签，合稿统一参考资料表。相对源路径以D:/contest/2026FPGA/yilingsi为根。

| Source ID | Citation | Source type | Finding/usable fact | Supported claim | Citation slot | Risk |
|---|---|---|---|---|---|---|
| R1 | 2026 FPGA竞赛赛题指南 -8.22(更正版)，2026，第15—17页 | 用户提供官方PDF，当前已目视复核15/16/17页 | 基础Fill/Copy、HDMI640×480@60Hz、burst/FIFO、双缓冲、屏上CPU/硬件FPS；高阶Alpha、Key、60FPS高负载游戏 | 基础项与高阶边界，最终接口AXI4/DDR3/HDMI | 1、6、7 | 无具体加分分值 |
| R2 | 用户提供Ti60F225开发套件核心参数/资源截图 | 板卡材料 | Ti60F225I3、60K级LE、4PLL、DDR3 x16 256MB最高800Mbps、8MB QSPI | 平台目标与容量，不代表已核对原理图引脚 | 1 | BOM/原理图仍待确认；截图路径D:/QQFile/tb_image_share_1787913248799.png与1787913255317.png |
| R3 | renderer_pkg.sv、render_cmd_parser.sv、c2_csr_cmd_bridge.sv，项目源码2026-08-31状态 | 一手源码 | 256位命令、RGB565、8字+submit、状态/计数器、字段校验 | 控制链与命令ABI | 2、3、4、附录 | 作者不是外部发表文献；代理需读实际代码 |
| R4 | render_cmd_mem_engine.sv、c2_mem_arbiter_2m_owner.sv，项目源码 | 一手源码 | 源/背景行burst、共享RAM、等待wr_rsp、单owner | 计算/存储事务实现 | 2、3、7 | 与legacy路径区分；无自动memmove/裁剪/融合alpha-key承诺 |
| R5 | c2_axi4lite_csr_adapter.sv、c2_mem_to_axi4_adapter.sv，项目源码 | 一手源码 | 单outstanding、AW/W独立、16→宽AXI、首尾WSTRB、4KiB拒绝和协议错误处理 | 已实现适配层及边界 | 2、4、7 | 不等于完整AXI VIP认证；厂商连接未验证 |
| R6 | c2_display_path.sv、c2_video_timing_gen.sv、c2_page_flip_ctrl.sv及视频/FIFO源码 | 一手源码 | vblank commit，随后捕获新页预取，首帧黑屏，固定光栅 | 显示路径及软件交接约束 | 2、4、7 | 同时钟4×2行为回归，真实CDC/HDMI待完成 |
| R7 | c2_renderer_system.sv、case2/README.md、architecture.md | 源码/项目说明 | DATA_W16、AXI128、命令FIFO8、行RAM4096、lineFIFO1024、burst16内部拍；generic top非board top | 总体实现与缺口 | 全文 | 须优先源码，避免README旧内容 |
| R8 | case2/tb/xsim_newguide_signoff_20260831、verification.md | 原始日志/状态、索引 | 10功能/11展开；4×2显示；AXI shell只NOP；错误注入预期 | 已有验证结果 | 5 | 本次不重跑EDA，引用已有记录且重新核对；不代表实板 |
| R9 | case2/synth_proxy/render_cmd_mem_engine_util.rpt及c2_renderer_system_ip_stub_util.rpt | Vivado 2023.1原始代理综合报告 | engine2265LUT/647FF/2RAMB36/0DSP；system3680LUT/3840FF/2RAMB36+1RAMB18/0DSP | 逻辑规模与RAM推断代理 | 5 | Artix-7无约束、厂商黑盒内部未计；非Ti60利用率/Fmax |
| R10 | case2/efinity_smoke/outflow_sv_axi_final/case2_rtl_probe_axi_final.map.rpt | Efinity原始结构映射 | 2384LUT4/2134FF/804ADD/0RAM/0DSP | 可解析/结构映射的阶段证据 | 5 | AXI响应绑0、Lite未启用、数据路径被裁剪，不是完整资源估算 |
| R11 | case2/efinity_smoke/GUI_HANDOFF.md | 项目IP交接记录 | 真实IP/约束/BSP/板卡联调交付物 | 待完成工作的接口与测试方法 | 4、6 | 配置以实际生成端口/原理图为准，不引用未验证GUI步骤为已完成 |

容量/带宽计算：640×480×2=614400B；双缓冲1228800B=1.171875MiB；扫描36.864MB/s；扫描+全屏Copy每秒60次110.592MB/s；扫描+全屏Alpha/当前Key147.456MB/s。均为理论下界，非实测。
