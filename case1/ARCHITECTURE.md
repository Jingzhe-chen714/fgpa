# 赛题一：板卡无关 RTL 系统架构

## 1. 架构定位与证据边界

本目录把 Efinix 加密 IP/原语与便携 RTL 严格隔离，使 APB 控制、RAW ISP、framebuffer、CNN、DDR 调度和显示可以在没有 Efinity 与实体板时继续开发。

当前主组合顶层是 `rtl/top/c1_r1_portable_soc.sv`：

```text
Sapphire/APB ── CSR + ISP shadow/commit ── lifecycle/frame manager
                                                │
camera_clk RAW10 ─ async FIFO ─ R1 ISP ─ capture XRGB writer ─┐
                                                               │
DDR parameter arena ─ loader ─ atomic parameter bank ─┐        │
                                                       ▼        ▼
input XRGB reader ─ Resize/C8 ─ MicroStyle bridge ─ 22-stage engine
                                   │                    ▲
                                    └ tensor adapter ────┘
                                      3×8 MiB DDR banks
                                              │
                              optional 3-row C8 window-cache seam
                                 (`ENABLE_TENSOR_WINDOW_CACHE=1`)
                                              │
                                    64→AXI128 tensor bridge
                                              │
output XRGB writer ─ frame pair ─ dual display prefetch ─ 720p/OSD

seven ID-less AXI128 clients ─ round-robin transaction-lock arbiter ─ DDR seam
```

这里的 22-stage engine 是真实 signed-INT8 算术实现，不再是“opaque CNN”。其参数路径不再使用旧 flat-cache 的全局随机选择：128-bit ABI word 先顺序写入可推断 BRAM，每层开始时由多拍 OIHW walker 重排到固定的 64 个 Conv lane bank或 8 个 DW lane bank，再由 dot/DW core 顺序寻址。但当前 tensor adapter 仍是单 outstanding 的顺序 correctness-first 调度器，不是实时 tile accelerator。板前新增的 `model/tensor_perf_model.py`、`model/window_cache_perf_model.py`、独立 `c1_tensor_mem_axi128_packer`、`c1_tensor_mem_path_seam` 和七客户端 arbiter 压力回归分别量化优化方向、验证局部 packing/flush 协议和共享仲裁 forward progress；window cache 现在由显式 `c1_tensor_window_cache_axi_client` 封装并固定接入 portable SoC client-6，默认参数仍是 wire-level bypass。真实 adapter→cache→64-bit BFM、adapter→cache→单拍 AXI128 bridge→BFM、wrapper→client-6→arbiter→AXI BFM，以及当前源码 shape-scaled gate 矩阵 `c1_8x8_gate_20260825`/`c1_16x8_two_gate_20260825`/`c1_64x48_single_gate_20260825`/`c1_64x48_two_gate_20260825` 均已 PASS；这些都不是 640×480 端到端性能证明。

`c1_r1_integration_skeleton` 和 `c1_r1_boardless_frame_system` 继续保留作为较小回归层级；它们不是最终主顶层。

## 2. 模块层次与当前完成度

| 层次 | 已实现的真实功能 | 尚未闭合 |
|---|---|---|
| APB | 主 CSR、ISP CSR mux、PSTRB、PSLVERR、sticky IRQ/W1C | Sapphire 地址映射/PLIC |
| lifecycle | START 快照、参数换代、single-shot/continuous capture admission、3入2出 ownership、NN job、display pair swap、abort/flush | 长时间全系统随机并发 |
| capture | RAW10 CDC、R1 ISP、frame-table lookup、XRGB writer、silent discard/cleanup | MIPI packet/CRC 与真实传感器 |
| frame job | pair/config preflight、descriptor 双 bank、dispatcher、input/output DMA、safe drain | DDR QoS 与长帧压力 |
| CNN engine | 22 descriptor cache；Conv3×3、Conv1×1、DW、upsample、residual、final；128-bit ABI BRAM→逐层多拍 OIHW 重排→固定 Conv/DW lane bank；参数 scheduler/active generation；训练工件的 22 descriptor 已通过 RTL decoder/arena ABI 回归 | 640×480 trained artifact 全层 RTL 对比；负 WNS 关键路径继续流水化；Ti60 资源/时序签核 |
| tensor adapter/cache | 三 bank ping-pong/残差映射；SAME/stride2、window/group/raster；单 outstanding 64-bit req/rsp；三行 all-group C8 cache、注册化 seam、adapter sideband 与 `c1_tensor_window_cache_axi_client` client-6 边界已实现；动态 64-bit、真实 AXI bridge、client-6→arbiter→DDR BFM 及 portable SoC shape-scaled gate 矩阵已完成 | native 长帧的 burst/系统级 packing、多 outstanding、并行供数仍未闭合；native 性能待测 |
| tensor bridge | 64-bit read/write→单拍 AXI128，`addr[3]` 半字选择、WSTRB、RRESP/BRESP/RLAST | 性能合并/队列 |
| display | 原图、风格图、分屏、fail-black 四模式；bit7 OSD；双源 prefetch、720p timing、underflow CDC；首次 pair bootstrap feed 与单源未选中 line-store drain | HDMI/TMDS/PLL 与板上 FIFO 深度 |
| vendor seam | APB、RAW stream、AXI128、RGB/DE/HS/VS | Efinix MIPI/DDR/Sapphire/PLL/显示 IP |

## 3. 数据与控制路径

### 3.1 START 原子快照

