## 参考资料

本报告以官方赛题、参赛板卡资料和本项目实现记录为依据。源码与实验记录按2026年8月31日的本地状态引用；它们属于工程证据，不作为外部发表论文。各编号对应的本地文件可用于追溯正文中的接口、算法和结果。

[R1] 易灵思赛题资料. [2026 FPGA竞赛赛题指南 -8.22(更正版)](<D:/contest/2026FPGA/yilingsi/resource/2026 FPGA竞赛赛题指南 -8.22(更正版).pdf>), 2026, PDF第15—17页.

[R2] 参赛板卡资料. [Ti60F225开发套件核心参数](D:/QQFile/tb_image_share_1787913248799.png)及[存储资源与板载接口](D:/QQFile/tb_image_share_1787913255317.png), 用户提供截图. 板卡修订号、原理图与BOM版本：【待补充】.

[R3] 本项目. [命令ABI](D:/contest/2026FPGA/yilingsi/case2/rtl/common/renderer_pkg.sv)、[命令解析器](D:/contest/2026FPGA/yilingsi/case2/rtl/cmd/render_cmd_parser.sv)、[命令FIFO](D:/contest/2026FPGA/yilingsi/case2/rtl/cmd/render_cmd_fifo.sv)与[CSR命令桥](D:/contest/2026FPGA/yilingsi/case2/rtl/system/c2_csr_cmd_bridge.sv), SystemVerilog源码, 2026.

[R4] 本项目. [渲染存储引擎](D:/contest/2026FPGA/yilingsi/case2/rtl/mem/render_cmd_mem_engine.sv)、[带owner的双主仲裁器](D:/contest/2026FPGA/yilingsi/case2/rtl/mem/c2_mem_arbiter_2m_owner.sv)、[Alpha参考算子](D:/contest/2026FPGA/yilingsi/case2/rtl/ops/alpha_blend_pixel.sv)与[Color Key参考算子](D:/contest/2026FPGA/yilingsi/case2/rtl/ops/color_key_pixel.sv), SystemVerilog源码, 2026.

[R5] 本项目. [AXI4-Lite控制适配器](D:/contest/2026FPGA/yilingsi/case2/rtl/bus/c2_axi4lite_csr_adapter.sv)与[宽AXI4存储适配器](D:/contest/2026FPGA/yilingsi/case2/rtl/bus/c2_mem_to_axi4_adapter.sv), SystemVerilog源码, 2026.

[R6] 本项目. [显示路径](D:/contest/2026FPGA/yilingsi/case2/rtl/system/c2_display_path.sv)、[视频时序发生器](D:/contest/2026FPGA/yilingsi/case2/rtl/video/c2_video_timing_gen.sv)与[页切换控制器](D:/contest/2026FPGA/yilingsi/case2/rtl/video/c2_page_flip_ctrl.sv), SystemVerilog源码, 2026.

[R7] 本项目. [板卡无关系统顶层](D:/contest/2026FPGA/yilingsi/case2/rtl/system/c2_renderer_system.sv)、[架构记录](D:/contest/2026FPGA/yilingsi/case2/architecture.md)与[项目状态](D:/contest/2026FPGA/yilingsi/case2/README.md), 2026.

[R8] 本项目. [验证范围与结果索引](D:/contest/2026FPGA/yilingsi/case2/verification.md)及[最终XSim回归记录目录](D:/contest/2026FPGA/yilingsi/case2/tb/xsim_newguide_signoff_20260831), 2026-08-31. 复现入口：[Run-NewguideRegression.ps1](D:/contest/2026FPGA/yilingsi/case2/scripts/Run-NewguideRegression.ps1).

[R9] AMD Vivado 2023.1生成的本项目报告. [渲染引擎资源报告](D:/contest/2026FPGA/yilingsi/case2/synth_proxy/render_cmd_mem_engine_util.rpt)与[系统AXI/IP-stub资源报告](D:/contest/2026FPGA/yilingsi/case2/synth_proxy/c2_renderer_system_ip_stub_util.rpt), 2026-08-31. 目标器件：xc7a35tcsg324-1；未包含真实厂商IP内部资源和有效时序约束.

[R10] Efinity生成的本项目报告. [Ti60F225最终结构映射报告](D:/contest/2026FPGA/yilingsi/case2/efinity_smoke/outflow_sv_axi_final/case2_rtl_probe_axi_final.map.rpt), 2026. 该探针存在端口绑零与逻辑裁剪，不是完整板级实现报告.

[R11] 本项目. [Efinity/Sapphire/Ti60F225集成交接记录](D:/contest/2026FPGA/yilingsi/case2/efinity_smoke/GUI_HANDOFF.md), 2026. 实际IP版本、接口、时钟和引脚以生成文件及原理图为准.

