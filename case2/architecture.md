# 赛题二底层架构与系统框架

> 当前状态：板卡无关功能 RTL、`c2_renderer_system` 组装框架、AXI4-Lite CSR
> 适配器、AXI4 Full DDR3 适配器以及 Vivado XSIM 回归已经形成闭环；DDR3
> controller/PHY、时钟、CDC、HDMI PHY 和 Sapphire 系统仍是明确的厂商 IP/板级
> 边界。本状态不代表已经通过含真实 IP 的 Efinity 布局布线或实板验证。

## 1. 系统拼装

```text
Sapphire RISC-V AXI master -> interconnect / Full-to-Lite bridge (if needed)
             -> c2_axi4lite_csr_adapter -> generic CSR
             -> c2_csr_cmd_bridge -> command FIFO/parser
                                            |
                       render_cmd_mem_engine (m0，源/背景行级 read burst)
                         descriptor + wr data + wr response
                                            |
display timing -> rect burst reader -> line FIFO (m1 read)
                                            |
                               c2_mem_arbiter_2m_owner
                                            |
                             abstract memory transaction
                                            |
              c2_mem_to_axi4_adapter -> DDR3 controller/PHY IP -> DDR3

vblank -> page commit -> next-cycle capture/prefetch -> active scanout
                                                     -> HDMI PHY blackbox
```

`c2_renderer_system.sv` 是板卡无关的 assembly top，不直接绑定 DDR3 引脚、PLL、
Sapphire 或 HDMI 物理引脚。默认分支使用行为内存和同源时钟，可在 Vivado XSIM
中运行；`USE_EXT_MEM_IP=1` 选择实际 AXI4 Full adapter/端口，
`USE_VIDEO_PHY_IP` 和 `USE_CLOCK_RESET_IP` 选择尚待实现的命名黑盒分支。
`c2_axi4lite_csr_adapter` 和 `c2_mem_to_axi4_adapter` 是可综合的
板卡无关协议层，应放在 generic system 与 Efinity 生成 IP 之间，不替代 Sapphire、
DDR3 controller/PHY 或 HDMI PHY 本身。

## 2. 命令和像素语义

一条命令描述一个矩形操作。地址和 stride 的单位为 byte，width/height 的单位为
pixel，第一版数据通路固定为 RGB565，像素地址为
`base + y*stride + x*2`。

| op | 含义 | 读源 | 写目的 |
|---:|---|---|---|
| 0 | NOP | 否 | 否 |
| 1 | SOLID_FILL | 否 | 是 |
| 2 | BLOCK_COPY | 是 | 是 |
| 3 | ALPHA_BLEND | 前景和背景 | 是 |
| 4 | COLOR_KEY_COPY | 源与完整背景行 | 是；key 命中保持背景 |

不支持旋转、缩放、负 stride 和任意重叠 Copy。零尺寸、未对齐地址、非法
stride、使用中的奇数stride、未知 op 或超过行缓存容量的命令会以错误完成，不发出
访存事务。NOP不检查未使用stride，Fill不检查源stride。

Alpha 参考公式为：

```text
out = (fg * alpha + bg * (255-alpha) + 128) / 255
```

上述为逐通道整数除法，沿用现有参考模块的 +128 偏置，再饱和到 RGB565 通道
范围。当前 RTL 保持 bit-exact 行为；未来若为时序或资源改写为 DSP、LUT 或
移位近似，仍需与该参考结果逐像素比对，不直接把 /255 改成 /256。

## 3. 存储事务、行级 burst 和 owner

基础 descriptor/read-response 通道为：

```systemverilog
req_valid, req_ready, req_write, req_addr, req_len, req_wdata, req_wstrb
rsp_valid, rsp_ready, rsp_rdata, rsp_last, rsp_error
```

`req_addr` 是 byte address，`req_len=N-1` 表示 N 个连续 beat。无 transaction ID，
因此读响应必须有序，最后一拍用 `rsp_last=1` 标记，并在 `rsp_ready=0` 时保持
payload 稳定。