软件先写 shadow CSR，再向 `CONTROL.START` 写 1。`c1_apb_csr` 在 busy 时拒绝 START 并返回 `PSLVERR`；`c1_r1_soc_control` 接受 START 后锁存当前 run 的 framebuffer table、width/height、pixel format、descriptor base/count、weight base、`0x098 TENSOR_BASE` 和 continuous/drop 策略。后续 APB 写只影响下一次任务，不能撕裂已启动任务。

参数 active bank 与 stage-config active generation 都采用完整批次成功后切换；失败的 shadow 装载不污染 active。config 允许作为可复用 preload cache 提前提交，因此失败 frame job 可能留下新 generation，但绝不会误 launch，也不承诺 job-level rollback。

### 3.2 Capture、silent discard 与 cleanup

camera seam 假定 vendor 侧已完成 CSI packet 校验和 RAW10 解包，sideband 与像素同 beat：

```text
raw10, x, y, valid/ready, SOF, EOL, EOF
```

capture FIFO 只是 CDC/弹性缓存，不是整帧缓存。single-shot 首帧被接纳后或系统未 armed 时，controller 关闭新帧 admission 并令 frontend 在 idle 状态持续消费 FIFO：无论 FIFO 头是 SOF 还是复位/禁用遗留的半帧，都静默丢弃到 EOF，不产生软件 drop 事件。显式资源不足的 `drop_frame` 才计数；abort、overflow 或输出 FIFO 错误进入 drain/recover，`cleanup_busy` 直到恢复到安全帧边界才释放。

### 3.3 真实 CNN 与 tensor 执行

`c1_r1_microstyle_system_bridge` 将同一份 22-descriptor snapshot 无损送给算术 engine 和 tensor adapter；两者都完成配置前不放行首个 C8 像素。engine 负责 OIHW signed-INT8 MAC、bias、per-channel multiplier/shift、round-away、saturation/ReLU；adapter 负责空间窗口、stride/padding、C8 group、upsample、residual bank 和中间 tensor 地址。

当前三 bank 固定映射避免 residual 被覆盖，默认每 bank 8 MiB：

```text
bank0 = tensor_base + 0 MiB
bank1 = tensor_base + 8 MiB
bank2 = tensor_base + 16 MiB
```

24 MiB 全部位于外部 DDR。software/SoC 合同要求 `tensor_base` 以 8 MiB 对齐并保证三个 bank 不越过 32-bit 空间；adapter 自身另做 8-byte 对齐与地址溢出防线。每个 64-bit read/write 都必须收到一次 response，且仅允许一个请求 outstanding；写请求也有 completion response。该协议便于自检，但不具备 15 fps 吞吐。

当前 engine 专项使用 8×8 定向/合成参数，adapter 专项使用 4×4 的完整 22-stage 小模型；portable SoC 的 shape-scaled 8×8/16×8 BFM 仍使用零参数功能性 arena，两者都没有装入 functional QAT arena 做 trained artifact RTL E2E。该缺口必须保留为 P0。

软件收到 DONE/ERROR terminal IRQ 后也不能立即复用本 job 的 framebuffer、descriptor、parameter 或 tensor 区。abort、display flush 或已提交 AXI transaction 可能仍在安全排空；必须通过 `c1_accel_wait_idle()` 观察 STATUS.BUSY=0 后才允许释放/复用内存。

### 3.4 三行 C8 tensor window cache

adapter 的真实循环是 `output_y -> output_x -> input_group -> 9 taps`。因此 resident row 不能只保存当前 group；完整行按 `x-major/group-minor` 保存所有 groups，索引为 `x * groups + group`。`c1_window_line_cache_c8` 的默认 payload 为三行×1280 words×64 bit，即 245,760 bit，并在 Artix-7 proxy 中推断为 7.5 BRAM tile、288 LUT、203 FF、0 DSP，100 MHz WNS +1.086 ns。

`c1_tensor_window_cache_seam` 位于 adapter 逻辑 req/rsp 与现有 64-bit memory path 之间。只有 Conv3×3/DWConv3×3 tap read 进入 cache；write、1×1、upsample、residual、final、sideband/address 不匹配和容量超限均旁路。注册前端先接受并快照一个上游逻辑请求，再以多拍 shift-add 完成范围和物理地址一致性分类；miss 后保持/重试的是内部 cache tap，不是已握手的上游请求。cache miss 逐 word refill 完整行，命中返回本地响应；所有 direct/refill response 都由注册 owner 路由。输入 tensor 范围内出现 write 后进入 coherence fallback，直到 flush 或下一 stage。加固后 seam 还会等待底层 cache 的配置完成结果：配置被拒绝时以 `CONFIG_REJECT` 禁用本 stage cache；请求已进入路由后若 cache 出现 runtime error，则后续请求安全降级为 direct bypass，而不留下悬空 cache owner。adapter 的仿真断言同时检查 stalled memory request/sideband、stalled stage config、cacheable 分类、WSTRB 和 8-byte 对齐。

abort 是 drain 而不是 cancel：已接受的前端请求、downstream transaction 与逻辑响应先排空；若配置范围计算期间 adapter 已呈现但尚未握手请求，`drain_front` 会在配置完成后接收并完成它，再清 cache/config。完整接口、地址公式、容量 guard 和后续 burst 条件见 `CACHE_INTEGRATION_CONTRACT.md`。portable SoC 默认 `ENABLE_TENSOR_WINDOW_CACHE=0` 仍直通；置 1 后 seam 已位于 adapter 与 bridge 之间，且 `tensor_cache_busy` 纳入软件 `system_busy` quiescence fence。enabled smoke 尚未发动态 tensor 请求，顶层 `flush_req` 也暂绑 0。

