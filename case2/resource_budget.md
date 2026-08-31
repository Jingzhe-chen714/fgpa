# 赛题二资源、带宽和板级边界（RTL 评估版）

本文给出板卡无关 RTL 的容量和流量预算。当前证据来自源码检查、Vivado XSIM、
面向 Artix-7 的无约束综合代理，以及一次只含空 IP/stub 的 Ti60 Efinity structural
map。Vivado 代理用于检查 RAM-friendly 编码和大致逻辑规模，不能换算成 Ti60 的
最终资源或 Fmax；structural map 只能证明 Efinity 前端可接受当前结构。仍没有含
真实 Sapphire/DDR3/HDMI/PLL IP 的 Efinity P&R 报告，也没有实板功耗、时序或吞吐
数据。

## 1. Ti60 级资源基线

Ti60 数据手册列出的整片资源包括 62,016 LE、60,800 XLR、14,720 个 SRL8、
2.6 Mbit 嵌入式存储、160 个 DSP 和最多 32 个全局时钟；F225 封装有 4 个 PLL。
参考：[Ti60 数据手册](https://www.efinixinc.com/docs/titanium60-ds-v3.2.pdf)。

Sapphire、PLL、DDR3 controller/PHY 和 HDMI PHY 会先占用部分器件资源。下表仅描述
当前 RTL 的主要资源类型，不是综合结果。

| RTL 部分 | 原始规模/主要资源 | 当前判断 |
|---|---|---|
| command FIFO/parser、owner 仲裁器、状态机 | XLR/FF、小 RAM、计数器 | 容量风险较低，关键是协议与时序 |
| 地址/stride、4 KiB 和最大 burst 分段 | 加法器、比较器、取模/边界控制 | 低到中等；常量 4 KiB 边界应可化简 |
| `render_cmd_mem_engine` 行缓存 | `4096×16 = 65,536 bit` | Vivado 代理已推断块 RAM；Ti60 原始容量约 7 个 10-Kbit 块，待 Efinity 确认 |
| `c2_line_fifo` | `1024×17 = 17,408 bit` | Vivado 代理已推断块 RAM；Ti60 原始容量约 2 个 10-Kbit 块，待 Efinity 确认 |
| `c2_mem_arbiter_2m_owner` | owner、长度、读/写/`wr_rsp` 状态和计数器 | 低到中等；owner 必须跨写响应保持 |
| `c2_axi4lite_csr_adapter` | AW/W 缓冲、B/R 响应和 CSR 仲裁 | 逻辑量低；partial WSTRB 本地返回 SLVERR |
| `c2_mem_to_axi4_adapter` | RGB565 宽拍聚合/拆包、首尾 WSTRB、AXI 状态 | 中等；当前单 outstanding，资源代理已独立测量 |
| RGB565 Alpha | 乘法、加法和 `/255` 的 bit-exact 参考逻辑 | 需用 Efinity 判断 DSP/LUT 映射和关键路径 |
| 视频时序/page flip/prefetch | 计数器、控制状态和少量寄存器 | 逻辑量低，风险主要在 pixel clock、外存停顿和 PHY |

这里的“约 7 块”和“约 2 块”只按原始 bit 数除以 10 Kbit 后向上取整。两者合计
82,944 bit，约为 2.6 Mbit 片上存储的 3.2%，尚未计命令 FIFO 和厂商 IP。实际
Efinix embedded-memory 数量、端口/宽度浪费和时序必须由 Efinity 报告确认。

## 2. Vivado 综合代理结果（不是 Efinity 结果）

在 `xc7a35tcsg324-1` 上进行无时序约束综合，所有板级 IP 选择空黑盒、排除仿真
framebuffer，得到：

| 代理综合对象 | LUT | FF | RAM | DSP | 解释 |
|---|---:|---:|---:|---:|---|
| `render_cmd_mem_engine` 单独 | 2,265 | 647 | 2×RAMB36 | 0 | 最终代码顺序重跑结果，已完成 |
| `c2_line_fifo` 单独 | 45 | 34 | 1×RAMB18 | 0 | `1024×17` 已确认使用块 RAM |
| `c2_renderer_system` IP-stub top | 3,680 | 3,840 | 2×RAMB36 + 1×RAMB18 | 0 | 本轮结果，已含两个 AXI 适配器；不含真实厂商 IP |
| system 内 `c2_axi4lite_csr_adapter` 子层 | 115 | 100 | 0 | 0 | 已计入系统总量，不是额外开销 |
| system 内 `c2_mem_to_axi4_adapter` 子层 | 459 | 439 | 0 | 0 | AW/W 独立推进、宽拍聚合/拆包；已计入系统总量 |

报告位于 `synth_proxy/*_util.rpt`。engine 最终独立代理为 2,265 LUT/647 FF；
`synth_proxy/engine_axi_final_run/sequential_retry.status.json` 记录顺序重跑已完成、
exit code 为 0 且不在 Windows Job 内。源/背景读复用同一行 RAM，没有增加第二块
完整行缓存。
系统代理中的 8×256 command FIFO 因异步复位和较浅深度使用寄存器，仍是 FF 的
主要来源之一。它可在 Efinity 阶段按资源压力决定保留、改成无复位 RAM-friendly
FIFO，或替换厂商 FIFO。当前两块大缓存已经消除了被铺成数万触发器的风险。

本轮 system 的 3,680 LUT/3,840 FF 是包含两个 AXI 适配器的顶层综合结果；表中的
AXI 子层用于解释构成，不能再次加到顶层总量上。上述 Xilinx LUT/FF 数不能与
Ti60 LE/XLR 作一比一换算；PLL、CDC、DDR3、HDMI 和 Sapphire IP 资源仍完全未计入。

本次 Ti60 structural map 报告
`efinity_smoke/outflow_sv_axi_final/case2_rtl_probe_axi_final.map.rpt` 显示
2,384 EFX_LUT4、2,134 EFX_FF、804 EFX_ADD、0 RAM、0 DSP。该工程仍采用空
IP/stub，AXI 响应绑 0 且未启用 AXI4-Lite；0 RAM 和偏小的逻辑量受到黑盒/无真实
消费者裁剪影响，只能在结构检查语境引用，不能与上表比较，更不能作为 Ti60
最终占用率。只有生成真实 DDR3/HDMI/PLL/Sapphire IP、加入引脚与时钟约束并完成
Efinity P&R 后，才可引用器件资源、Fmax 和余量。

## 3. Framebuffer 和片上缓存容量

| 项目 | 原始存储量 | 预算判断 |
|---|---:|---|
| 640 像素 RGB565 行 | 10,240 bit（1,280 B） | 约 1 个 10-Kbit 块的原始容量，实际可能取 2 块 |
| 默认渲染行缓存 4096×16 | 65,536 bit（8 KiB） | 约 7 个 10-Kbit 块，如成功推断 |
| 默认显示 FIFO 1024×17 | 17,408 bit | 约 2 个 10-Kbit 块，如成功推断 |
| 1280 像素 RGB565 行 | 20,480 bit（2,560 B） | 至少约 2 个块，按端口模式取整 |
| 640×480 RGB565 单 framebuffer | 4,915,200 bit（614,400 B） | 超过片上容量，必须放外存 |
| 640×480 RGB565 双 framebuffer | 9,830,400 bit（1,228,800 B，约 1.17 MiB） | 必须放外存 |
| 1280×720 RGB565 双 framebuffer | 29,491,200 bit（3,686,400 B，约 3.52 MiB） | 必须放外存 |

`render_owner_mem_model` 中的数组是仿真存储，不应参加板卡综合，也不能因为 XSIM
能容纳整帧就把 framebuffer 预算到片上 RAM。

竞赛板补充资料给出的外存为 MT41J128M16JT-125、256 MB（2 Gbit）、x16 DDR3，
标称最高 800 Mbps。640×480 RGB565 双缓冲约占 1.17 MiB，只占该 DDR3 容量约
0.46%；容量不是主要风险，真正风险是 controller/PHY training、持续有效带宽、
读写切换和最坏仲裁停顿。以 x16、800 Mbps 粗算的物理峰值为 1.6 GB/s，这只是
总线线速，不能直接当作应用层可持续吞吐。

## 4. 并行 scanout + render 的带宽下限

以下采用 RGB565、60 Hz 和十进制 MB/s，仅统计 active pixel 的必要字节数：

- Scanout：显示读取 1 次；
- Copy：显示读取 1 次，加 renderer 的源读 1 次和目的写 1 次，共 3 次；
- Alpha：显示读取 1 次，加 renderer 的前景读、背景读和目的写，共 4 次。
- Color-Key：当前行级 burst 实现读取完整源/背景行再写目的，流量与 Alpha 相同。

| 分辨率/操作 | 每像素等效外存访问 | 最低流量 |
|---|---:|---:|
| 640×480@60 Scanout | 1×2 B | 36.864 MB/s |
| 640×480@60 Scanout + Copy | 3×2 B | 110.592 MB/s |
| 640×480@60 Scanout + Alpha | 4×2 B | 147.456 MB/s |
| 640×480@60 Scanout + Color-Key | 4×2 B | 147.456 MB/s |
| 1280×720@60 Scanout | 1×2 B | 110.592 MB/s |
| 1280×720@60 Scanout + Copy | 3×2 B | 331.776 MB/s |
| 1280×720@60 Scanout + Alpha | 4×2 B | 442.368 MB/s |
| 1280×720@60 Scanout + Color-Key | 4×2 B | 442.368 MB/s |

这些是理论下限，不含刷新、训练维护、仲裁空隙、读写 turnaround、命令开销、
CDC、PHY 效率和最坏停顿。源、背景和目的写均已改为有界行级 burst，它减少
descriptor/切换开销，但不会减少像素字节数。renderer、owner 和 AXI4 Full 适配器
当前仍采用单 outstanding，因此不能用大量并发请求隐藏 DDR3 延迟；“物理峰值带宽
足够”也不等于已经达到对应帧率。性能闭环仍需含真实 IP 的 Efinity 时序和实板测量。

通用 Ti60 F225 开发板指南可能描述不同的 HyperRAM 版本，不能覆盖本次竞赛套件。
本项目按用户提供的竞赛板资料采用 x16、256 MB DDR3 架构；最终器件 speed grade、
引脚、bank 电压和 Efinity DDR3 IP 参数仍以实际板卡 BOM/原理图为准。通用器件参考：
[Ti60 F225 开发板指南](https://www.efinixinc.com/docs/ti60f225-devkit-ug-v2.4.pdf)。

## 5. 已能在 RTL/XSIM 完成的工作

不安装 Efinity 也可验证：

1. 256-bit 命令字段、FIFO/parser 和 RGB565 Fill/Copy/Alpha/Color-Key 行为；
2. 地址/stride、`MAX_READ_BEATS`/`MAX_WRITE_BEATS` 和 4 KiB 读写 descriptor
   分段，以及源/背景行级读、同行 RAM 覆盖计算和行级写回；
3. descriptor、独立写数据、延迟 `wr_rsp`，以及 owner 从 descriptor 到写提交响应
   的保持和错误恢复；
4. 多 beat 有序读响应、`rsp_last`、显示 burst reader 和 line FIFO 背压；
5. vblank page commit、下一拍 page capture/prefetch、首帧黑屏和无欠载扫描；
6. CSR→parser→renderer→共享存储→page flip→视频流的小栅格系统连线；
7. AXI4-Lite AW/W 任意先后、partial WSTRB 错误和 B/R 背压，以及 AXI4 Full
   宽拍聚合、首尾 WSTRB、读拆包、B/R 错误和协议恢复。

本轮完整 Vivado XSIM 证据位于 `tb/xsim_newguide_signoff_20260831`：11 项展开
检查和 10 项功能仿真均 PASS，包含 AXI4 64/128-bit、AW/W 乱序（含全部 W 先于
AW）、RID/RLAST 错误恢复、4 KiB 边界及奇数 stride 拒绝。这个数量不包括真实
DDR3/HDMI/PLL/Sapphire IP 的功能验证。

这些结果来自行为模型。IP stub 只能证明端口和 generate 分支能够被 Vivado 编译、
展开；Efinity structural map 同样只能证明 stub 结构被前端接受。两者都不能证明
任何厂商 IP 的功能、资源或时序。

## 6. 必须由 Efinity/IP/实板完成的工作

- 生成 PLL、各时钟域复位和真实约束，检查 clock lock、恢复/移除和 CDC；
- 按竞赛板 x16 DDR3 生成控制器/PHY，完成 training、刷新、byte lane、burst、
  4 KiB 规则和读写 turnaround 验证；
- 把抽象 `wr_rsp` 映射到 AXI B 或控制器写提交响应，并验证错误路径不会丢 owner；
- 根据真实 system/pixel/memory 时钟实现 page/memory async bridge；
- 将 Sapphire AXI4-Lite master 接到已完成的 CSR 适配器，并接入 HDMI TX PHY、
  serializer、IO 电平和引脚约束；
- 用 Efinity 报告确认 embedded RAM/DSP/XLR 映射、Fmax 和余量；
- 在板上测量 scanout+Copy/Alpha 吞吐、欠载、撕裂和长时间稳定性，并通过
  ILA/UART 或等价观测点定位问题。

因此当前可以判断协议和功能框架在 RTL/XSIM 阶段已形成闭环，且 AXI 协议层已有
可综合实现；但 Ti60 最终资源占用、Fmax、DDR3 效率和 HDMI 显示质量仍只能由
含真实 IP 的 Efinity P&R 与实板验证给出。