写事务分为独立数据阶段和提交响应阶段：

```systemverilog
wr_valid, wr_ready, wr_data, wr_strb, wr_last, wr_error
wr_rsp_valid, wr_rsp_ready, wr_rsp_error
```

系统 wrapper 同时启用 `READ_BURST_ENABLE=1` 和 `WRITE_BURST_ENABLE=1`。对
Copy/Alpha/Color-Key，源行按 `MAX_READ_BEATS` 和 4 KiB 边界拆成连续读
descriptor；Alpha 与 Color-Key 随后用相同规则读取完整背景行。单个同步双口行
RAM 先保存源行，背景响应到达时逐拍读取源像素并把计算结果覆盖回同一 RAM，因而
无需再增加一块完整行缓存。Copy 只需源读，Solid Fill 不需源/背景读。

渲染器完成一行计算后，再把结果拆成一个或多个写 descriptor。每个读写段同时受
两个上限约束：

- 读/写 beat 数分别不超过 `MAX_READ_BEATS`/`MAX_WRITE_BEATS`；
- 默认 `READ_BOUNDARY_BYTES=WRITE_BOUNDARY_BYTES=4096`，任何 descriptor 都
  不跨 4 KiB 边界。

Color Key 路径读取完整背景行，并只在 key 命中位置选择背景，其他位置选择源像素，
随后写回完整目的行。这个实现增加一些读带宽，但让源、背景和目的写都保持行级
burst。引擎发完 `wr_last` 后不会立即报告命令完成，而会等待对应 `wr_rsp`；该响应
映射到 AXI B，或映射到 DDR3 控制器的写提交/错误指示。

`c2_mem_to_axi4_adapter` 每次处理一个 abstract descriptor，将连续 16-bit RGB565
beat 聚合为参数化宽度的对齐 AXI4 Full INCR burst。首尾未使用 byte lane 通过
`WSTRB=0` 屏蔽，读数据按原请求地址拆回 16-bit beat；B 映射为唯一 `wr_rsp`，
RRESP、RID、RLAST 和内部 `wr_last` 异常均进入可终止、可恢复的错误路径。当前
实现单 outstanding，单个 descriptor 最多映射为 256 个 AXI beat 且不得跨 4 KiB。
AW与W独立推进，WVALID不等待AWREADY；支持全部W先于AW完成，两个通道均握手
完毕后才进入B等待。因此可连接等待WVALID才接受AW的合法从设备而不互等。

`c2_mem_arbiter_2m_owner` 的规则为：

1. 只在空闲时仲裁 descriptor；首次竞争可优先 display，之后竞争采用轮转，避免
   连续扫描请求永久饿死 renderer；
2. 读 descriptor 的 owner 保持到完整读响应结束或协议错误恢复完成；
3. 写 descriptor 的 owner 从 descriptor 被接受开始，跨越全部 `wr_*` 数据拍，
   一直保持到下游 `wr_rsp` 被相同 master 接受；
4. `wr_last` 提前/缺失或 beat 错误会累计协议错误，但不会绕过最终写响应；AXI
   适配器在 AW 已发出的情况下会用零 `WSTRB` 补齐剩余 W beat，合法结束 AXI burst；
5. owner 有效期间，另一 master 的 descriptor、写数据和响应均被隔离。

因此真实 memory adapter 必须为每个已接受的写 descriptor 产生且只产生一个
`wr_rsp`，即使写数据或控制器提交失败也要返回错误响应，不能让 owner 永久等待。
旧 `c2_mem_arbiter_2m`、`READ_BURST_ENABLE=0` 和 `WRITE_BURST_ENABLE=0` 仅保留
给 legacy 单 beat 回归；系统 top 使用 owner-aware 的读写 burst 路径。

## 4. 显示、切页和预取时序

显示链为：