最终加固 seam 专项 run `1e6f562adbc34ea383932840b97aa0e4` 完成 17/17 logical req/rsp 与 50 个 downstream transaction，并定向命中 `cfg_rejects=1`、`runtime_fallbacks=1`；route lock 保证未取得 cache owner 的请求固定旁路、已取得 owner 的请求不产生重复 direct transaction。随后 64-bit 动态 run `9212d5a042ae4d9895a3162869e3815f` 让真实 sideband-enabled adapter 的完整 22-stage 4×4/8×4 自检流量穿过 seam/C8 到单 outstanding 64-bit BFM；它保持原 448 个 engine operands/32 个 final beats，得到 2,230/2,230 logical req/rsp、1,493 hit/19 miss、19 row refills/204 words，并把 1,810 个 logical reads 降为 `298 bypass + 204 refill = 502` 个 downstream reads，另完成 420 writes、1 次 memory error 与 5-cycle abort drain。

真实 AXI 动态 run `be4977424d9d484e80340f970d9904d0` 在相同 scoreboard 下继续串入 `c1_tensor_mem_axi128_bridge` 和严格 AXI128 BFM，完成 502/502 AR/R、420/420/420 AW/W/B、上下 lane 462/460、AW-first/W-first/same 318/81/21，并覆盖 AR/AW/W stall 1577/1583/1580、R/B gap 1194/915、B hold 2、error 1 和 abort 5。这里已经是真实单拍 AXI bridge 事务，但仍是小尺寸、单 outstanding；随后显式 client-6 wrapper 回归 `54d6d7ec0b28445f8f80edeb67281c72` 又穿过七客户端 arbiter 与 AXI BFM。当前源码 shape-scaled latest gate 矩阵完成：8×8 `AW/W/B=852/868/852`、`AR/R=1119/2199`；16×8 两帧 `AW/W/B=3376/3472/3376`、`AR/R=4185/5463`、`swaps=2 drops=0`；64×48 单帧 `AW/W/B=40224/41664/40224`、`AR/R=48427/51643`；64×48 两帧 `AW/W/B=80448/83328/80448`、`AR/R=96793/102295`、`swaps=2 drops=0`。tensor adapter 的 64-bit 几何/地址修复后，8×8 与 64×48 两帧又分别由 `c1_8x8_u64fix_gate_20260825`/`c1_64x48_two_u64fix_gate_20260825` 重跑通过；仍需长帧/QoS/性能化。

### 3.5 帧缓冲与显示

输入状态：

```text
FREE → CAPTURING → READY_NN → PROCESSING → READY_DISPLAY → DISPLAY → FREE
```

输出状态：

```text
FREE → PROCESSING → READY_DISPLAY → DISPLAY → FREE
```

采用 3 个输入和 2 个输出，因为 display 必须同时持有原图/风格图 pair，而 capture 与 NN 仍需前进。prefetch 在 core 域可提前运行；pixel 域只在 frame boundary/VSYNC 提交新 pair 的 ownership。没有新完整 pair 时重复当前 pair。首次 pair 尚无 current feed 时，`c1_r1_display_subsystem` 在两行 store primed 后启动 bootstrap feed；在 ORIGINAL/STYLED 单源模式中，未选中的 reader 由同一活动窗口发出 drain 请求，避免其 ping-pong bank 永久占用。core 域 pending pair 预取期间由 `display_hold_requests` 经两级 CDC 门控 pixel 请求，且控制器以 `!prefetch_loading_new_q` 禁止重复启动同一 pending pair；最终两帧回归验证了该 ownership 闭环。可选 display response FIFO（默认关闭）在 reader 与 line-store 之间保存 59-bit `{eof,eol,sof,y,x,rgb}` token；credit-only pre-AR gate 只限制尚未呈现的 burst，并保持 `ARVALID/payload` 稳定，`done/start_ready` 还要等 FIFO 与两组 line-store 排空。单帧 64×48、8×8 两帧和 64×48 两帧均已通过 QoS/ownership 回归，native 640×480 已完成逐像素 FIFO 预检；Vivado proxy 已测得 fifo128 相对 bypass 为 `+494 LUT/+44 FF/+304 LUTRAM`，但 FIFO 资源和 native 长帧 deadline 仍需 Efinity/板卡测量。四个 compositor mode 为：0 风格图居中、1 原图居中、2 左原图/右风格分屏、3 保留模式 fail-black；`DISPLAY_MODE[7]` 独立使能十六进制状态/告警 OSD。

## 4. AXI128 内存结构

`c1_r1_portable_soc` 的七个 client 为：

| client | 方向 | 功能 |
|---:|---|---|
| 0 | R/W | boardless frame job：表/config/input reader/output writer |
| 1 | W | capture XRGB writer |
| 2 | R | parameter loader |
| 3 | R | capture framebuffer-table reader |
| 4 | R | display original prefetch |
| 5 | R | display styled prefetch |
| 6 | R/W | `c1_tensor_window_cache_axi_client`：optional window-cache seam + tensor 64→AXI128 bridge |

仲裁器是 ID-less、按事务锁定的 round-robin baseline。被授权的 burst 必须通过终止 response/RLAST 后才释放 owner；这保证返回路由明确，但当前没有 per-client response FIFO。独立七客户端压力 run `bbaccd1453aa43368eebc4e1f5bdae5a` 已在 56 写+56 读、随机 AW/W/AR/B/R 停顿下观察到每客户端完整配额和读写并行；新增 client-6 wrapper 回归 `54d6d7ec0b28445f8f80edeb67281c72` 又在真实 slot 6→fabric→AXI BFM 上完成 4 次 refill AR、1 次旁路 AR 和 1 次写。顶层 gate 期间控制层在 foreground CNN admission 前等待 display prefetch quiescent，并在 boardless/NN active/request 期间禁止新 display refresh，以规避 display reader held R beat 对 tensor/NN 的头阻塞；可选 response FIFO 现在提供了一个板卡无关的、单帧/两帧已验证的 credit-only 修复路径，但默认仍是 compatibility bypass。由于 gate 不冻结 raster，双 bank line-store 在长 CNN 期间仍可能 underflow；native portable-SoC 长帧尚未把 `display_underflow_event`、FIFO occupancy 和 deadline 纳入 PASS。真实 15 fps 需要 QoS/优先级、burst 和 outstanding 重新设计。