## 附录A 命令格式与控制寄存器

### A.1 256位渲染命令

表A-1按打包命令的位号给出当前ABI。软件将完整命令划分为8个32位字，`CMD_WORDn`对应原始命令的`[32n+31:32n]`。字段存在跨字边界的情况，驱动应显式移位和掩码打包，不依赖C编译器的位域布局。命令组装与驱动实现尚未完成，下表描述的是已有RTL接口。[R3]

表A-1 渲染命令字段

| 位范围 | 字段 | 宽度/单位 | 当前含义 |
|---|---|---|---|
| [2:0] | op | 3 bit | 0：NOP；1：Fill；2：Copy；3：Alpha；4：Color Key |
| [10:3] | flags | 8 bit | 当前不选择融合模式；位0/1为未来ABI保留提示，不能当作现有Alpha/Key使能 |
| [12:11] | pixel_fmt | 2 bit | 当前仅支持编码0，即RGB565 |
| [15:13] | reserved_lo | 3 bit | 保留，软件宜写0 |
| [47:16] | src_addr | 32 bit/字节地址 | 源矩形基地址 |
| [79:48] | dst_addr | 32 bit/字节地址 | 目标矩形基地址，也是混合/透明色操作的背景地址 |
| [95:80] | width | 16 bit/像素 | 矩形宽度 |
| [111:96] | height | 16 bit/像素 | 矩形高度 |
| [127:112] | src_stride_bytes | 16 bit/字节 | 源图相邻两行起点的地址间隔 |
| [143:128] | dst_stride_bytes | 16 bit/字节 | 目标图相邻两行起点的地址间隔 |
| [175:144] | color | 32 bit | Fill使用低16位RGB565颜色 |
| [183:176] | alpha | 8 bit | 单条命令共享的混合系数，范围0—255 |
| [199:184] | color_key | 16 bit | RGB565透明色比较值 |
| [255:200] | reserved_hi | 56 bit | 保留，软件宜写0 |

有效像素的地址遵循`base + y × stride_bytes + 2 × x`。使用中的基地址和stride均应保持两字节对齐，stride不小于`2 × width`。NOP不使用矩形地址、尺寸及stride，Fill不使用源surface；格式和操作码仍按当前解析器检查。Copy、Alpha和Color Key在启用行缓存路径时还受行RAM容量限制，Fill不因行RAM容量而限制矩形宽度。地址范围、整数溢出、裁剪和源目标重叠策略需在软件/系统层定义。[R3][R4]

### A.2 CSR偏移与语义

表A-2中的地址是12位CSR窗口内的字节偏移，不是Sapphire系统绝对地址。实际基地址应由系统互连、BSP和链接脚本共同确定，当前为【待补充：CSR窗口基地址】。控制侧按对齐的32位访问使用；已有AXI4-Lite适配器对非全字写返回SLVERR，且不修改CSR。[R3][R5]

表A-2 当前CSR映射

| 偏移 | 名称 | 访问 | 含义 |
|---|---|---|---|
| 0x00—0x1C，步长4 | CMD_WORD0—7 | 读/写 | 命令暂存字，WORD0对应最低32位 |
| 0x20 | CMD_SUBMIT | 写 | 写任意值，将8字快照提交至单项pending槽 |
| 0x24 | STATUS | 读 | FIFO、引擎、显示、错误及pending状态 |
| 0x28 | PAGE_REQUEST | 写 | 请求页面编号，默认PAGE_W=1取bit0 |
| 0x2C | PAGE_STATUS | 读 | 活动页、待切换页和控制器pending |
| 0x30 | ACCEPTED | 读 | parser消费的命令数，包含随后被判为非法的命令 |
| 0x34 | COMPLETED | 读 | engine产生完成事件的次数，包含错误完成 |
| 0x38 | MEM_ERR | 读 | parser统计的engine错误完成次数；名称不意味着仅DDR物理错误 |
| 0x3C | DROPPED | 读 | parser拒绝数与FIFO诊断计数之和，不能直接解释为丢失命令条数 |
| 0x40 | REQ_COUNT | 读 | 渲染引擎抽象存储请求计数，不是整机全部AXI请求数 |
| 0x44 | PIXEL_COUNT | 读 | 渲染引擎像素数据阶段计数，不是成功提交的帧数 |
| 0x48 | DISP_PIXELS | 读 | 显示路径像素计数 |
| 0x4C | DISP_ERRORS | 读 | 显示路径累计错误计数 |
| 0x50 | MEM_READS | 读 | 当前渲染/显示存储路径的读请求计数 |
| 0x54 | MEM_WRITES | 读 | 当前渲染/显示存储路径的写请求计数 |
| 0x58 | MEM_RSP | 读 | 仲裁器读响应beat计数，不包含独立AXI B写完成次数 |
| 0x5C | LAST_ERROR | 读 | parser错误有效脉冲、错误码和截断后的序号 |