```text
c2_video_timing_gen
       -> vblank_start
       -> c2_page_flip_ctrl commit
       -> 下一拍 prefetch_start：捕获新 active page、清 FIFO
       -> 再下一拍启动 c2_rect_burst_reader
       -> c2_line_fifo
       -> 下一个 active frame 扫描输出
```

切页在垂直消隐开始时提交，`prefetch_start` 延迟一拍，因此显示路径捕获到的是
已经更新的 page base，而不是旧页。显示读取器利用 vblank 提前填充 line FIFO；
到下一个 active frame 时，只有 FIFO 已有数据才会打开整帧消费。复位后的第一帧
没有前一段 vblank 可供预取，设计上整帧保持黑屏，不把半帧或错位像素送给 PHY。

固定光栅不能被 ready/valid 任意暂停。真实视频 PHY 在 active video 期间必须持续
保持 `pixel_ready=1`；若 active 期间拉低 ready，RTL 将其记录为显示错误，而不是
把后续像素移到错误坐标。FIFO 深度和外存仲裁必须按最坏停顿保证下一帧可用。

Page request 与 renderer completion 彼此独立。软件应只渲染 inactive page，并在
对应命令成功完成后再提交 page request；vblank commit 本身不能补偿过早翻页。

系统默认 XSIM 中 system/pixel 同时钟。启用 clock IP 后，页请求/状态经过
`c2_page_cdc_blackbox`，显示读事务经过 `c2_mem_cdc_blackbox`；其真实 CDC
结构必须在 Efinity 和实板时钟方案确定后实现。当前 memory-CDC 端口只覆盖显示
descriptor/read response，不带 renderer 的 burst write-data/`wr_rsp`，不能当作
通用写事务 CDC。

## 5. 行为模型和 IP 黑盒边界

`render_owner_mem_model` 仅用于仿真，提供 descriptor、写数据、`wr_rsp` 和有序
读响应，不代表可综合的 framebuffer。`tb_c2_renderer_system_ip_stub` 只对空黑盒
分支执行 `xvlog`/`xelab` 结构检查，空黑盒不能运行功能 xsim。

本轮完整 Vivado XSIM 回归位于 `tb/xsim_newguide_signoff_20260831`：11 项展开
检查、10 项功能仿真均 PASS，覆盖 AXI4 64/128-bit、AW/W 乱序与 W 先于 AW、
RID/RLAST 错误恢复、4 KiB 边界及奇数 stride 拒绝。此证据仍限于 RTL/行为模型。

已经完成且保持厂商无关的总线适配层包括：

- `c2_axi4lite_csr_adapter`：独立捕获 AW/W，允许二者任意先后到达，读写各单
  outstanding；CSR 目前只接受完整 32-bit word write，partial `WSTRB` 返回
  `SLVERR`，B/R 在背压期间保持稳定；
- `c2_mem_to_axi4_adapter`：把 abstract memory beat 聚合/拆分为 AXI4 Full burst，
  处理首尾 byte lane、B/R 错误及写流协议恢复；它是 controller 前端，不含 DDR3
  training、refresh、PHY 或引脚逻辑。

仍需由 Efinity IP 或板级 wrapper 替换/实现的边界包括：

- `c2_clock_reset_blackbox`：PLL、锁定指示和各时钟域复位同步；
- DDR3 controller/PHY：接到当前 system 的 `m_axi_*` 主接口以及
  `ext_mem_init_done/error`；旧 `c2_ext_mem_adapter_blackbox` 只保留 legacy
  native-interface 说明位置，当前 system 不再实例化；
- `c2_mem_cdc_blackbox`、`c2_page_cdc_blackbox`：跨时钟异步 FIFO/握手；
- `c2_video_phy_blackbox`：HDMI TX PHY、serializer 和 IO；
- `c2_sapphire_csr_blackbox`：Sapphire 系统封装锚点；板卡版通过
  `c2_axi4lite_csr_adapter` 接到通用 CSR，当前不实例化进 generic system top。