现有 tensor bridge 将每个 64-bit 请求变成一个 `ARLEN/AWLEN=0`、`AxSIZE=4`、INCR 的 16 B AXI beat：地址对齐到 16 B，`addr[3]` 选择低/高 64 bit，写 strobe 映射到对应 8 byte。AW 与 W 可任意先后握手，所有 VALID payload 在 READY 前稳定；非 OKAY response 或读缺 `RLAST` 返回 `mem_rsp_error`。

frame/descriptor/parameter DMA 仍各自遵守 4 KiB、RLAST/WLAST 和 cancel/drain 合同。AXI VALID 一旦呈现不能撤回；取消后必须排空已提交事务，真实 R/B 错误不能被 cancel 掩盖。

### 4.1 共享 read/write owner+epoch fence（2026-08-28）

当前共享 AXI 数据路径仍由 `c1_axi_n_serial_arbiter_128` 负责；本阶段新增的
`c1_axi_shared_owner_epoch_fence` 只提供一个板卡无关的维护/epoch 控制 seam，
不复制或重写 AXI payload mux。arbiter 新增以下只读状态输出：

```text
read_busy / read_quiescent / read_owner
write_busy / write_quiescent / write_owner
```

`c1_axi_shared_owner_epoch_arbiter_128` 还把 `read_admit/write_admit` 与实际
`read_fire/write_fire` 作为显式端口导出，便于 CSR/监控逻辑接入而不依赖层次
探针。

它们直接观察既有事务状态和 owner 寄存器：`*_busy` 表示方向上仍有已选事务
（包括 stalled VALID/response skid），`*_quiescent` 表示该方向可安全换代，
`*_owner` 给出当前锁定的 client。新增输出不改变 round-robin 选择、事务锁定、
VALID 保持或 R/B 路由，因此 legacy named instantiation 仍可省略这些端口。

未来 owner/QoS mux 的推荐接法是：

```text
raw_client_valid[i] &&
    (read_admit || (read_busy && read_owner == i))  -> arbiter.s_arvalid[i]
raw_client_valid[i] &&
    (write_admit || (write_busy && write_owner == i)) -> arbiter.s_awvalid[i]
```

这条规则在维护边沿关闭空闲新 owner，同时保留已经锁定且可能停顿的当前
owner，直到其终止 R/B 完成。fence 在观察到
`read_quiescent && !read_busy && write_quiescent && !write_busy` 后，才发出
`abort_done`/`flush_done` 并递增一次 `current_epoch`；abort 清除 context，
flush 保留 context。`read_fire/write_fire` 是 AR/AW 接受的观测脉冲，违反
admission 且没有既有 busy owner 时只置 sticky `protocol_error`，不会撤回已
呈现的 VALID。

真实 arbiter+fence focused xsim 已通过：

```text
C1_AXI_SHARED_OWNER_EPOCH_FENCE_ARBITER_PASS ar=1 r=1 aw=1 b=1 epoch=2 cycles=23
```

该回归故意在维护边沿保持 stalled 读/写 owner，验证当前 owner 能排空、第二个
idle owner 被阻止，以及 epoch/fence 完成 token 的时序。它只是共享边界协议
证据；默认 `c1_r1_portable_soc`、client-6 和现有 read/write payload mux
尚未接入该 seam，不能据此宣称 native 长帧 QoS 或 15 fps。

在控制 seam 上还有一个可选的真实数据路径封装
`rtl/dma/c1_axi_shared_owner_epoch_arbiter_128.sv`。它实例化现有
`c1_axi_n_serial_arbiter_128`，只在进入 arbiter 前按以下规则屏蔽 client
VALID，并把 AR/AW 下游接受作为 fence 的 fire 观测：

```text
gated_valid[i] = raw_valid[i] &&
                 (admit || (busy && owner == i))
```

因此 abort/flush 边沿不会引入第二个 idle owner，同时已锁定且 stalled 的
owner 仍可完成 W/R/B。2-client shell xsim marker 为
`C1_AXI_SHARED_OWNER_EPOCH_ARBITER_PASS ar=1 r=1 aw=1 b=1 epoch=2 cycles=23`；
100 MHz Artix-7 proxy 为 2-client/no-skid `434 LUT/233 FF/+5.769 ns`，以及
默认 7-client/read-skid `1411 LUT/407 FF/+2.144 ns`。这些是独立 shell 的
结构证据，默认 portable SoC 仍未实例化，真实 Ti60/Efinity、DDR QoS、CNN
长帧与 15 fps 仍待后续接入验证。

### 4.2 Native DMA 读写闭环边界

native 640×480 的板前集成门 `c1_native_dma_loopback_final2_20260825` 使用
真实 table/XRGB read master、read arbiter、XRGB writer 和 write arbiter，把三
个输入 slot 写入三个不重叠的输出 slot，并由 DDR BFM 逐像素回读。writer 与
串行仲裁器之间的 `c1_axi_write_skid_bridge` 是一项可综合的单项 AW/W/B
缓冲；它只负责隔离 READY/VALID、保持 AW→W→B 顺序，不提供 burst packing 或
多 outstanding。仿真台在 BFM 边界另加反相时钟采样 shell，用于消除 xsim
delta-cycle 竞态，不能当作板上数据路径。该闭环证明 DMA/slot/回压组合，不
等于 portable SoC 七客户端、CNN/tensor、display QoS 或 15 fps。