`STATUS`的bit0—8依次对应命令FIFO满、parser忙、engine忙、display忙、显示欠载、存储错误状态、页控制器pending、命令提交pending和页面提交pending；bit15:9为FIFO占用量的低7位。默认双页配置下，`PAGE_STATUS`的bit0为活动页，bit8为待切换页，bit16为页控制器pending。命令被CSR接收、进入FIFO、经parser消费、被engine执行和写完成是不同事件，软件不能只用一个计数器代替完整生命周期判断。[R3][R7]

`LAST_ERROR`的bit0直接反映单周期`parser_error_valid`，bit7:4为保留的错误码，bit31:8为错误命令序号低24位；当前不是读清的黏滞错误有效位。错误码0—5分别表示无错误、非法操作码、非法像素格式、非法尺寸、非法stride和地址未对齐。`DROPPED`中的FIFO计数在每拍`in_valid && !in_ready`时增长，而提交槽会在背压期间保持valid，因此合法等待也可能被计入。稳健驱动需要补齐明确的完成、拒绝和超时判定契约，不能从这些混合量直接计算成功率。[R3][R7]

### A.3 存储握手约定

抽象请求的`req_addr`是字节地址，`req_len=N-1`表示N个16位像素beat。读数据通过有序`rsp_*`返回；写请求接受后，通过独立`wr_*`输送数据，末拍标记`wr_last`，并通过`wr_rsp_*`返回提交结果。写数据结束与写完成不能合并，当前宽AXI适配器将B通道映射为写完成响应。任一有效通道在背压期间应保持有效及负载稳定，错误恢复仍依赖下游最终结束已接受的事务；当前没有无限停顿下的超时收敛保证。[R4][R5]

## 附录B 工程与证据索引

| 内容 | 本地位置 | 用途 |
|---|---|---|
| 系统顶层 | [c2_renderer_system.sv](D:/contest/2026FPGA/yilingsi/case2/rtl/system/c2_renderer_system.sv) | 参数、模块连接及行为/IP分支 |
| 渲染方法 | [render_cmd_mem_engine.sv](D:/contest/2026FPGA/yilingsi/case2/rtl/mem/render_cmd_mem_engine.sv) | 行缓存、算法与读写状态机 |
| 总线适配 | [bus目录](D:/contest/2026FPGA/yilingsi/case2/rtl/bus) | 控制面及宽数据面 |
| 显示与页切换 | [video目录](D:/contest/2026FPGA/yilingsi/case2/rtl/video) | 时序与页控制 |
| IP边界 | [ip目录](D:/contest/2026FPGA/yilingsi/case2/rtl/ip) | 时钟/CDC/视频命名黑盒 |
| 自检与日志 | [verification.md](D:/contest/2026FPGA/yilingsi/case2/verification.md) | 用例范围、记录和复现入口 |
| 资源与理论预算 | [resource_budget.md](D:/contest/2026FPGA/yilingsi/case2/resource_budget.md) | 原始容量及带宽推导背景 |
| 更正版需求分析 | [官方补充资料概括与赛题二差异分析.md](D:/contest/2026FPGA/yilingsi/resource/官方补充资料概括与赛题二差异分析.md) | 新旧要求差异与实施范围 |

## 附录C 待补充材料清单

| 材料编号 | 待补充内容 | 对应正文 |
|---|---|---|
| C01 | 学校、队名、队员、指导教师、正式作品名称 | 封面 |
| C02 | 赛板修订号、原理图/BOM、引脚与时钟约束 | 第1、6章 |
| C03 | 真实SoC总图及跨时钟域边界图 | 第2、4章 |
| C04 | 命令、burst、写响应及换页代表性波形 | 第3—5章 |
| C05 | Sapphire/DDR3/PLL/HDMI/互连IP配置、版本与导出端口 | 第6章 |
| C06 | BSP、驱动接口、缓存策略、超时和错误恢复实现 | 第4、6章 |
| C07 | DDR自测、HDMI照片、完整AXI联合验证 | 第6章 |
| C08 | Ti60完整系统利用率、SDC、布局布线与STA | 第5、6章 |
| C09 | 同场景CPU/硬件帧时间、完成帧率与加速比 | 第6章 |
| C10 | Alpha/Color Key游戏、稳定精灵数量、长时间运行与固化启动 | 第6、7章 |
| C11 | 最终性能结论、截图与演示视频说明 | 摘要、第8章 |