黑盒只保证接口位置明确。本次 Ti60 Efinity structural map 报告为
`efinity_smoke/outflow_sv_axi_final/case2_rtl_probe_axi_final.map.rpt`，包含 2,384
EFX_LUT4、2,134 EFX_FF、804 EFX_ADD、0 RAM、0 DSP。该工程仍使用空 IP/stub，
AXI 响应绑 0 且未启用 AXI4-Lite，因此只能在结构检查语境引用：逻辑会因无真实
消费者而被裁剪，不能据此宣称 DDR3、HDMI、PLL 或 Sapphire 已集成，也不能作为
最终资源/Fmax 结论。DDR3 training/refresh/PHY、CDC、HDMI PHY、引脚约束、时序
收敛和板上稳定性均未由 Vivado XSIM 或该 structural map 验证。

## 6. 资源和性能边界

默认 `LINE_BUFFER_PIXELS=4096`、`DATA_W=16`，行缓存原始容量为 65,536 bit，
按 10-Kbit embedded memory 原始容量约需 7 个块。默认 line FIFO 为
`1024×17=17,408 bit`，约需 2 个 10-Kbit 块。两者均已改成无 RAM 复位的同步读
结构；Vivado/Artix-7 无约束代理综合分别得到 2×RAMB36E1 和 1×RAMB18E1。
engine 单独代理的最终顺序重跑结果为 2,265 LUT、647 FF、2×RAMB36、0 DSP。
本轮系统 top 代理为 3,680 LUT、
3,840 FF、2×RAMB36、1×RAMB18、0 DSP；其中 AXI4-Lite/AXI4 Full 子层分别为
115/100 和 459/439（LUT/FF），已包含在系统总量内，不能重复相加。这些数据不含
PLL/CDC/DDR3/HDMI/Sapphire IP，也没有有效的板级时序
结论；实际 Ti60 RAM 块数、DSP/LE/XLR 映射仍必须以含真实 IP 的 Efinity 报告为准。

RGB565 双 framebuffer 的容量和并行 scanout+render 的带宽下限见
`resource_budget.md`。典型最低流量为：640×480@60 的 scanout/Copy/Alpha 分别
约 36.864/110.592/147.456 MB/s；1280×720@60 分别约
110.592/331.776/442.368 MB/s。该数值尚未计刷新、仲裁、读写切换和控制器效率，
也不是已达到的实测吞吐。

## 7. 板卡实施顺序

1. 用 Efinity 生成 PLL/复位网络，验证 lock、复位释放和实际 pixel/system 时钟；
2. 按竞赛板的 x16 DDR3 器件和原理图生成 controller/PHY，先验证 training、固定
   图案、byte lane、4 KiB/最大 burst 和 `wr_rsp` 提交语义；
3. 按实际时钟关系实现 page/memory CDC，并在背压下验证事务和 owner 不丢失；
4. 把 Sapphire AXI master 经地址译码/interconnect、必要的 Full-to-Lite 桥接入
   CSR 适配器，确认完整 word write、软件写 inactive page、完成轮询和 vblank flip；
5. 接入 HDMI TX PHY、引脚和 IO 约束，验证 640×480@60 以及 active 期间 ready 恒高；
6. 完成 Efinity 综合、布局布线、时序分析和板上 ILA/UART/长时间稳定性测试。

Vivado 启动统一使用 `scripts/Start-DetachedEdaTool.ps1`，它创建
`run_detached_tool.py` worker：由本机 `Win32_Process` WMI 服务隐藏启动 worker，
worker 确认 `in_job=false` 后才调用 `xvlog`、`xelab` 或
`xsim`。普通 `CREATE_BREAKAWAY_FROM_JOB` 在本机实测仍为 `in_job=true`，因此
“分开执行三个命令”不能作为已经脱离 Windows Job 的证据，也不能保证 Codex 会话
异常时仿真不被连带终止。