随后 `native_boardless_job_hold_full_20260825` 将 `c1_r1_boardless_frame_system`
接回同一 native 地址图：table/22 descriptor barrier、真实 input/output DMA、
Resize/C8 两侧和外部 CNN echo 完成一帧 `cnn_in/cnn_out=307200/307200`，并由
associative DDR 对 output 逐像素回读。这里的 output writer 仍是 boardless top
的直连 AXI 写口，read side 只有 boardless top 内的单个 ID-less arbiter；它是
job/DMA 集成门，不是七客户端共享 fabric 或真实 CNN 性能门。

紧接着的 `native_fabric_full2_20260825` 将该 640×480 boardless top 作为真实
`c1_axi_n_serial_arbiter_128(CLIENTS=7)` 的 client-0，并在 client-1..6 接入
六个带随机 AW/W/AR 背压与 R/B 延迟的 procedural AXI peer。job 侧完成
`AW/W/B/AR/R=4800/76800/4800/4800/76890` 和 307,200 个 output 像素，六个
peer 均完成写入、B response、读回与 RLAST，最大观测等待为 118 cycles。该
结果闭合的是 native 长帧共享 fabric 的 forward-progress/响应保持风险切片；
peer 仍不是 capture、parameter/tensor、display 或真实 CNN 叶模块，不能替代
portable SoC 七客户端并发、underflow/QoS、Efinix DDR 或 15 fps 验收。

随后 `native_fabric_param_full_20260825` 将 client-1 换成真实
`c1_axi_parameter_loader` + `c1_r1_parameter_bank`，完成 16,896 B arena 的
`AR/R=66/1056`、shadow-bank commit 与三个词读回；client-2..6 保留五个
procedural peer。它证明一个真实只读参数叶能在同一七路 fabric 与 native
boardless job 共存，但仍不是七个 portable-SoC 真实叶模块的并发 QoS 证据。

### 4.3 Native 640×480 boardless job 与 portable 层次门（2026-08-29）

`run_r1_native_boardless_job_xsim_detached.ps1` 的 `-CompileOnly` run
`1fcd542bc74145c186807b22865a6ba1` 已通过 `xvlog+xelab`，marker 为
`C1_R1_NATIVE_BOARDLESS_JOB_ELAB_PASS frame=640x480`。同一 testbench 的完整
xsim run `76927b77e5b14cc998e43951d162bae8` 也通过，marker 为
`C1_R1_NATIVE_BOARDLESS_JOB_PASS`，完成 `stages=22`、
`cnn_in/cnn_out=307200/307200`、`table_ar=2`、`descriptor_ar=22`、
`input_ar/input_r=4800/76800`、`output_aw/output_w/output_b=4800/76800/4800`、
`output_pixels=307200`；随机背压统计为
`ar_stalls=517/r_gaps=115167/aw_stalls=697/w_stalls=5216/b_delays=6691`，
`stage_stalls=3/cnn_in_stalls=224913/cnn_out_stalls=80451`。该 bench 使用
`c1_r1_boardless_frame_system` 和单项外部 CNN echo，因此闭合的是 native
frame-table、descriptor barrier、输入/输出 DMA、ready/valid、AXI response 和
drain 的长帧集成，不是训练 CNN 算术或 DDR3 PHY 性能。

更高层 `run_r1_portable_soc_cache_ddr_bfm_xsim_detached.ps1 -Frame 640x480
-CompileOnly` run `09850789d6ba4d2180fa5831cf6f26dc` 已完成 portable SoC
`xvlog+xelab`，marker 为 `C1_R1_PORTABLE_SOC_SHAPE_ELAB_PASS frame=640x480`。
这证明当前完整层次的 native 几何/连接性可展开；full portable-SoC 长帧
数据面、真实训练 CNN、DDR3 服务效率、Efinity P&R 与 15 fps 仍需单独签核。
上述 runner 均采用 WMI 失败时的 `CREATE_BREAKAWAY_FROM_JOB` fallback，且
worker 结束后删除 disposable runRoot。

## 5. CSR 地址空间

主 CSR 为 32 bit、byte address；`0x200..0x2ff` 由 APB mux 路由到 ISP shadow/commit block。

| 地址 | 名称 | 说明 |
|---:|---|---|
| `0x000` | ID | `0x43315254` (`C1RT`) |
| `0x004` | VERSION | 当前 RTL 版本 |
| `0x008` | CAPABILITY | 3 input、2 output、APB3 |
| `0x010` | CONTROL | enable、START W1P、abort W1P、continuous、drop-oldest、clear |
| `0x014` | STATUS | idle/busy、done/error、ready buffer count |
| `0x018/01c` | IRQ_ENABLE/STATUS | done/error/drop/swap/underflow；status W1C |
| `0x020/024` | ERROR | 最近 error code/address |
| `0x040..04c` | FRAME TABLES | input/output table 64-bit base |
| `0x050..05c` | FRAME FORMAT | size、stride、XRGB formats |
| `0x080/084` | DESCRIPTOR_BASE | 当前 32-bit AXI 要求高 32 bit 为 0 |
| `0x088` | DESCRIPTOR_COUNT | MicroStyle 固定 22 |
| `0x08c` | STYLE_ID | 软件风格编号 |
| `0x090/094` | WEIGHT_BASE | 16,896 B 参数 arena DDR 地址 |
| `0x098` | TENSOR_BASE | 3×8 MiB 外部 DDR arena 起址，START 快照 |
| `0x0c0` | DISPLAY_MODE | bits[1:0] 四模式，bit7 OSD |
| `0x100/104` | COUNTERS | completed frame、busy cycles |

framebuffer 固定为 little-endian XRGB8888：逻辑字 `0x00RRGGBB`，640 像素最小 stride 2560 B 且 16 B 对齐。模块间 RGB888/C8 stream 不是 DDR 格式。

## 6. 时钟、复位与 vendor 边界

至少存在 `camera_clk`、`core_clk/DDR AXI clk` 与 `pixel_clk`。camera 用 async FIFO 入 core；display line store/prefetch 跨 core/pixel；事件用 toggle/ack CDC；reset 允许异步拉低，但每域同步释放。多 bit job/config 只能通过握手快照，不能逐 bit 两级同步。

便携 RTL不实例化 XPM、RAMB、DSP48、MIG 或 Efinix primitive。RAM 采用同步 read-first wrapper且大存储不整片 reset；乘法用显式 signed 运算交给综合器；ready/valid stall 时 payload/sideband 稳定。厂商替换仅位于 shell：

```text
RAW seam  ← Efinix MIPI CSI-2 + unpack
AXI seam  ← Efinix DDR controller/PHY + clock bridge
APB seam  ← Sapphire + PLIC/BSP
video seam← PLL + HDMI/TMDS/board interface
```

## 7. 验证层次与仍缺闭环

推荐从小到大保留四层：

1. Python/QAT/整数逐层 Golden；性能模型作为请求/周期预算基线；
2. ISP、DMA、CNN 原语、engine、tensor adapter/bridge、capture/display/control 专项；
3. boardless frame job 动态 AXI 回归；
4. portable SoC compile/elaboration/CSR smoke，随后是已完成的 8×8 单帧、16×8 两帧、64×48 单帧/两帧 gate 全链；独立 native 640×480 display prefetch staged preflight `native_prefetch_run2_20260825`、capture-writer staged preflight `c1_native_capture_writer_final_20260825`、真实 capture/table/ISP staged preflight `c1_native_capture_table_paced_full_20260825`、两主机 input-DMA/table/arbiter staged preflight `c1_native_input_dma_full_20260825`、read→write DMA loopback `c1_native_dma_loopback_final2_20260825` 以及 boardless job 全帧 run `76927b77e5b14cc998e43951d162bae8` 也已完成相应地址/读回/CDC/写回/RAW10 stream/read-arbiter/slot/drain 检查；portable SoC native 640×480 目前已通过 compile/elaboration（`09850789d6ba4d2180fa5831cf6f26dc`），但其 output DMA/七客户端/CNN/QoS 长帧数据面仍待补。独立七客户端 arbiter、loopback 或 boardless echo 回归不能替代该系统回归。

当前第 1 层包含两条独立证据：32×32 stored artifact 可 exact replay 22 个整数 stage；6 张 64×64 图片的 QAT checkpoint 与整数模型最终 RGB 最大误差为 0。RTL ABI run `35f1aa0e76ed41d084f40e6637ac331e` 已把训练描述符送入 decoder，并由真实 parameter scheduler 完成 1,030 个注册 arena reads/cache writes；这仍不是逐层算术证据。第 2 层的最终 engine 专项 run `c382d6f1705041d4a7d2e3650799ebce`、adapter 默认/sideband `5cc1f6d0fcd242bf9de7fe48c5418270`/`513714c5626b47e99bc730cf7d3fdf9f`、最终加固 cache seam `1e6f562adbc34ea383932840b97aa0e4`、64-bit/真实 AXI 动态链 `9212d5a042ae4d9895a3162869e3815f`/`be4977424d9d484e80340f970d9904d0`、显式 client-6 wrapper `54d6d7ec0b28445f8f80edeb67281c72` 与 bridge/capture/display/control 专项均 PASS；第 3 层在 external loopback 时代已有严格事务回归；第 4 层新增当前源码默认/缓存启用 smoke `7e76332ea7044371af9efcf39809258a`/`30658446f3d4442fb7f7a442bd5f9fe2`，以及当前源码 shape-scaled gate 矩阵 `c1_8x8_gate_20260825`（8×8）、`c1_16x8_two_gate_20260825`（16×8 两帧）、`c1_64x48_single_gate_20260825`（64×48 单帧）和 `c1_64x48_two_gate_20260825`（64×48 两帧）（22/44 descriptors、display done、真实七客户端 DDR、`swaps=2 drops=0`）；native 640×480 `c1_640x480_final_elab_20260825` 也已通过 compile/elaboration，独立 display preflight `native_prefetch_run2_20260825` 完成双路 307,200 像素/路、4,800 AR、76,800 R beat 和 `underflow=0/0`，独立 capture-writer preflight `c1_native_capture_writer_final_20260825` 完成三 slot、921,600 像素读回和 `AW/W/B=14400/230400/14400`，真实 capture/table/ISP preflight `c1_native_capture_table_paced_full_20260825` 又完成三帧 RAW10→RGB stream `pixels/sof/eol/eof=921600/3/1440/3` 与 Gamma/table/writer 检查，两主机 input-DMA/table/arbiter preflight `c1_native_input_dma_full_20260825` 完成三 slot `frame_pixels=921600` 和 shared `AR/R=14403/230403`；这些仍未覆盖 portable SoC output DMA/boardless job/七客户端/CNN/QoS。独立七客户端 arbiter run `bbaccd1453aa43368eebc4e1f5bdae5a` 与 cache fabric BFM `75ac975f5ec049a6b579e00c14dd41d0` 仍只覆盖共享边界；下一缺口是 trained artifact 驱动的 engine+adapter 逐层/端到端 RTL 对比、native input/output DMA/CNN 长帧并发、性能优化后的周期证明，以及 Efinity/Ti60/实体板签核。

所有 Vivado/xsim 任务使用 WMI 隐藏 worker 脱离当前 Windows Job；PASS 必须同时满足退出码、空 stderr、无 Fatal/Error/FAIL 和唯一 marker。不得用文件摘要代替像素/张量内容比较。

最新 native loopback 已补上“input read→output write”这一块此前缺失的集成证据；剩余缺口收窄为把它接入 boardless job/portable SoC 七客户端 fabric，并在真实 CNN/tensor/display 同时争用时测量长帧 QoS、abort/drain、underflow 和周期预算。

该缺口的第一半已经由 `native_boardless_job_hold_full_20260825` 完成，并由最新
detached run `76927b77e5b14cc998e43951d162bae8` 复核：真实 boardless frontend、
descriptor/table、input/output DMA 和外部 CNN echo 已在 640×480 运行；因此当前
主线缺口明确是 portable SoC 七客户端 fabric、真实 engine/tensor traffic 与
display/QoS 的并发，而不是单独 DMA 地址图。portable SoC 640×480 当前先闭合
compile/elaboration（`09850789d6ba4d2180fa5831cf6f26dc`），尚未宣称其长帧
数据面动态完成。

因此第 7 节中早先把 “native output DMA/boardless job” 列为待补的句子只保留为
历史分层说明；当前源码的 native boardless job 已有动态 PASS，尚未完成的是把
它与 portable SoC 的七客户端、capture、tensor/CNN 和 display traffic 合并。

同理，`native_fabric_full2_20260825` 已经把 boardless job 放入真实七路
仲裁器，但 client-1..6 仍为 procedural traffic。当前剩余闭环是以真实
portable-SoC client 叶模块替换这些 peer，并在同一 native BFM 中加入每客户端
等待、display underflow、abort/drain、帧 deadline 和 tensor/engine 周期门。

portable SoC 64×48 的 bind-only client monitor 已先把该风险量化：所有必需
方向均有握手，但 styled-display client-5 的连续 AR 等待达到 1,243,738
cycles，超过一百万 cycle 诊断门。该结果说明 ID-less `RD_DATA` owner 在
某个 leaf 长时间不接收 R 时会拖住其他 display 请求。随后 protocol-safe
response FIFO 的单帧 run 将 c4/c5 wait 降到 76/83、response hold 降到 2/2，
credit-only 版本在 8×8 两帧保持 `swaps=2 drops=0`；仍需在 native
portable-SoC 长帧中加入 underflow/deadline/occupancy 门，并完成 Efinity
资源与时序签核，而不是只放宽 watchdog。

本阶段的最大行 profile 已把只读 cache-refill seam 推到 `1280` logical words
和 `BURST_BEATS=32`，同时保留 ID-less 顺序与维护边界；它仍不改变上述
single-outstanding tensor adapter。任何性能接入都必须先满足统一 epoch/owner、
generation、flush/abort drain 和 read/write response credit 合同，具体审计见
[`TENSOR_CLIENT_INTEGRATION_AUDIT.md`](TENSOR_CLIENT_INTEGRATION_AUDIT.md)。

### 当前只读 cache-refill scheduler 边界（2026-08-27）

新增的 `c1_cache_refill_scheduler_read_client` 是一条独立的 boardless
composition：scheduler 负责 row command、logical-word metadata/epoch、
MAX_OUTSTANDING credit 和维护 fence；AXI128 reader 负责 request FIFO、pack2、
4-KiB-safe burst、AXI R 顺序和 response FIFO。两者之间只通过 ready/valid
以及 `leaf_req_occupancy`/`leaf_quiescent`/`leaf_req_flush` 连接，不引入
Efinix primitive，也不改 default SoC。

维护时 current word 先完成 handshake，随后才进入新 epoch；已接受的旧响应
可经 `drain_word_*` 排水。这里“尚需 cancellation-token/completion adapter”
属于 2026-08-27 historical snapshot；2026-08-28 已由 exact-count adapter
和 optional exact shell 补齐 line-cache 声明但尚未发出的 word。该边界仍不
改变默认 SoC：在 owner mux/真实 DDR QoS 完成前，scheduler proxy 的资源和
小 TB 周期都不作为整网或 15 fps 结论。

### exact-count refill ABI bridge（2026-08-27）

为接入现有 `c1_window_line_cache_c8` 的严格计数协议，当前推荐边界为：

```text
line-cache refill_req (row/count/base/epoch)
             │
             ▼
c1_cache_refill_completion_adapter
  normal word + accepted stale drain → one exact-count refill stream
  unissued suffix after fence         → zero/error poison
             │
             ▼
c1_cache_refill_scheduler_read_client_exact
  scheduler(epoch/credit/fence) → AXI128 read client(pack2/burst/R FIFO)
```

适配器只有在 declared word count 和 scheduler terminal token（`cmd_done`、
`abort_done` 或 `flush_done`）均到达后才报告 `refill_done`/释放下一命令。
这避免 late `cmd_done` 误作用于下一行，但会保留一个 correctness-first 的
行间 bubble；上层不能把 `refill_done` 当作 AXI 带宽提升。三个 token 必须
真实连线，不能绑 0。`word_count=0` 是错误诊断路径，line-cache 接线必须
保证 count 非零。

zero/error suffix 只用于让 line-cache 在取消后完成计数并触发 discard；它
不包含有效 tensor 数据。因而正常提交路径仍需确保所有 declared words 都
由当前 epoch 的 AXI response 提供，且必须在 shared read/write owner+epoch
mux 处阻止旧响应越过边界。当前 exact composition 仍是 boardless optional
seam，default SoC 和 legacy client-6 不变。

板上若发现 `refill_word_ready→scheduler→reader RREADY` 组合反压路径过长，
可在该边界加入一深度 skid，但必须连同 normal/drain 标志、row/index/epoch、
error/last 一并缓存；只延迟 data 而不延迟 sideband 会破坏 exact-count 合同。

### 真实 line-cache exact shell（2026-08-28）

当前 boardless 接线实现为

```text
stage_base + group_start
        │  (atomic capture)
        ▼
c1_window_line_cache_c8
  refill_req(row,count)
        │
        ▼
command hold: base = stage_base + row*(width*groups*8), stride = 8,
              row/count/epoch latched
        │
        ▼
c1_cache_refill_scheduler_read_client_exact
        │  exact normal/drain/poison stream
        ▼
REFILL_SKID_DEPTH=2 registered FIFO
        │
        ▼
line-cache refill_word(data,error,last)
```

`abort_req`/`flush_req` 同时送入 cache 与 exact seam；shell 的双路 done join
只在两边都完成 drain 后对外产生完成脉冲。command hold 防止 fence 改变已呈现
命令的 epoch，skid FIFO 的输入 ready 只依赖 occupancy，从而切断 cache 输出
ready 直达 AXI `RREADY` 的组合路径。FIFO 内部仍保留 row/index/epoch sideband，
即使 line-cache 只消费 data/error/last，也不会丢失 adapter 的协议校验信息。

小型 xsim 已覆盖正常行、取消行和新 epoch 重试；Artix-7 proxy 的真实 shell
在 `REFILL_SKID_DEPTH=2` 时为 `35639 LUT / 11930 FF / 7.5 BRAM / 0 DSP /
WNS +0.302 ns / TNS 0`，无 skid 对照为 `35543 LUT / 11923 FF / WNS -1.622 ns`。
这证明该 FIFO 是时序收敛措施，不是吞吐或资源优化；默认 SoC、读写 owner mux
和 Ti60/Efinity 实现仍保持隔离。已接受的 AXI 请求必须最终得到 AR/R 服务，
否则 exact drain 会有意保持反压。

### 共享 AXI QoS 观测边界（2026-08-28）

`c1_axi_shared_qos_monitor` 位于真实 serial arbiter 的 client-side 向量旁路，
只读采样，不插入 payload mux：

```text
client VALID/READY ───────┐
arbiter busy/quiescent ───┼──► c1_axi_shared_qos_monitor
arbiter owner ────────────┤       │
display underflow ────────┤       ├─ AW/AR wait + W/R/B stall
boardless start ──────────┤       ├─ per-client accepted counts
tagged new-pair prefetch ──┘       ├─ owner hold total/max+ID
                                  ├─ frame cycles/deadline miss
                                  └─ underflow/protocol/overflow
```

顶层用 `ENABLE_SHARED_QOS_MONITOR` 选择 generate 分支，默认 0；启用时
`csr_clear_stats_pulse` 是同步清零控制。帧计时从 accepted boardless start 开始，
以 `display_prefetch_new_done_event` 结束，刻意覆盖对应新 pair 的显示 R/FIFO/
line-store 排空；raw `display_prefetch_done` 还可能来自 current-pair 后台刷新，
不能直接作为跨帧 terminal。这比使用较早的 `control_done_event` 更能反映端到端
frame deadline。选定 aggregate 已成为 APB `0x108..0x12c` 只读 ABI，per-client
向量仍为层次化 diagnostic signals；`display_swap_event` 是独立的 VSYNC
ownership commit，当前可早于 tagged done，不能与 QoS terminal 混用。

实现采用 24-bit 饱和统计；仅 global owner-max 采用标量 max+owner-id，以切断
其变量索引 max-array 写回，per-client owner totals 仍保留索引更新；
Artix-7 100 MHz 独立 proxy 为 `2268 LUT / 4000 FF / WNS +1.465 ns`。在真实
8×8 native BFM 的 tagged two-frame 回归观察到
`start=2/raw_done=3/new_done=2/swap=2`；aggregate 窗口为
`last_frame_cycles=3446518`、`deadline_miss=2`、`underflow=2`，且 client-4 R
hold 约 `5.34 M` cycles，明确指出原始 ID-less display HOL。该观测边界仍不执行
owner/epoch admission，不能被解读为 QoS 修复或 15 fps 签核；下一层才是在同一
monitor 上比较 response-FIFO 和 owner-fence shell。

### Native 640×480 boardless gate（2026-08-29）

`c1_r1_boardless_frame_system` 已用 detached Vivado/xsim 完成一次完整
640×480 任务：22 个 descriptor、307200 个 C8 输入/输出 beat、4800 个输入
与输出 burst、76,800 个读/写数据 beat 均完成，AXI 背压、R gap、B delay、
CNN ready/valid stall 和 terminal drain 均通过。该 gate 证明 frame-job、DMA、
resize/C8 seam 在 native 几何下可闭合；CNN 端仍是外部 echo 模型，所以不把它
当作真实训练网络的周期或 15 fps 证据。完整 `c1_r1_portable_soc` 的 640×480
`xvlog+xelab` 也已通过，下一阶段可以在已有层次上替换真实训练 CNN/DDR BFM，
而不必再修改 frame-table 或 native DMA 地址合同。
