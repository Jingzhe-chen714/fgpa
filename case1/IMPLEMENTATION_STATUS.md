# 赛题一实现状态与选题门槛

更新日期：2026-08-29。

### Efinity 2026.1 隔离资源门（2026-08-29）

已在 Ti60F225/C4 上通过 Efinity map/PNR 的板卡无关探针：同步 EBR proxy 为
8/256 memory blocks、64 DSP；真实 `c1_dot8x8_requant_core` 为
`EFX_DSP24=64 + EFX_DSP48=16`，PNR 物理 DSP=80/160（50%），final
Fmax=189.717 MHz；小 IO DW wrapper 的 PNR 物理 DSP=28/160（17.5%），final
Fmax=271.592 MHz；参数 scheduler 仅占 1/160 DSP、final Fmax=236.855 MHz。
结果、日志目录和解读见
[`efinity/RESOURCE_MAP_RESULTS_20260829.md`](efinity/RESOURCE_MAP_RESULTS_20260829.md)。

同日的默认（`PACKED_AFFINE_CACHE=0`、unpacked affine）参数化尺寸探针显示：
`MAX_CHANNELS=8` 的小 wrapper 与 full-weight（`PARAM_ARENA_BYTES=16896`、
`MAX_PACKED_WEIGHT_TILES=72`）均可 map；`MAX_CHANNELS=16/24/48`、full-cache
和 22-stage full-shape wrapper 均在 `efx_map.exe → libefx.dll/libvfc_database.dll`
触发同一访问违例。随后增加的**可选** `PACKED_AFFINE_CACHE=1` 分支在
channel16（map+PNR final 396.040 MHz）、fullchannel/48-channel（map+PNR
final 321.027 MHz）以及保留 22-stage dispatcher/descriptor-cache 的
`c1_ti60_cnn_top_packed_wrapper`（map+PNR final 435.540 MHz）均通过；后者仍是
窄 stimulus 壳，资源计数不能作为板级值。上述均为板卡无关兼容性候选，不是
full board sign-off。该结果是 Efinity 前端兼容性诊断，不是 LE/DSP/EBR 超限；
完整表和 run ID 见资源报告。

新增的 `c1_ti60_portable_soc_packed_wrapper.sv/.xml/.sdc` 将完整
`c1_r1_portable_soc` 纳入 packed-affine map 探针。60 s 与 180 s 上限内均未见
已知 `libefx.dll/libvfc_database.dll` 访问违例或 HDL unknown-module 错误，但
180 s 时完整 hierarchy 尚未结束，runner 超时，未执行 PNR，也没有可信
LE/FF/EBR/DSP 数字；这只是前端复杂度/兼容性诊断，不是资源或时序签核。
本轮固定深度/扁平化等其他实验性存储变体未作为生产修复保留；生产 RTL 默认
仍为 `PACKED_AFFINE_CACHE=0`，以已通过 stage-21 handoff 及 cache/overlap
回归的功能基线为准。packed 分支的 stage21/trained-artifact A/B 门已补齐：
Icarus `run_iverilog_stage1_handoff.ps1 -FullStage21 -PackedAffine` 与 detached
xsim `run_r1_stage1_handoff_xsim_detached.ps1 -FullStage21 -PackedAffine`
均 PASS，marker 与默认分支一致（`operands=896/results=836/final=64/`
`stage_done=22/abort=0`；xsim run `5e234f2e1b87483b8cd4c47bb9e3d667`）。
这只闭合 8×8 scaled trained-artifact handoff；packed 仍是可选候选，默认参数
不变，full-board/DDR3/15-fps sign-off 仍 OPEN。

拿板前的 RTL、Icarus/xsim、Efinity map/PNR proxy、STA 和报告解析可由脚本独立
完成；首次 Sapphire/DDR3/PLL/MIPI/HDMI/pin/peri 参数选择与 IP Manager 生成
仍需用户在 GUI 确认一次。CLI/IPM 审计见
[`efinity/CLI_IPM_AUDIT_20260829.md`](efinity/CLI_IPM_AUDIT_20260829.md)。

完整 `c1_r1_microstyle_engine` 与 `c1_r1_microstyle_cnn_top` 在当前 Efinity
2026.1.132.3.9 map 前端触发 `libefx.dll`/`libvfc_database.dll`
`EXCEPTION_ACCESS_VIOLATION`，因此 full-top 资源和板级可实现性仍为 OPEN；这
不是 RTL 仿真失败，也不是资源超限证明。下一门是按官方 Sapphire/DDR 工程
逐层二分映射并替换 Efinity 不兼容的存储/断言表达。

### 2026-08-29 系统级独立回归收口

在当前受管桌面上重新执行了完整板前门禁：Icarus 全 RTL（127 个源文件）
退出码 0，stage-21 production-bank handoff 通过，Python 21 命令回归通过；
Vivado/xsim 的 portable-SoC 空闲 smoke 和 cache-enabled wiring smoke 也均通过。
后两项 runner 已改为“WMI 失败时自动调用 native
`CREATE_BREAKAWAY_FROM_JOB` helper”，并用 response file 传递长源文件列表；
因此不需要把 Vivado/xsim 绑定到当前 Codex Windows Job，且 compile/elaboration
失败时也会删除 disposable runRoot。cache wiring smoke 的层级探针同步修正为
当前 `g_tensor_legacy_client.u_tensor_cache_axi_client` 生成路径。该收口只证明
系统组合、APB/QoS 空闲状态、cache quiescent/fence 和工具运行隔离，不改变
`native 640×480 + DDR3 + 15 fps` 仍 OPEN 的结论。

同一门禁的 packed 参数 smoke 也已通过：`run_portable_soc_smoke_xsim_detached.ps1
-PackedAffine`（run `40ef92de11024301abe4dcc069ee855e`，marker
`C1_R1_PORTABLE_SOC_SMOKE_PASS tensor=02000000`）以及
`run_portable_soc_cache_wiring_smoke_xsim_detached.ps1 -PackedAffine`（run
`dc4e49c39efc40ac8ccca802b6c9f7a6`，marker
`C1_R1_PORTABLE_SOC_CACHE_WIRING_SMOKE_PASS tensor=00000000 quiescent=1
fence=1 qos=1`）均 PASS。它们只验证 `PACKED_AFFINE_CACHE` 定义贯通
portable-SoC/cache seam，不构成 native CNN、板级资源或 15-fps 证据；默认值仍为 0。

随后完成 native 尺寸的独立门禁：`run_r1_native_boardless_job_xsim_detached.ps1`
已加入 WMI 失败时的 `CREATE_BREAKAWAY_FROM_JOB` fallback，并通过
640×480 全流程 xsim（run `76927b77e5b14cc998e43951d162bae8`）：
`stages=22`、CNN 输入/输出各 `307200`、输入/输出 AXI 各 `4800` burst、
`output_pixels=307200`，所有 backpressure/response/drain 检查通过，stderr 为空，
runRoot 已清理。同一 runner 的 `-CompileOnly` 门也通过（run
`1fcd542bc74145c186807b22865a6ba1`，marker
`C1_R1_NATIVE_BOARDLESS_JOB_ELAB_PASS frame=640x480`）。更高层的
`c1_r1_portable_soc` 640×480 `xvlog+xelab` 也已通过
（run `09850789d6ba4d2180fa5831cf6f26dc`）；因此当前板卡前可独立完成 native
接口与层次展开验证，剩余的是真实训练 CNN 长帧周期、DDR3 服务效率、Efinity
板级 P&R 和 15-fps sign-off，而不是语法/连接性问题。

同时用已安装的 Efinity RISC-V IDE 工具链执行了
`verify_efinity_toolchain.ps1 -BuildSmoke`：`rv32imc/ilp32` 最小软件工程以
`riscv-none-elf-gcc 13.4.0` 完成 ELF/HEX/BIN/反汇编生成（`SMOKE_BUILD_PASS
files=8 bytes=35952`）。由于最终 `soc.h`、linker、startup 和 APB base 必须
来自 IP Manager 生成的 Sapphire BSP，这仍是软件编译链门，不是板上 CPU 启动
或中断/DDR 调试证据。

## 结论先行

赛题一已经从“接口骨架”推进到**真实算法/控制模块齐备、顶层小帧全链动态回归通过的板卡无关功能基线**：功能性训练/QAT 工件、22-stage 整数 Golden、真实 MicroStyle 算术 engine、参数调度、顺序 tensor 地址/window/group scheduler、可选三行 C8 cache、64→AXI128 bridge、capture/ISP、三输入双输出 ownership、frame job、四模式显示与 OSD 都已有 RTL 或软件实现和分层验证证据。`c1_r1_portable_soc` 把这些模块组合到一个 APB、camera、video 和单 AXI4-128 的厂商无关边界；当前源码下 8×8 单帧、16×8 两帧、64×48 单帧和 64×48 两帧的 latest gate run 均通过，其中 64×48 两帧为 `c1_64x48_two_gate_20260825`，保持 `done=2 descriptors=44 swaps=2 drops=0`。这些仍是小帧功能/协议证据，不是 native 640×480 性能证明。

   这仍不是可参赛 bitstream，也不是 15 fps 证明。当前 QAT 只是一套 6 图/单风格的功能工件；portable SoC 的主动态矩阵仍是 8×8/16×8/64×48 的零参数生命周期回归，另有一个**独立的 8×8 真实 arena/descriptor 参数加载闭环**、一个**native 640×480 descriptor/parameter commit 预检**、一个**真实 stage-0 首行 1..16 像素有限算术 gate（已验证至 16 像素）**和一个**production parameter-bank 的 stage-0→stage-1→…→stage-21 有界 handoff gate（已验证至 stage 21 完整 2×2，并自然输出 64 个 RGB beat）**，但尚未扩展到 native 640×480 全网/长帧 CNN 数据平面；真实 22-stage engine 的完整重排版代理综合虽已完成，但 `WNS=-4.965 ns`，100 MHz 明确未闭合；顺序 tensor adapter 每次只允许一个 64-bit DDR 请求 outstanding，属于 correctness-first 实现，性能远低于 640×480@15 fps。赛题指南已明确目标为 Ti60F225I3/Ti60F225 开发板，用户截图也给出 `MT41J128M16JT-125` DDR3 x16/800 Mbps；Efinity IDE 2026.1.132（patch 2026.1.132.3.9）与 Efinity RISC-V IDE 已安装且命令行工具入口已核验，Icarus 14.0 (devel)/GTKWave 3.3.128 也已完成板前 smoke，但尚未取得/核验本次板卡 revision、DDR 控制器/IP 拓扑、时钟和引脚约束，也尚未完成 Efinity 综合、布局布线或板卡实测；工具链操作边界见 `EFINITY_RISCV_TOOLCHAIN_GUIDE.md` 与 `efinity/TI60F225_BOARD_PROFILE.md`。

### 2026-08-29 收口：stage 8–21 production-bank handoff 已闭合

上面的总体结论仍适用于 native 尺寸、物理实现和 15 fps；但“production-bank
只到 stage 6/7”的旧证据边界已被本轮更新。`tb_c1_r1_microstyle_artifact_tensor_engine_8x8.sv`
现在为 stage 8…21 提供独立的 producer-bank bitmap、精确地址函数、残差来源检查、
写回 offset/顺序检查和最终 RGB stream 检查。Icarus 已逐一通过
`-FullStage8`…`-FullStage21`；累计计数从 `156/176` 推进到 `896/836`，stage 21
另有 64 个 final RGB beat 自然完成。detached Vivado/xsim 已复核 stage 14 和
stage 21 代表性端点，stderr 为空、临时 runRoot 已删除。完整层表、地址语义、
marker 与复现命令见 [`STAGE8_21_HANDOFF_PREFLIGHT.md`](STAGE8_21_HANDOFF_PREFLIGHT.md)。

因此当前板前功能边界是：

`stage 0→21 / 8×8 scaled / production parameter bank / handoff semantics = PASS`；
`native 640×480 full CNN + real DDR3/Efinity + timing + 15 fps = OPEN`。

## 已闭合的板卡无关基线

| 领域 | 当前真实成果 | 证据边界 |
|---|---|---|
| Python/ISP Golden | RAW10、四 Bayer/ROI、BLC、Debayer、AWB、CCM、Gamma、Resize；6 张公开图×4 Bayer | 算法/定点回归，不代表传感器标定 |
| QAT 工件 | float 240 step + QAT 80 step；22 descriptor、16,896 B arena、12,212 个 INT8 卷积权重；6 图 QAT 与整数输出最大误差 0；RTL decoder + parameter scheduler 已接收 22 stage、1,030 个 128-bit reads/cache writes；同一真实 arena 的 8×8 缩放 descriptor 已完成 engine 逐阶段 bit-exact | 功能训练而非最终视觉收敛；tensor adapter、portable SoC 全链和 native 640×480 算术帧仍未闭合 |
| 软件/ABI | RV32IMC 裸机 C API、64 B descriptor、16 B framebuffer、ISP CSR；configure 拒绝 busy/非640×480/非22层及五个元数据/参数/tensor 区域重叠；start 先清旧 terminal 且 busy 时返回 false；`c1_accel_wait_idle()` 门控 job 内存复用；主机测试通过 | framebuffer payload 的 allocator/表项另验；尚无**为当前 Case-1 器件生成并接入**的 Sapphire BSP/启动代码/PLIC/I2C/UART（本地 Soft Sapphire 示例与 BSP 已随 Efinity 安装） |
| APB/job snapshot | `0x098 TENSOR_BASE`；START 时由 lifecycle controller 原子锁存表地址、descriptor/weight/tensor base、尺寸和模式；busy START 被拒绝 | 当前 32-bit AXI，tensor base 需 8 MiB 对齐并容纳 24 MiB arena |
| Capture/ISP | camera async FIFO→R1 ISP→capture writer；无 admission 时对 FIFO 中完整或半帧执行 silent discard，abort/error 后 drain/cleanup 到安全边界 | FIFO 不是整帧缓存；真实 CSI 坏包/短行仍需 vendor 侧和板上验证 |
| Frame ownership/control | 3 输入+2 输出、single-shot/continuous admission、参数装载、NN job、display pair prefetch/swap、abort/flush cleanup | lifecycle 专项覆盖 continuous capture/NN/prefetch；最终 `C1_TWO_FRAME` 回归又覆盖串行 single-shot 两帧、`swaps=2 drops=0`。这仍不是长时间随机系统回归 |
  | 真实 22-stage compute | `c1_r1_microstyle_engine` 缓存 22 descriptor，128-bit ABI BRAM 每层多拍重排到固定 Conv/DW lane bank，并执行 signed-INT8 Conv3×3/Conv1×1/DW/upsample/residual/final；同一 16,896-byte trained arena 配合 8×8 缩放 descriptor 已完成 22 stage、896 输入记录、836 输出记录的 RTL/Python 逐阶段 bit-exact；production parameter bank 的 stage-0→21 完整 2×2 handoff 也已逐层通过，stage-21 另有 64 个 final RGB beat | 已闭合小尺寸 engine+arena 的全 22-stage handoff 语义；仍未闭合 native 640×480 trained-model、共享 DDR 长帧 QoS、物理实现和代理 WNS |
  | Tensor adapter/cache | 三个固定 8 MiB 外部 DDR bank；支持 SAME/stride2、1×1、DW、upsample2、residual/final；三行 all-group C8 payload cache、adapter sideband、`c1_tensor_window_cache_axi_client` client-6 wrapper 已验证，并由默认关闭参数保持 wire bypass；真实 22-stage adapter→cache→64-bit BFM、adapter→cache→AXI128 BFM、wrapper→client-6→arbiter→DDR BFM，以及 trained artifact 8×8 adapter→engine→写回闭环均完成；production-bank stage-1 首像素/完整 2×2、stage-2…21 完整 2×2 handoff 已单独通过，stage-5/stage-9/stage-13 residual 双读和多 bank provenance 均有记录 | 顶层证明仍是零参数小帧、单拍、单 outstanding；尚无 burst/multi-outstanding/native 640×480 性能闭环；24 MiB 是外部 DDR，不是 M10K |
| Tensor AXI bridge | 64-bit req/rsp 映射为单拍 AXI4-128；按 `addr[3]` 选上下半字，覆盖 AW/W 独立握手、WSTRB、RRESP/BRESP/RLAST | 单 outstanding，不能形成实时带宽 |
| 显示 | 720p60 timing、原图居中、风格图居中、左右分屏、保留模式 fail-black；bit7 OSD；双源 line prefetch、frame-boundary enable、underflow 事件 | HDMI/TMDS/PLL 属于 vendor shell，DDR 最坏延迟未上板验证 |
| portable SoC | APB、capture、parameter、frame-job、真实 engine+tensor adapter、display 合成；第 7 个客户端由 `c1_tensor_window_cache_axi_client` 统一封装，默认 adapter→bridge，参数启用时 adapter→window-cache seam→bridge；当前源码 8×8/16×8/64×48 shape-scaled latest gate（含 64×48 两帧）均完成动态回归；另有 `-TrainedArtifact` 的 8×8 真实 descriptor/arena 参数加载闭环 | 证明的是板卡无关小帧生命周期、共享 DDR 握手和 frame ownership；真实工件尚未逐像素对 golden，native 640×480 trained-model、长帧 QoS、burst/multi-outstanding 和 15 fps 仍未闭合 |

## 当前验证快照

| 项目 | run | 结果 |
|---|---|---|
| lifecycle control | `595748663d3541248c8ef4c1c46b1fd3` | `capture=1 nn=1 prefetch=5 swaps=1 repeats=4`；指定收口快照 `14817510235e4da8882511ec46606626` 同样 PASS |
| capture frontend | `11e14099eb784ccba3b6397650a80278` | `frames=5 ... cleanup_entries=4 cleanup_cycles=114` |
| display modes/raster | `aaf5846df1a84216aa88515a82b2eda8` | bootstrap/drain 修复后四模式 11 点 + 完整 720p raster PASS |
| display prefetch/CDC（bootstrap/drain 后） | `3bf346fd0896450681875829c29ff0e9` | `C1_DISPLAY_PREFETCH_CDC_PASS`；pair/CDC 回归通过 |
| real MicroStyle engine | `c382d6f1705041d4a7d2e3650799ebce` | `stages=22 outputs=836 param_reads=1116 stalls=252 aborts=8 faults=6`；stderr 为空 |
| trained artifact → RTL engine bit-exact（8×8） | `artifact_probe_8x8_20260828c`；Icarus 同 TB 亦通过 | `C1_R1_MICROSTYLE_ENGINE_ARTIFACT_8X8_PASS stages=22 records=896 outputs=836 cycles=28276`；真实 16,896-byte arena，detached xsim，runRoot 自动清理；尚未覆盖 tensor adapter/SoC/native |
| trained artifact → portable SoC（8×8） | `trained_artifact_soc_8x8_20260828`；detached xsim | `C1_R1_PORTABLE_SOC_TRAINED_ARTIFACT_8X8_PASS descriptors=22 weight_ar=66 axi_r=2199 done=1 stage_mask=1fffff`；真实 arena 穿过 parameter loader/共享七客户端 AXI/adapter/engine/display 生命周期；尚未逐像素对 golden、尚未 native 640×480 |
| native 640×480 artifact descriptor/parameter commit preflight | `native_preflight_full2_20260828`；Icarus 同 TB 亦通过 | `C1_R1_NATIVE_ARTIFACT_PREFLIGHT_PASS frame=640x480 stages=22 descriptor_count=22 parameter_bytes=16896 parameter_words=1056 parameter_nonzero_words=1030 bursts=66 beats=1056 ar_stalls=23 r_stalls=242 generation=1`；覆盖真实 descriptor continuity/geometry、production AXI loader、双 bank 原子提交与首/中/尾读回；明确不含 native CNN 数据平面 |
| native 640×480 首层有限窗口 preflight | `native_first_window_full_20260828`；Icarus 同 TB 亦通过 | `C1_R1_NATIVE_FIRST_WINDOW_PREFLIGHT_PASS frame=640x480 stages=22 source_writes=307200 first_window_reads=9 engine_inputs=1 output_writes=2 abort=1 base=00100000`；覆盖真实 adapter 源帧写入、首层 stride-2/SAME_REPLICATE tap 地址/数据、两个 output group 与安全 abort；明确不含后续 21 层/全网长帧 |
| native 640×480 首层流水化有限窗口 A/B | `native_first_window_pipe_elab_20260828` / `native_first_window_pipe_full_20260828`；Icarus 同 TB 亦通过 | `pipeline=1 pixel_pipeline=1` 下仍为 `source_writes=307200 first_window_reads=9 engine_inputs=1 output_writes=2 abort=1`；证明可选 address/pixel-index pipeline 的功能与握手兼容性，不代表 WNS/Fmax/15 fps |
| native 640×480 首层真实 engine/parameter-bank 算术 preflight | `native_first_window_engine_default_postroi_20260828`；Icarus 同 TB 亦通过 | `C1_R1_NATIVE_FIRST_WINDOW_ENGINE_PREFLIGHT_PASS frame=640x480 stages=22 pipeline=0 pixel_pipeline=0 window_pixels=1 source_writes=307200 first_window_reads=9 engine_inputs=1 engine_outputs=2 output_writes=2 abort=1 group0=0e09000000320005 group1=0000000000190006`；覆盖 1056×128-bit dual-bank arena load（generation=1）、真实 stage-0 weight scheduler/repack/dot/requant、adapter window/地址和安全 abort；明确不含 stage 1–21/native 全网 |
| native 640×480 首层真实 engine 流水化 A/B | `native_first_window_engine_pipe_full_20260828`；detached xsim | `C1_USE_PARAMETER_BANK` 与 `pipeline=1 pixel_pipeline=1 window_pixels=1` 下真实 stage-0 算术 golden、计数和 abort 合同保持一致；仅证明可选地址流水寄存器的功能兼容性，不代表时序/15 fps |
| native 640×480 首层真实 engine 有限四像素 gate | `native_first_window_engine_roi4_elab2_20260828` / `native_first_window_engine_roi4_full_20260828`；Icarus 同 TB 亦通过 | `pipeline=1 pixel_pipeline=1 window_pixels=4`；真实 parameter-bank + stage-0 连续首行 4 像素逐项比较，`source_writes=307200 first_window_reads=36 engine_inputs=4 engine_outputs=8 output_writes=8 abort=1`，x=0..3 的两个 C8 group golden 全部通过；仅覆盖 stage 0 有限窗口，不代表 stage 1–21/native 全网/15 fps |
 | native 640×480 首层连续窗口扩展（8/16 像素） | `native_first_window_engine_roi8_full_20260829` / `native_first_window_engine_roi16_full_20260829`；Icarus `native16_iverilog_20260829`；Python `--pixels 1/2/4/8/16` | `pipeline=1 pixel_pipeline=1` 下真实 parameter-bank + stage-0 连续首行 golden 通过；N=8 为 `first_window_reads/engine_inputs/engine_outputs/output_writes=72/8/16/16`，N=16 为 `144/16/32/32`，两者 `source_writes=307200 abort=1`，首像素两组 golden 均为 `0e09000000320005/0000000000190006`；Icarus 16 像素 marker 与 xsim 一致，Python 五档护栏逐项通过。仍仅覆盖 stage 0，不代表 stage 1–21/native 全网/15 fps |
  | 8×8 production-bank stage-1 handoff（首像素/完整 2×2） | `stage1_handoff_metadata_final_20260829` / `stage1_full_metadata_final_20260829`（源码更新后回归：`stage1_handoff_post_stage2_20260829` / `stage1_full_post_stage2_20260829`）；Icarus `run_iverilog_stage1_handoff.ps1` | 首像素门：`operands/results=18/35`、`stage1_reads/writes=18/3`、`stage_done=1`；完整门：`C1_R1_STAGE1_FULL_8X8_PASS operands=24 results=44 source_writes=64 stage0_reads=144 stage0_writes=32 stage1_reads=72 stage1_inputs=8 stage1_pixels=4 stage1_writes=12 stage1_outputs=12 stage_done=2 abort=1 abort_response_delay=3`。真实 1,056×128-bit parameter bank generation=1；stage-0 全部 32 group 写回后才允许 stage-1 读取，末个写响应刻意延迟 3 周期并完成 drain，且输出 x/y/group-last/SOF/EOL/EOF 元数据逐项检查。仅覆盖 stage 1，不代表 stage 2–21/native/15 fps |
  | 8×8 production-bank stage-2 full handoff | `stage2_full_metadata_final_20260829`；Icarus `run_iverilog_stage1_handoff.ps1 -FullStage2` | `C1_R1_STAGE2_FULL_8X8_PASS operands=36 results=68 source_writes=64 stage0_reads=144 stage0_writes=32 stage1_reads=72 stage1_writes=12 stage2_reads=12 stage2_inputs=12 stage2_pixels=4 stage2_writes=24 stage2_outputs=24 stage_done=3 abort=1 abort_response_delay=3`。stage-2 `res0.expand1x1` 的 C24→C48/2×2 只读取 center tap；独立 bank0 provenance、bank1 写回、算术数据和 output metadata 均逐项通过；xsim/Icarus 均通过且私有目录自动清理。仅覆盖 stage 0–2，不代表 stage 3–21/native/15 fps |
  | 8×8 production-bank stage-3 full handoff | `stage3_full_metadata_final_20260829`；Icarus `run_iverilog_stage1_handoff.ps1 -FullStage3` | `C1_R1_STAGE3_FULL_8X8_PASS operands=60 results=92 source_writes=64 stage0_reads=144 stage0_writes=32 stage1_reads=72 stage1_writes=12 stage2_reads=12 stage2_writes=24 stage3_reads=216 stage3_inputs=24 stage3_pixels=4 stage3_writes=24 stage3_outputs=24 stage_done=4 abort=1 abort_response_delay=3`。stage-3 `res0.depthwise3x3` 的 C48→C48/2×2 逐项保留 SAME_REPLICATE 边界重复地址，独立 stage2→stage3 bank1 provenance、bank2 写回、算术数据和 output metadata 均通过；xsim/Icarus 均通过且私有目录自动清理。仅覆盖 stage 0–3，不代表 stage 4–21/native/15 fps |
  | 8×8 production-bank stage-4/5/6/7 full handoff | `stage4_full_metadata_final_20260829` / `stage5_full_metadata_final_20260829` / `stage6_full_metadata_final_20260829` / `stage7_full_metadata_final_20260829`；Icarus `run_iverilog_stage1_handoff.ps1 -FullStage4/-FullStage5/-FullStage6/-FullStage7` | 四个有限 2×2 gate 均由 Icarus 与 detached Vivado/xsim 通过。累计 marker 为 stage4 `operands/results=84/104`、stage5 `96/116`（primary/residual reads=`12/12`）、stage6 `108/140`、stage7 `132/164`（SAME_REPLICATE reads/writes=`216/24`），`stage_done=5/6/7/8`，末个写响应固定延迟 3 周期并完成 abort/drain；stage3→4、stage4→5、stage1→5 residual、stage5→6、stage6→7 provenance 与 output metadata 均逐项检查。xsim stderr 为空，私有 runRoot 已清理；这是 stage 8…21 扩展前的历史分段快照，不代表 native/15 fps。详见 `STAGE4_6_HANDOFF_PREFLIGHT.md` 与 `STAGE7_HANDOFF_PREFLIGHT.md` |
  | 8×8 production-bank stage-8…21 full handoff | `stage14_full_handoff_20260829` / `stage21_full_handoff_final_20260829`；Icarus `run_iverilog_stage1_handoff.ps1 -FullStage8`…`-FullStage21` | Icarus 14 个终点全部通过：stage8…21 累计 `operands/results=156/176, 168/188, 180/212, 204/236, 228/248, 240/260, 288/308, 336/356, 384/388, 512/516, 640/644, 768/708, 832/772, 896/836`；detached xsim 复核 stage14（`stage_done=15 abort=1`）和 stage21（`final=64 stage_done=22 abort=0`）。producer-bank bitmap、stage9/13 residual 来源、SAME_REPLICATE 重复地址、upsample floor 坐标、output metadata 和 final RGB stream 均逐项检查；stderr 为空、runRoot 自动清理。该证据仍是 8×8 scaled handoff，不代表 native/DDR3/15 fps |
| tensor adapter（默认/sideband） | `5cc1f6d0fcd242bf9de7fe48c5418270` / `513714c5626b47e99bc730cf7d3fdf9f` | 默认保持 2,230 requests；sideband 为 22 configs、44 config stalls、1,512 cacheable reads、266 bypass reads；历史 adjacency 为 407/2,229（18.2593%） |
| tensor AXI bridge | `b587aa890cc04165bd5a88ce76868087` | 1,209 transactions，含上下半字、AXI 错误和随机 stall |
| portable SoC smoke（当前源码） | bypass `7e76332ea7044371af9efcf39809258a`；最终 cache-enabled `30658446f3d4442fb7f7a442bd5f9fe2` | `tensor=02000000`；enabled `quiescent=1 fence=1`，最终 route-lock/断言源码下 `tensor_cache_busy` 已进入 `system_busy` fence；stderr 全空。不证明动态 stage/refill |
| tensor traffic 性能模型 | Python regression（13 commands） | baseline `21,388,800` requests / `342,220,800 B`；候选 `47,547,744 B`，但 64-MAC 算术下界仍 `6,691,200 cycle` |
| AXI128 packing 原型（未接 SoC） | xsim `4d4c4edfb483422c9196b7fdc12b8e6a`；proxy synth `d011df7b1a7a4bd19275769b89a01f94` | 100 requests→51 beats，48 packed pairs，49% reduction，响应/错误/stall PASS；412 LUT、649 FF、0 BRAM、0 DSP，100 MHz WNS +2.588 ns/TNS 0（裸模块 proxy） |
| trained artifact ABI（decoder/scheduler/arena 边界） | `35f1aa0e76ed41d084f40e6637ac331e` | 22 stages、1,030 reads/cache writes、16,379 B logical payload；明确 `NATIVE_640x480`，非算术 E2E |
| 七客户端 arbiter 压力 | `bbaccd1453aa43368eebc4e1f5bdae5a` | 56 写+56 读，AW/AR/B/R 随机停顿，最大等待 89/67 cycle，读写并行 |
| 共享 owner/epoch fence + 真实 arbiter status seam | focused xsim `C1_AXI_SHARED_OWNER_EPOCH_FENCE_ARBITER_PASS` | `ar=1 r=1 aw=1 b=1 epoch=2 cycles=23`；真实 `c1_axi_n_serial_arbiter_128` 新增只读 `read_busy/read_quiescent/write_busy/write_quiescent/read_owner/write_owner`，维护期间保留当前读/写 owner 排空；默认 SoC 尚未接入 |
| 可选 owner/epoch + serial-arbiter integration shell | focused xsim `C1_AXI_SHARED_OWNER_EPOCH_ARBITER_PASS`；cache-enabled top compatibility smoke | shell `ar=1 r=1 aw=1 b=1 epoch=2 cycles=23`；顶层默认接线仍通过 `C1_R1_PORTABLE_SOC_CACHE_WIRING_SMOKE_PASS tensor=02000000 quiescent=1 fence=1`，未替换 default SoC fabric |
| `c1_axi2_serial_arbiter_128` 写握手修复回归 | `4e035ad9cea447eb98bfd6595a52cfa2` | 24 写 burst/104 beat 与 24 读 burst/100 beat，覆盖早/缺 RLAST 及 AW/W/B/AR/R 停顿；为 native loopback 的 registered write-side handshakes 提供独立 PASS |
| boardless frame-system compatibility after arbiter change | `c1_boardless_after_arbiter_20260825` | 9 jobs、7 launches、2 done、5 errors、2 aborted、110 stage transfers、5 safe drains；既有外部-CNN/小帧 job/abort 合同保持 PASS |
| memory path seam | xsim `7a447dba98be413d9e36c9f20bee443d`；proxy synth `ca3e6b438d7e471bb39a083fc31746de` | legacy/performance 两分支；3 requests→2 beats、1 packed pair，`flush_done/quiescent` PASS；mode0 122 LUT/176 FF，mode1 413 LUT/651 FF |
| line/window cache traffic model | Python regression（13 commands） | 8×8/16×16/64×48 external 408/1,632/19,584；按真实 group 交织、整行全 group refill，三行逐 tap 命中率 98.7434%/99.3717%/99.8429% |
| line/window cache RTL control | xsim `8991ff1ef0954d669c3a4568208ae5a2`；proxy synth `7ee82460964f4926b9b5030655bd049d` | 720 taps、16 refills、128 external words；97 LUT/342 FF/0 BRAM/0 DSP，WNS +5.042 ns；row-tag-only 独立小帧，不是系统 cache |
| all-group C8 payload cache | normal `2a1766339f834f3b9eba6f0dd5deecd4`；fault `3373b871a3734d2ab2ca9607a206face`；max-row `a3ac690fadf34c8fb123c8043f365cc1`；synth `d07c3a3c7348474ea465ff73f765707a` | 1445 正常响应；3 类 fault/2 类 maintenance；1280-word 最大行；288 LUT/203 FF/7.5 BRAM tile/0 DSP，100 MHz WNS +1.086 ns |
| tensor window-cache seam hardening | xsim `1e6f562adbc34ea383932840b97aa0e4`；synth `6dc7d474aff34448ba590ff615927a53` | 17/17 logical req/rsp、5 row refills/40 refill reads、8 bypass reads/2 writes、50 downstream；`cfg_rejects=1 runtime_fallbacks=1`，配置拒绝和路由后错误以 route lock 安全收口；adapter/seam 协议、分类和 owner 断言启用。最终 proxy 为 1,236 LUT/792 FF/7.5 BRAM tile/0 DSP，100 MHz WNS +1.086 ns；较历史 209b 基线仅 +2 LUT/+5 FF |
| adapter/cache 动态 64-bit 链 | `9212d5a042ae4d9895a3162869e3815f` | 22 configs；2,230/2,230 logical req/rsp；1,512 cacheable reads 中 1,493 hit/19 miss，19 refills/204 words；1,810→502 downstream reads（-72.3%），其中 `502=298 bypass+204 refill`，另有 420 writes；memory error/abort drain 与原 22-stage bit-exact marker PASS，三阶段 stderr 全空 |
| adapter/cache/真实 AXI128 动态链 | `be4977424d9d484e80340f970d9904d0` | `AR/R=502/502`、`AW/W/B=420/420/420`；上下 lane 462/460，AW-first/W-first/same 318/81/21；AR/AW/W stall 1577/1583/1580，R/B gap 1194/915，B hold 2，error 1，abort 5。小尺寸、单拍、单 outstanding；未到 portable SoC 仲裁/DDR |
| 显式 tensor/cache AXI client-6 wrapper | `54d6d7ec0b28445f8f80edeb67281c72` | `c1_tensor_window_cache_axi_client(ENABLE_CACHE=1)` 将 seam 与 AXI128 bridge 统一封装并固定接入七客户端 slot 6；真实 wrapper→`c1_axi_n_serial_arbiter_128`→AXI BFM 完成 `refill_ar=4`、`direct_ar=1`、`writes=1`、`responses=6`，marker 唯一且 xvlog/xelab/xsim stderr 全空 |
| cache client + 七客户端 DDR BFM | `75ac975f5ec049a6b579e00c14dd41d0` | wrapper 置 `ENABLE_CACHE=1`，与 6 个合成读写客户端共同穿过真实七客户端仲裁；`cache_logical_reads=9`、`cache_refill_reads=16`、`cache_rsp=12`、`writes=1`，AXI `AW/W/B=19/19/19`、`AR/R=36/36`，并覆盖 AW/W/AR 与 R/B 随机停顿/间隙；闭合 cache-client→共享 DDR fabric 小帧边界，但不是 portable SoC 全生命周期 |
| portable SoC 全链小帧 DDR BFM（历史 table-index-aware 单帧） | `b82811285e52462c9c5b7ed7d76f01be`（基线 `78f...`） | `frame=8x8 done=1 descriptors=22 stage_mask=1fffff display_done=1`；AXI `AW/W/B=852/868/852`、`AR/R=1119/2199`；真实 capture/CNN/cache/client-6/七客户端/display 完成；保留为历史基线 |
| portable SoC 最终单帧 | `5c416178cd90437ea6e223a3711717e8` | `frame=8x8 done=1 descriptors=22 stage_mask=1fffff display_done=1`；AXI `AW/W/B=852/868/852`、`AR/R=1119/2199`；干净源码、干净测试台、stderr 为空 |
| portable SoC 最终两帧 ownership | `4b28f72f506043cf905abbaa74d3b9b7` | `frame=8x8 done=2 descriptors=44 stage_mask=1fffff swaps=2 drops=0 display_done=1`；AXI `AW/W/B=1704/1736/1704`、`AR/R=2353/3703`；干净 detached xsim 回归 |
| portable SoC shape-scaled 8×8（当前源码） | `e2e36e004f35429f93f4bc297490d713` | `done=1 descriptors=22 display_done=1`；AXI `AW/W/B=852/868/852`、`AR/R=1119/2199`；shape-parameterized BFM 源码下重新通过 |
| portable SoC shape-scaled 16×8（当前源码） | `377f5dbeded545318e1bde1950d9bebe` | `done=1 descriptors=22 display_done=1`；AXI `AW/W/B=1688/1736/1688`、`AR/R=2123/3251`；动态单帧 PASS |
| portable SoC shape-scaled 16×8 两帧（gate 前历史快照） | `7273cf5182874941a893d9b1a8b085a8` | `done=2 descriptors=44 swaps=2 drops=0 display_done=1`；AXI `AW/W/B=3376/3472/3376`、`AR/R=4505/6743`；保留作 gate 前历史对照，latest gate 见下一行 |
| portable SoC shape elaboration 64×48 | `efc0181ebc9a427c8d9dd7a48da98c1a` | xvlog/xelab exit 0、stderr 为空；`C1_R1_PORTABLE_SOC_SHAPE_ELAB_PASS frame=64x48`。仅形状/编译边界，不是动态 xsim 或性能 PASS |
| portable SoC shape-scaled 64×48 单帧 | `c1_64x48_single_20260825` | `done=1 descriptors=22 swaps=1 drops=0 display_done=1`；AXI `AW/W/B=40224/41664/40224`、`AR/R=48427/51643`；xvlog/xelab/xsim exit 0、三阶段 stderr 为空 |
| portable SoC latest gate 8×8 单帧 | `c1_8x8_gate_20260825` | `done=1 descriptors=22 display_done=1`；AXI `AW/W/B=852/868/852`、`AR/R=1119/2199`；三阶段 exit 0、stderr 为空 |
| portable SoC latest gate 16×8 两帧 | `c1_16x8_two_gate_20260825` | `done=2 descriptors=44 swaps=2 drops=0 display_done=1`；AXI `AW/W/B=3376/3472/3376`、`AR/R=4185/5463`；三阶段 exit 0、stderr 为空 |
| portable SoC latest gate 64×48 单帧 | `c1_64x48_single_gate_20260825` | `done=1 descriptors=22 swaps=1 drops=0 display_done=1`；AXI `AW/W/B=40224/41664/40224`、`AR/R=48427/51643`；三阶段 exit 0、stderr 为空 |
| portable SoC latest gate 64×48 两帧 | `c1_64x48_two_gate_20260825` | `done=2 descriptors=44 swaps=2 drops=0 display_done=1`；AXI `AW/W/B=80448/83328/80448`、`AR/R=96793/102295`；三阶段 exit 0、stderr 为空 |
| portable SoC native 640×480 compile/elaboration | `c1_640x480_final_elab_20260825` | `C1_R1_PORTABLE_SOC_SHAPE_ELAB_PASS frame=640x480`；xvlog/xelab exit 0、stderr 为空；含 input/output/tensor 非重叠与 associative-store 前置断言，未启动 xsim |
| native 640×480 display staged preflight | `native_prefetch_run2_20260825` | 独立真实 display pair 双路完成 `307200/307200` 像素响应、`4800/4800` AR、`76800/76800` R，`underflow=0/0`；覆盖地址/4 KiB/行边界、XRGB lane、双行 CDC；不含 portable SoC capture/CNN/共享仲裁 |
| native 640×480 capture-writer staged preflight | `c1_native_capture_writer_final_20260825` | 真实 XRGB writer 三 slot 完成 `frames=3`、`AW/W/B=14400/230400/14400`、`readback_pixels=921600`，slot `00100000/0022c000/00358000`；覆盖写地址/打包/4 KiB/行边界和源端回压；不含 camera/CSI、input DMA、CNN/共享仲裁 |
| native 640×480 capture/table/ISP staged preflight | `c1_native_capture_table_paced_full_20260825` | 真实 `c1_r1_capture_subsystem` 完成 3×642×482 RAW10→640×480，`pixels/sof/eol/eof=921600/3/1440/3`，Gamma `1024`，table `AR/R=3/3`，writer `AW/W/B=14400/230400/14400`；camera blanking 遵循 frontend sensor-overflow 合同；不含 CSI/portable SoC input DMA/共享仲裁/CNN/QoS |
| native 640×480 input-DMA/table/arbiter staged preflight | `c1_native_input_dma_full_20260825` | 真实 table reader + XRGB reader + 两主机 `c1_axi2_serial_arbiter_128` 三 slot 逐像素通过：`frame_pixels=921600`，table/frame `AR/R=3/3`、`14400/230400`，shared `AR/R=14403/230403`；覆盖地址/4 KiB/行边界、坐标/markers、reader sink stall；不含 boardless job/output DMA/七客户端/CNN/QoS |
| native 640×480 read→write DMA loopback staged preflight | `c1_native_dma_loopback_final2_20260825` | 真实 table/XRGB read master、read arbiter、XRGB writer、`c1_axi_write_skid_bridge`、write arbiter 和 associative DDR 回读闭合三帧：`frame_pixels=921600`，input `AR/R=14400/230400`，output `AW/W/B=14400/230400/14400`；覆盖输入/输出 slot 隔离、stream stall、AW/W/B 回压；不含 boardless job、七客户端完整 fabric、CNN/tensor、display/QoS/帧率 |
| native 640×480 boardless job staged preflight | `native_boardless_job_hold_full_20260825` | 真实 `c1_r1_boardless_frame_system` 完成 table/22 descriptor/input-output DMA/外部 CNN echo：`stages=22`、`cnn_in/cnn_out=307200/307200`、input `AR/R=4800/76800`、output `AW/W/B=4800/76800/4800`、`output_pixels=307200`；覆盖 boardless terminal/drain、descriptor barrier、地址图和逐像素 output 回读；不含 portable SoC 七客户端、真实 CNN/tensor、display/QoS/帧率 |
| native 640×480 boardless + 7-client fabric contention preflight | `native_fabric_full2_20260825` | 真实 boardless job 占 client-0，六个 procedural AXI peer 占 client-1..6，共享真实 N-way arbiter 与 randomized DDR BFM；synthetic `AW/W/B/AR/R=18/72/18/18/72`，job input/output 数据面完整，六 peer 最大等待 `118` cycles，逐像素 output 回读 PASS；证明 fabric forward progress，不等于七个 portable SoC 真实叶模块或 15 fps |
| native 640×480 fabric real parameter leaf slice | `native_fabric_param_full_20260825` | client-0 真实 boardless，client-1 真实 `c1_axi_parameter_loader` + `c1_r1_parameter_bank`，client-2..6 五个 procedural peer；`param_ar/param_r=66/1056`、`generation=1`，job `AW/W/B/AR/R=4800/76800/4800/4800/76890`，peer max wait `158/162/160/169/167`；xvlog/xelab/xsim exit 0、stderr 为空；只证明一个真实 read leaf 的 fabric 接入 |
| portable SoC internal seven-client traffic monitor（诊断） | `portable_client_gate_64x48_20260825` | bind-only monitor 观察 c0..c6 所需方向均有 handshake，但 c5 styled-display `max AR wait=1,243,738` cycles 超过 1,000,000 guard；xsim exit 1、stderr 为空，记录为当前 ID-less fabric starvation/QoS 风险，不计为 PASS |
| portable SoC display response FIFO（单帧 QoS prototype） | `portable_display_fifo_reader_gate_full_64x48_20260825` | depth=128、每 reader 预留 64 token credit；reader pre-AR gate + ARVALID 稳定性 guard；c4/c5 `max AR wait=76/83`、`r4/r5 hold=2/2`，完整 64×48 monitor/DDR BFM 严格 PASS。默认参数仍 bypass |
| portable SoC display response FIFO（连续帧 ownership） | `portable_display_fifo_credit_only_twoframe_8x8_20260825` | credit-only 门控在 8×8 两帧严格 PASS：`done=2 swaps=2 drops=0 display_done=1`，monitor c4/c5 max wait `8/13`、r4/r5 hold `1/1`；此前带 `!hold_requests` 的探索性版本在第二 pair deadlock，已废弃 |
| portable SoC display response FIFO（native-scaled 两帧） | `portable_display_fifo_credit_only_twoframe_64x48_20260825` | 64×48 两帧严格 PASS：`done=2 swaps=2 drops=0 descriptors=44`、`AW/W/B=80448/83328/80448`、`AR/R=96796/102358`，c4/c5 wait `76/83`、hold `2/2`；仍是 shape-scaled 功能/QoS 证据，不是 native 640×480 CNN 性能 |
| portable SoC display response FIFO（两帧 aggregate monitor） | `portable_display_fifo_twoframe_monitor2_64x48_20260825` | `job_completions=2` 后汇总 c4/c5 `AR/R=100/1600`、max wait `89/83`、hold `2/2`，并通过 `done=2 swaps=2 drops=0`；这是当前两帧 QoS 统计的 canonical run |
| native 640×480 display response FIFO pixel gate | `native_display_fifo_final_20260825` | 最新 reader/drain-guard 源码下 depth=128 分支逐像素 RGB/地址/CDC 严格 PASS：两路 `307200` responses、`4800` AR、`76800` R、`underflow=0/0`；不含 SoC CNN/QoS/资源签核 |
| display response FIFO Vivado proxy synthesis | `display_fifo_proxy_async_final2_20260825` | bypass→fifo128：`2600→3094 LUT`、`1141→1185 FF`、`1280→1584 LUTRAM`、BRAM `0→0`、DSP `4→4`；core 100 MHz WNS `+3.265→+2.470 ns`，pixel 71.43 MHz WNS `+8.470 ns`；仅为 Xilinx proxy 结构预算 |
| portable SoC native FIFO elaboration | `portable_fifo_native_elab_final_20260825` | 完整 `c1_r1_portable_soc` 在 `640×480`、FIFO depth=128 参数下 xvlog/xelab 通过且 stderr 为空；长帧 xsim、underflow/deadline 尚未作为 PASS |
| portable SoC native all-optional elaboration | `treefull_final_native_elab_20260825`（前一版 final-dot-sum 快照：`dottree_final_native_elab_20260825`） | `640×480 + FIFO128 + relaxed descriptor + tensor-address/start-config/full product→pair→quad→dot tree` xvlog/xelab PASS、stderr 为空；未启动 native full-xsim，不能外推性能 |
| portable SoC 640×480 FIFO system proxy synthesis | `portable_soc_fifo_proxy_post_pipeline_default_20260825` | 最终源码 bypass→fifo128：`44792→45298 LUT`、`28082→28123 FF`、`5644→5948 LUTRAM`，BRAM/DSP 不变；strict FIFO128 core WNS `-53.327 ns`，旧 `-53.944 ns` 仅为流水化前历史快照；下一 P0 仍是 engine/tensor/控制路径流水化与真实长帧周期门 |
| descriptor validation relaxed timing proxy | `portable_soc_descriptor_relaxed_post_pipeline2_20260825`；xsim `descriptor_relaxed_fifo_8x8_20260825` | strict 默认保持；最终源码 relaxed=0 资源 `44713 LUT/28061 FF/93 DSP`，直接 path `-15.659 ns`、Q→D data-only `-13.455 ns`，且 8×8 simulation ABI guard PASS。旧 canonical `44799/-15.958` 只作历史快照；tensor address 仍未闭合 |
| fast tensor address arithmetic experiment | `portable_soc_descriptor_relaxed_fast_post_pipeline2_20260825`；xsim `descriptor_relaxed_fast_fifo_8x8_20260825` | 最终源码 fast-address 资源 `45506 LUT/28073 FF/93 DSP`，直接 path `-16.647 ns`、Q→D `-14.216 ns`；相对最终 relaxed 增加 793 LUT，shift/add 仍为负优化，参数保留为实验开关但默认禁用 |
| tensor pixel/final address pipeline experiment | `descriptor_relaxed_pipelined2_fifo_8x8_20260825`；proxy `portable_soc_descriptor_relaxed_pipelined2_data_proxy_20260825` | 新增 `PIPELINED_TENSOR_ADDRESS=1`，8×8 完整链 PASS；native proxy `44641 LUT/28069 FF/84 DSP`，原 tensor-address 关键路径从 Q→D top-20 消失，数据专用报告最差 `-4.772 ns`（camera FIFO→resize）；默认仍关闭，且仍未完成 100 MHz/15 fps |
| tensor pixel/final address pipeline two-frame ownership | `descriptor_relaxed_pipelined2_twoframe_8x8_20260825` | 两帧 `done=2 swaps=2 drops=0 descriptors=44 stage_mask=1fffff display_done=1`，`AW/W/B=1704/1736/1704`、`AR/R=2188/3374`；跨帧地址状态和 drain/ownership 通过 |
| optional compute-start/config register boundary | `descriptor_pipelined2_compute_start_8x8_20260825`；两帧 `descriptor_pipelined2_startcfg_twoframe_8x8_20260825`；strict `descriptor_pipelined2_startcfg_strict_8x8_20260825`；proxy `portable_soc_descriptor_relaxed_pipelined2_startcfg_proxy_20260825` | 在 `PIPELINED_TENSOR_ADDRESS=1` 之上加入 `PIPELINED_START_CONFIG=1`；relaxed 640×480 proxy `44670 LUT/28141 FF/84 DSP`，direct `-4.950 ns`、Q→D `-4.601 ns`，相对 pixel/final 增加 29 LUT/72 FF；单帧、两帧和 strict 兼容回归通过，默认仍关闭并增加一拍 launch latency |
| optional final-dot-sum/accumulator boundary | `aba8388974174f209ea0c7c2cc2dcbf0`；engine `8b6b7df80aa1482ead7c3cdea4269e55`；budget `f00e07cb7e884af7960dfaae36696bfb` / `0475bd62524b40388af6fe685dfd2cc9`；`descriptor_pipelined2_startcfg_dottree_final_8x8_20260825`；proxy `portable_soc_descriptor_relaxed_pipelined2_startcfg_dottree_proxy_20260825` | `PIPELINED_DOT_TREE=1` 当前只寄存完整 dot-sum 与上下文，未切分乘法/reduction tree；独立 dot、22-stage engine、非零 10,000-cycle stage-18 budget 与完整 8×8 链 PASS；640×480 proxy `44691 LUT/28606 FF/84 DSP`，direct `-4.950 ns`、Q→D `-4.752 ns`，相对 start-config `+21 LUT/+465 FF` 且未改善时序，默认关闭 |
| optional full product/pair/quad/dot tree | `4998087102b6420ba49009b7216b3f96`；engine `a3f71de333da470483f247902d497d52`；`descriptor_pipelined2_startcfg_treefull_8x8_20260825`；native `treefull_final_native_elab_20260825`；proxy `portable_soc_descriptor_relaxed_pipelined2_startcfg_treefull_proxy_20260825` | `PIPELINED_DOT_TREE_FULL=1` 将 8 个 dot lane 的 product→pair→quad→dot-sum→accumulator/overflow 做成四级弹性流水；standalone/22-stage engine/完整 8×8 链与 640×480 all-option elaboration PASS，full-tree proxy `44594 LUT/31396 FF/84 DSP`，direct `-4.950 ns`、Q→D `-4.701 ns`；相对 start-config `-76 LUT/+3255 FF`，II=1（填充后）但增加约四级 latency，仍未闭合 100 MHz，默认关闭 |
| optional full-tree cross-frame ownership | `descriptor_pipelined2_startcfg_treefull_16x8_twoframe_20260825` | 16×8 两帧 full-tree 动态 PASS：`done=2 swaps=2 drops=0 descriptors=44 display_done=1`，`drain_cycles=1438892`，`AW/W/B=3376/3472/3376`、`AR/R=4194/5502`；stderr 为空，证明四级 latency、display drain 与跨帧 ownership 兼容 |
| optional full-tree shape-scaled 64×48 | `descriptor_pipelined2_startcfg_treefull_64x48_20260825` | 64×48 单帧 full-tree 动态 PASS：`done=1 swaps=1 drops=0 descriptors=22 display_done=1`，`drain_cycles=907593`，`AW/W/B=40224/41664/40224`、`AR/R=48427/51643`；stderr 为空，证明更大 shape 的 AXI/ownership 守恒 |
| optional registered descriptor replay（负优化） | `descriptor_replay_treefull_8x8_20260825`；proxy `portable_soc_descriptor_relaxed_pipelined2_startcfg_treefull_descr_replay_proxy_20260825` | 512-bit descriptor replay 加一拍后 8×8 full-tree 功能 PASS、无 per-stage bubble；proxy `47114 LUT/41837 FF/84 DSP`，direct `-4.824 ns`、Q→D `-4.701 ns`，相对 full-tree `+2520 LUT/+10441 FF` 且 LUTRAM `5948→5636`，明确不选用，默认关闭 |
| optional capture-time descriptor prevalidation | `prevalidate_replay_8x8_final_20260825`；native `prevalidate_native_elab_640x480_20260825`；proxy `prevalidate_treefull_proxy_final_20260825` | 每 stage 只缓存 5-bit validator result；8×8 `done=1 descriptors=22 swaps=1 drops=0`，AXI 计数保持 `852/868/852` 与 `1119/2199`；640×480 proxy `44660 LUT/31374 FF/84 DSP`，direct `-4.824 ns`、Q→D `-4.701 ns`，仅相对 full-tree `+66 LUT/-22 FF`，仍默认关闭 |
| optional abort fanout replication（负优化） | `abortrep_8x8_postpatch_20260825`；proxy `abortrep_treefull_proxy2_20260825` | 8×8 AXI/ownership 计数保持；proxy `44727 LUT/31380 FF/84 DSP`，direct `-5.557 ns`、Q→D `-5.434 ns`，相对 prevalidation 恶化约 `0.733 ns`，默认关闭并停止 |
| optional registered fatal fault ticket | controller legacy `8be7cfb239b449eabd37f12f9fbe276a` / ticket `e600e09f5487450c935bab144b7ff09c`；SoC `fatal_ticket_soc8x8_20260826`；native `fatal_ticket_native_elab_20260826`；paired proxy `fatal_ticket_paired_legacy_proxy_20260826` / `fatal_ticket_fulltree_proxy_retry2_20260826` | `REGISTER_FATAL_TICKET=1` 只把内部 fatal 延后一拍并锁存 code/address；软件 ABORT 与 disable 仍为原有立即语义，sticky fault 每次拉高只报告一次。controller 两模式、8×8 动态链和 640×480 elaboration 均 PASS。严格配对 proxy 为 legacy `44660 LUT/31374 FF`、direct/Q→D `-4.824/-4.701 ns`，ticket `44672 LUT/31420 FF`、`-4.350/-0.877 ns`；目标 abort 链退出 top-20，开关暂默认关闭。 |
| parameter scheduler registered validation/terminal control | artifact `param_scheduler_directed_final_20260826`；engine `cc9e43673b88499a9813964e6d91ed81`；SoC `param_terminalflag_soc8x8_20260826`；proxy `param_terminalflag_ticket_proxy_20260826` | START 原子快照配置/派生 metadata，`ST_VALIDATE` 将 DSP 计算与 size/range/error 分开一拍；末字有效字节数与 terminal 标志均寄存。训练工件 1,030 reads/writes、16,379 B 不变，六种错误码优先级、validation abort、live-cfg 改写隔离均 PASS。ticket 配置 proxy `44739 LUT/31618 FF/84 DSP`，direct/Q→D `-2.069/-0.694 ns`；相对上一阶段 `+67 LUT/+198 FF`，每层 +1 cycle，parameter scheduler 旧关键端点退出 top-20。 |
| frame-manager ordered READY queues | manager `ready_fifo_directed_20260826`；controller `frame_ready_fifo_soc_control_20260826`；SoC `ready_fifo_soc8x8_20260826`；proxy `ready_fifo_ticket_proxy_20260826` | 以3-entry输入/2-entry输出小FIFO显式保存单owner capture/CNN天然产生的frame顺序，移除每周期32-bit oldest-frame扫描；free-slot、drop-oldest、NN/display ownership和接口拍数不变。定向覆盖满队列、两类同周期pop+push和abort；完整SoC计数保持。proxy `44272 LUT/31597 FF/78 DSP`、direct/Q→D `-0.306/-0.060 ns`，相对上一阶段 `-332 LUT/-59 FF`，旧manager路径退出top-20。 |
| bilinear complement-weight range reduction | primitives `interp_nosat_primitives_20260826`；system `interp_nosat_system_20260826`；SoC `interp_nosat_soc8x8_20260826`；proxy `interp_nosat_ticket_proxy_retry1_20260826` | 合法X/Y Q0.12权重各自和为4096，因此pair rounded numerator严格小于2^20、输出天然为u8；删除不可达饱和carry并以仿真断言守住生产者合同，不改elastic pipeline。10,726组插值和完整链PASS；插值首路径退出top-20。proxy `44175 LUT/31595 FF/78 DSP`、direct/Q→D `-0.291/-0.060 ns`，相对上一阶段 `-97 LUT/-2 FF`。 |
| registered launch-contract fault boundary | bridge `contract_fault_boundary_retry1_20260826`；SoC `contract_fault_boundary_soc8x8_20260826`；proxy `contract_fault_boundary_ticket_proxy_20260826` | live generation比较仅即时阻止尚未发出的START；运行期error/transfer gate使用sticky fault寄存器，故障帧捕获边沿最多退休一个在途beat并随后abort，不能提交display。定向覆盖`0x03/0x04`、停止/恢复；完整SoC守恒。proxy `44165 LUT/31592 FF/78 DSP`、direct/Q→D `-0.191/-0.060 ns`，旧跨层error/ready路径退出top-20。 |
| pipelined descriptor verdict boundary | decoder `925d7efd0f734711b47b375e288ca213`；loader `76b1252b78934aad946ca4280d27a675`；SoC `659a381895554f4fa4b05b9248a8c011`；proxy `descriptor_verdict_pipe_ticket_proxy_retry2_20260826` | config-loader decoder以capture→validate/verdict→publish切断宽校验树到512-bit CE/command-valid的同拍反馈，每descriptor增加2拍；默认decoder兼容模式不变。429向量、loader错误/abort/重启和完整SoC均PASS。proxy `44202 LUT/31605 FF/78 DSP`、direct/Q→D `-0.182/+0.344 ns`；Q→D首次全部闭合。 |
| preserved four-stage bilinear pipeline | primitives `interp_preserved_pipe_primitives_20260827`；system `interp_operand_pipe_system_20260826`；SoC `2dc8c3d400434b00a0de89c2a19cd91d`；proxy `interp_preserved_pipe_ticket_proxy_20260827` | horizontal→operand→vertical-product→rounded-output四级弹性流水；算术payload使用保层属性阻止Vivado跨DSP重定时。10,726组向量、313个system输出和完整SoC均PASS。proxy `44568 LUT/32064 FF/78 DSP`、direct/Q→D `+0.136/+0.340 ns`，两份报告均0违例；Artix-7 100 MHz综合代理首次整体闭合。 |
| optional table response elastic FIFO | `tablefifo_8x8_20260825`；proxy `current_treefull_prevalidate_tablefifo_nohelper_20260825` | 8×8 full-xsim PASS；当前源码同条件 proxy `46174 LUT/37790 FF/84 DSP`，相对 FIFO=0 `-6 LUT/+128 FF`，direct/Q→D WNS 不变；默认关闭，作为协议隔离开关 |
| optional unified output FIFO protocol/integration | `unified_output_fifo_latest_20260825`；`unified_output_fifo_registered_error_gate0_recheck_20260825`；`unified_fifo_errorgate0_gated_8x8_20260825`；`unified_fifo_errorgate0_gated_8x8_twoframe_20260825`；`unified_fifo_errorgate0_gated_native_elab_20260825`；paired proxy `current_treefull_prevalidate_unifiedfifo_errorgate0_gated_nohelper_retry1_20260825` | standalone、同步 error-gate unit、8×8 单帧/两帧和最终 640×480 elaboration PASS；最终集成 proxy `46390 LUT/37656 FF/5716 LUTRAM/84 DSP`，direct/Q→D `-4.831/-4.702 ns`，相对 FIFO=0 资源增加但 timing 无收益；已接线但默认关闭，不改变默认路径 |
| optional unified output skid protocol/integration | `skid_abort_error_default_retry_20260826`；`skid_abort_error_registered_retry_20260826`；`skid_soc_8x8_20260826`；`skid_soc_8x8_twoframe_20260826`；`skid_soc_16x8_20260826`；`skid_native_elab_20260826`；paired proxy `current_treefull_prevalidate_unifiedskid_nohelper_20260826` | 1-entry/103-bit standalone（默认与同步 error gate，含 abort directed case）、8×8 单帧/两帧、16×8、640×480 elaboration 均 PASS；proxy `46243 LUT/37766 FF/5636 LUTRAM/84 DSP`，direct/Q→D `-5.415/-5.415 ns`，相对无边界为负优化；协议候选保留，默认关闭 |
| portable SoC u64-fix compatibility gates | `c1_8x8_u64fix_gate_20260825` / `c1_64x48_two_u64fix_gate_20260825` | 8×8 单帧与 64×48 两帧重新通过；后者 `done=2 swaps=2 drops=0`、`AR/R=96793/102295`；三阶段 stderr 为空 |

完整标记和 stderr/证据等级见 `TEST_RESULTS.md`。

## 拿板前仍需完成的 P0

1. 用更有代表性的内容/风格数据继续训练和主观评估；当前工件可做 RTL 联调，但不能作为最终画质结论。
2. trained artifact 的 descriptor/parameter-scheduler/arena ABI 已完成；同一真实 arena 的 8×8 缩放 descriptor 已完成 engine 逐阶段 RTL/Python bit-exact，并进一步完成 adapter→engine→tensor write-back 的 8×8 逐拍闭环（22 stages、896 operands、836 results、64 final pixels）。tensor adapter 的 native 640×480 `width*height`/`y*width` 中间表达式已显式扩展到 64 位，并由 `c1_adapter_u64fix_20260825` 兼容回归覆盖；仍需把该证据扩展到 portable SoC 真实共享 DDR，再做 native 640×480。顶层 smoke 或 ABI 回归不能替代该测试。
3. 继续流水化重排版 engine 的关键路径。旧 flat-cache 已由 128-bit ABI BRAM→逐层 OIHW 重排→固定 Conv/DW 小 bank 取代，不再是“待 RAM 重构”。最终完整 proxy run `6cb8dfd59ed5473383eed87f52b2a013` 使用 28,298 LUT、11,168 FF、2 BRAM36、35 DSP，旧 window→dot overflow 最差路径已经消失；但新最差 `replay_index`→descriptor decoder error reset 为 14 级/14.351 ns，`WNS/TNS=-4.965/-2511.307 ns`。新增的可选 `PIPELINED_START_CONFIG` 已把 camera-FIFO→resize Q→D 路径从 `-4.772 ns` 推到 dot overflow `-4.601 ns`，代价 29 LUT/72 FF 和一拍启动延迟。`PIPELINED_DOT_TREE=1` 的 final-dot-sum 边界实验仍为负结果（`44691 LUT/28606 FF/84 DSP`，Q→D `-4.752 ns`）。随后真正的 `PIPELINED_DOT_TREE_FULL=1` 已完成 product→pair→quad→dot 四级弹性流水，并通过 standalone/engine/8×8/native elaboration；但 full-tree proxy 为 `44594 LUT/31396 FF/84 DSP`、Q→D `-4.701 ns`，仍未闭合 100 MHz。针对 descriptor 最差路径的 `PIPELINED_DESCRIPTOR_REPLAY=1` 虽在 8×8 功能通过，却把 proxy 增至 `47114 LUT/41837 FF/84 DSP`，不予采用。新 `PREVALIDATE_DESCRIPTOR_REPLAY=1` 以 5-bit cache 结果取得同样 `-4.824 ns` direct path，资源仅 `+66 LUT/-22 FF`，但 Q→D 仍 `-4.701 ns` 且依赖 cache integrity；该开关也不默认启用。最新 full-tree/prevalidation 报告显示最差 Q→D 已转为高扇出 abort/ready 控制链（详见 `READY_ABORT_TIMING_PREFLIGHT.md`），下一步先做默认关闭的 `REPLICATE_ABORT_CONTROL` 网表复制实验，并重新检查 latency/budget/deadline contract。
4. 独立 memory seam、三行 all-group C8 payload cache、adapter sideband、tensor-window-cache seam、optional-top 结构接线，以及真实 adapter→cache→64-bit BFM、adapter→cache→AXI128 bridge→BFM、client-6→七客户端 DDR BFM 和 portable SoC shape-scaled latest gate 矩阵均已完成。仿真期间修复了 parameter reload generation race、首次显示 bootstrap/未选中源 drain 死锁、重复 pending-pair 启动 livelock、新 pair 预取期间过早消费导致的 frame ownership 问题，以及共享 ID-less AXI 读响应被 display reader 反压后造成的 CNN starvation；当前 64×48 两帧 gate 为 `swaps=2 drops=0`。仍需 AXI burst、多个 outstanding 和并行 MAC/channel/group 调度；顶层 `flush_req` 暂绑 0。portable SoC 默认 `1,000,000,000` clocks 只是宽松功能 watchdog；100 MHz/15 fps 预算为 6,666,667 clocks。
5. 64×48 单帧和两帧均已完成动态回归，且独立 native display prefetch、capture-writer、capture/table/ISP、两主机 input-DMA/arbiter、read→write DMA loopback、640×480 boardless job 与 boardless+7-client fabric preflight 已完成；boardless job 已把 table/descriptor、input reader、Resize/C8 shell、外部 CNN echo、XRGB writer 和真实 job terminal/drain 串成一帧逐像素回读闭环。下一步把 fabric preflight 中的 synthetic peer 替换为完整 SoC 的真实 capture writer、frame reader/writer、parameter/tensor、compute 和 display readers，同时争用七客户端 AXI，检查 QoS、无饿死、abort/drain、无撕裂，并记录周期/带宽分布。当前 gate 与各分阶段 preflight 仍不外推长帧真实 CNN 性能。
   `native_fabric_full2_20260825` 已先完成其中的 fabric 风险切片：native boardless client-0 与六个 synthetic peer 共同穿过真实七客户端仲裁，六 peer 最大等待 118 cycles 且全部读回。剩余工作因此收窄为把 synthetic peer 替换成 capture/parameter/display/tensor 真实叶模块，并补真实 engine、underflow 和 15 fps 周期门。
    `native_fabric_param_full_20260825` 已完成第一枚真实叶替换（parameter-loader + parameter-bank）。portable SoC 内部 monitor 的 `portable_client_gate_64x48_20260825` 暴露 c5 styled-display 最大 AR 等待 1,243,738 cycles；随后 protocol-safe display response FIFO 已把单帧 64×48 的 c4/c5 wait 降到 76/83、response hold 降到 2/2，并在 8×8 两帧验证 `swaps=2 drops=0`。仍需把 credit-only FIFO 扩展到 native portable-SoC 长帧、完成代理资源/时序评估，并将 underflow/deadline 纳入硬门。
6. 清理最后的 Vivado 代理时序：最新含 DMA boardless 与 Resize 分别为 `-0.191 ns`、`-0.154 ns`；DW 最终专项已到 `+3.039 ns`。这些仅是 Xilinx 综合后代理，不是 Ti60 时序。

### 2026-08-27 15 fps 吞吐优化 seam

本阶段完成了板卡前的 AXI/cache/fabric/MAC 增量，但没有改动默认 portable-SoC
接线：

- 读 leaf、3-row cache shell、读 fabric queue 及两个 leaf 的集成 wrapper 均通过
  detached xsim；集成小流量为 `16 logical → 6 AR/8 R beats`，最多 5 个在途描述符。
- 写 leaf 通过 `req=21/aw=10/w=13/packed=7/errors=2`，明确仍是单 outstanding；
  新写 fabric queue 让三个独立 writer 的 AW 提前排队，xsim 为
  `6 AW/12 W/6 B/max_outstanding=3`。
- `c1_dot8x8_requant_bank` 双 lane/full-tree 回归通过；它只提供输出组并行算术，
  尚未接入顺序 engine 的 stage scheduler。
- Artix-7 proxy：基础写 fabric `370 LUT/478 FF/WNS +3.787 ns`；响应阈值
  优化后的两个读 leaf+fabric 为 `31905 LUT/10075 FF/WNS +1.928 ns`，读
  response FIFO 在该配置仍落为 distributed RAM/LUTRAM，Ti60 EBR 映射待
  Efinity。新增双 lane 写 wrapper 为 `4308 LUT/10091 FF/WNS +1.203 ns`。
- Python 新增 fabric outstanding=1/2/4/8/16/32 扫描；理想 cache+pack2、
  response latency=4 的 memory-only bound 在 out=2 已过 15 fps 门槛，但共享
  CNN FSM 仍约 2.53 fps（legacy）到 6.04 fps（两组 II=1），所以当前项目仍不能
  宣称 15 fps。

完整文件、复现入口、假设和未解决风险见 [`15FPS_THROUGHPUT_PHASE.md`](15FPS_THROUGHPUT_PHASE.md)。

## 需要 Efinity、但通常不必等待实体板

1. 生成 Ti60 MIPI CSI-2、DDR controller/PHY、Sapphire、PLL 和显示相关 IP；
2. 按竞赛板原理图冻结封装、lane、pin、I/O standard、时钟和 reset constraint；
3. 首次 Ti60 综合/布局布线，核对 LE、DSP、M10K、端口 banking 和 WNS；
4. 生成 Sapphire BSP、启动/链接脚本、PLIC、中断号和 DDR cache 属性。

## 真正依赖实体板的步骤

1. SC431HAI 上电/I2C、lane/polarity、VC/DT、RAW 相位、曝光和增益；
2. D-PHY/CSI 稳定接收、ECC/CRC/坏帧恢复；
3. DDR PHY training 与七客户端最坏并发/QoS；
4. HDMI/并行显示物理输出、PLL、显示器兼容和真实 CDC/reset；
5. 板上 640×480 风格输出至少 15 fps，长时间无错帧、撕裂和欠载，并测功耗/温升。

## 选题决策门槛

当前适合继续做赛题一的板前降险，但不应仅因“RTL 能仿真”就认定可交付。最终选题至少要同时通过：

- 风格画质门：真实候选风格在独立图片上主观与客观可接受；
- 算法一致性门：trained artifact 的 22-stage RTL/Python 端到端 bit-exact；
- 性能门：优化后周期模型与仿真证明 640×480@15 fps，并留 DDR/watchdog 余量；
- 器件门：Efinity place-and-route 对 Ti60 的 M10K/DSP/LE/100 MHz 有可解释余量。

任一门失败时，先评估 tile/cache/burst/并行调度、参数单 bank、通道/IRB 缩减和输入模式降级；仍无法闭合再重新评估选题。

### 最新控制路径实验结论

`REPLICATE_ABORT_CONTROL=1` 的 8×8 回归 `abortrep_8x8_postpatch_20260825` 功能
通过，但历史、非同源码配对的 640×480 proxy `abortrep_treefull_proxy2_20260825` 变为
`44727 LUT/31380 FF/84 DSP`、direct `-5.557 ns`、Q→D `-5.434 ns`，相对
prevalidation 快照恶化约 `0.733 ns`；该差异不能单独归因于复制树，已停止该方向。
当前源码同条件 table response FIFO 只增加 `128 FF` 且 WNS 不变；完整 payload 的
unified output FIFO 已接入可选 bridge，并通过单帧/两帧/native elaboration 与同步
error-gate unit。组合 error gate 版本会把 Q→D 恶化到 `-6.098 ns`；bridge-local
error gate=0 后恢复到 direct/Q→D `-4.831/-4.702 ns`，但相对 FIFO=0 仍增加约
`210 LUT/80 LUTRAM`、没有 timing 收益，因此同样保持默认关闭。下一步只评估更靠近
engine 的局部 payload elastic/skid 边界，不对 raw abort/ready 裸延迟。

### 2026-08-26 shared-fabric R-response skid

- `c1_axi_n_serial_arbiter_128` 增加默认关闭的 `READ_RESPONSE_SKID`，portable SoC 以 `ENABLE_FABRIC_READ_RESPONSE_SKID` 选择，legacy 周期行为不变。
- skid 保存完整 `{RDATA,RRESP,RLAST}`，支持同周期 consume-and-replace；ARLEN 推导的末拍也作为本地 terminal，末拍等待客户端时不会误接收协议违规的 extra beat。
- legacy/skid 均通过七客户端 4-beat burst 压力：56 个读 burst、224 个 R beat、56 个写事务；skid 另覆盖一笔定向 missing-RLAST。
- 8×8 portable SoC 动态链保持 22 descriptors、`done/swaps/drops=1/1/0` 以及原 AXI 事务数。DDR-side R stalls 从 `1952595` 降为 `0`，client-side `fabric_r_stalls=1951641`，证明反压被隔离而非删除。
- 最终源码 640×480 elaboration 通过。full-tree proxy 为 `44640 LUT/31490 FF/84 DSP`、direct/Q→D `-4.824/-4.701 ns`，最差仍是 camera FIFO→capture error→fatal/abort→output-DMA 控制链；因此该开关保持默认关闭，下一轮转向源端注册化故障票据。
- 七客户端 detached runner 的 FAIL 检测也已修正：下划线 marker 中 `_FAIL` 现在会使 run 失败，首轮误判状态不作为证据。

### 2026-08-26 registered fatal fault ticket

- `c1_r1_soc_control` 新增默认关闭的 `REGISTER_FATAL_TICKET`。启用时，内部 fatal 的优先级分类仍在原处完成，但 `{code,address}` 被原子锁存；下一完整时钟周期产生 abort/report，且 sticky source 在先撤销前不会重复出票。
- `abort_pulse` 和 `!system_enable` 未经过 ticket，继续保持立即取消语义；两者也会清空尚未广播的内部 ticket，明确以外部取消优先。
- controller legacy/ticket 定向回归均为 `capture=1 nn=1 prefetch=6 swaps=1 repeats=5 errors=1`。ticket 模式额外确认 capture error 当拍不组合泄漏、下一完整周期三路 abort 同时有效、错误码/地址准确且只报告一次；共同的 manual-ABORT case 确认软件取消没有多一拍延迟。
- 8×8 完整 SoC 在 ticket 模式下仍为 `done/swaps/drops=1/1/0`、22 descriptors、`AW/W/B=852/868/852`、`AR/R=1119/2199`；640×480 源码结构展开通过。
- 当前源码严格配对 proxy（replay=0、prevalidate=1、address/start/full-tree 相同）显示：legacy `44660 LUT/31374 FF/84 DSP`、direct/Q→D `-4.824/-4.701 ns`；ticket `44672 LUT/31420 FF/84 DSP`、`-4.350/-0.877 ns`。即代价 `+12 LUT/+46 FF`，Q→D 违例缩小 `3.824 ns`；camera FIFO→fatal/abort 路径不再出现在两个 top-20 报告中。
- 新 direct 最差路径为 parameter scheduler 的 `weight_bytes_calc1/CLK`→`region_base_q_reg[10]/CE`（data delay `13.968 ns`）；新 Q→D 最差为 job frontend controller→CNN engine state（`-0.877 ns`，route `8.115/10.726 ns`）。因此 ticket 是有效但未闭合 100 MHz 的阶段性优化；板前还需多故障优先级、abort/drain、恢复和重复启动矩阵，默认值暂保留 0。

### 2026-08-26 parameter scheduler staged validation

- 原 scheduler 在接受 START 的同一拍完成 `Cin*Cout*9`、weight-size、四个 arena-end 检查和错误选择；由于 `begin_region` 只在合法配置调用，Vivado 把整条逻辑并入 `region_base_q.CE`，形成 17-level、`-4.350 ns` direct 路径。
- 第一小步将 weight-region metadata 在每次 START 无条件捕获，消除数据依赖 CE；proxy `param_ce_eager_ticket_proxy_retry_20260826` 为 `44571 LUT/31427 FF`、direct/Q→D `-3.629/-0.880 ns`，旧 CE 端点消失，但乘法仍到达 `error_reg/D`。
- 最终结构新增 `ST_VALIDATE`：START 边沿快照 opcode/channel 派生量、四个 region base/bytes、group/mask/taps 和 multiplier 结果；下一拍仅从寄存器执行 weight-size/33-bit arena-end 校验。该状态计入 busy，每层增加 1 cycle；region 切换也只使用快照，不再要求上游 `cfg_*` 在参数读取期间保持。
- 初版 `ST_VALIDATE` 暴露 `region_bytes_q`→cache byte-count→`affine_invalid_q` 的 `-2.692 ns` Q→D；预计算 5-bit terminal byte count 后为 `-2.236 ns`，再寄存 1-bit current-word-terminal 后最终为 direct/Q→D `-2.069/-0.694 ns`。
- 最终 proxy `param_terminalflag_ticket_proxy_20260826` 为 `44739 LUT/31618 FF/5832 LUTRAM/20 RAMB36/9 RAMB18/84 DSP`。相对 ticket-only `44672/31420` 为 `+67 LUT/+198 FF`；direct 违例缩小 `2.281 ns`，Q→D 缩小 `0.183 ns`。weight multiplier、`region_base.CE`、`region_bytes` 和 `region_word_count` 均不在两份 top-20。
- `param_scheduler_directed_final_20260826` 保持训练工件 `1030 reads/1030 writes/16379 B`，并通过 `ERR_OPCODE/CHANNELS/DW/ALIGNMENT/WEIGHT_SIZE/ARENA_RANGE` 六种优先级、`ST_VALIDATE` abort 无请求泄漏、以及 START 后立即破坏 live `cfg_*` 仍按快照完成 `9 reads/9 writes/136 B`。最终 full-tree/nonzero-budget engine 与 ticket 8×8 SoC 也均 PASS。
- 新 direct 瓶颈转为 tensor adapter `tap_source_y_fn3/CLK`→`addr_pixel_index_q_reg/A[15]`：`-2.069 ns`、12 levels（8 CARRY4）、data delay `11.526 ns`。新 Q→D 仍为 job frontend controller→CNN engine state：`-0.694 ns`、route `7.555/10.543 ns`。两者是下一轮对象；本轮不宣称 100 MHz 或 Ti60 sign-off。

### 2026-08-26 pipelined tensor tap-coordinate optimization

- `c1_r1_microstyle_tensor_adapter` 的 `PIPELINED_TENSOR_ADDRESS=1` 分支现在按 descriptor 合同实现 stride 1/2 的窄位移和 3×3 tap `-1/0/+1` 加减，去除 tap 坐标的通用 `integer` 乘法；legacy 分支保持不变。
- adapter legacy/pipeline standalone 与完整 performance 配置 8×8 SoC 全部 PASS。proxy 为 `44706 LUT/31622 FF/5832 LUTRAM/20 RAMB36/9 RAMB18/80 DSP`；相对上一阶段 `-33 LUT/+4 FF/-4 DSP`，direct WNS `-2.069→-1.066 ns`，Q→D `-0.694→-0.692 ns`。
- tap-source→pixel-index 已退出 timing top-20。新的 direct 首路径是 job-controller state→CNN `conv_tile_read_addr_q.CE`（15 levels、route 76.7%）；100 MHz 仍未闭合，下一阶段转向 start/enable 控制锥的局部寄存化/分层解码。
- 本轮生成的五个仿真/综合工作目录已在报告提取后删除（7.47 MiB）；只保留约 0.68 MiB 的状态、小日志和文本报告，不保留 Vivado/xsim 临时工程。

### 2026-08-26 registered-owner system-disable qualification

- `c1_r1_soc_control` 现在以已寄存的 `run_armed_q` 资格化 `!system_enable` 取消，去除 child busy→manager abort 的跨层组合反馈；system-disable 仍在同一周期广播，下一边沿才清除 owner。
- controller legacy/ticket 均新增并通过 disable-abort 定向检查；完整 performance 配置 8×8 SoC `disable_owner_soc8x8_20260826` 也保持 PASS。
- proxy `disable_owner_ticket_proxy_20260826` 为 `44740 LUT/31617 FF/5832 LUTRAM/20 RAMB36/9 RAMB18/80 DSP`。相对上一阶段 `+34 LUT/-5 FF`，direct WNS `-1.066→-0.682 ns`，Q→D `-0.692→-0.380 ns`；旧 boardless-busy→abort→dot-ready 路径退出 top-20。
- 新 direct 瓶颈为 parameter-bank BRAM→weight cache/mux→affine metadata 校验→`affine_invalid_q.D`（11 levels、route 63.8%）。下一阶段转向 affine 参数读取后的寄存/校验边界；100 MHz 与 Ti60 时序仍未签核。
- 本轮四个仿真/综合工作目录已删除（6.16 MiB）；仅保留约 0.64 MiB 的状态、小日志和文本报告。

### 2026-08-26 registered affine-word verdict boundary

- engine 保持 parameter-bank payload 同拍写入 cache，只将 multiplier/shift 的 per-word 非法 verdict 寄存一拍，再更新 sticky `affine_invalid_q`；没有增加128-bit payload寄存器或参数读取吞吐 bubble。
- `affine_verdict_pipe_engine_20260826` 通过22层、1,115次参数读取和6类故障，包含 `shift=48` affine-format 注入；完整 performance 配置8×8 SoC `affine_verdict_pipe_soc8x8_20260826` 也保持 PASS。
- proxy `affine_verdict_pipe_ticket_proxy_20260826` 为 `44568 LUT/31617 FF/5832 LUTRAM/20 RAMB36/9 RAMB18/80 DSP`。相对上一阶段 `-172 LUT`，direct WNS `-0.682→-0.613 ns`，Q→D 保持 `-0.380 ns`；BRAM→affine-invalid 与新 verdict 寄存器均退出 top-20。
- 新 direct 瓶颈为 `input_groups_q`→weight-repack channel/tap 控制→`repack_input_channel_q.CE`（12 levels、route 71.6%）。100 MHz 仍差0.613 ns；下一阶段转向 repack 终止条件/计数器使能。
- 本轮三个仿真/综合工作目录已删除（6.46 MiB）；仅保留约0.65 MiB的状态、小日志和文本报告。

### 2026-08-26 staged weight-layout verdict and repack terminals

- engine在parameter-done边沿寄存weight-layout verdict，并预计算最后linear byte、input channel和tap；新增一拍 `ST_WEIGHT_LAYOUT`，重排状态只使用寄存结果和等值比较。
- `repack_terminal_pipe_engine_20260826` 保持22层、836 outputs、1,115参数读和6类故障，新增10个控制等待周期；完整8×8 SoC `repack_terminal_pipe_soc8x8_20260826` 保持22 descriptors与全部AXI计数。
- proxy `repack_terminal_pipe_ticket_proxy_retry1_20260826` 为 `44544 LUT/31641 FF/5832 LUTRAM/20 RAMB36/9 RAMB18/80 DSP`。相对上一阶段 `-24 LUT/+24 FF`，direct WNS `-0.613→-0.587 ns`，Q→D保持 `-0.380 ns`；旧layout→repack CE路径退出top-20。
- 新 direct 瓶颈为tensor adapter `addr_pixel_index_q`→`request_addr_q.D`（2 DSP、4 CARRY4、data delay `10.468 ns`）。100 MHz仍差0.587 ns；下一阶段转向final tensor address的乘加分段。
- 本轮四个仿真/综合工作目录（含一次Vivado runtime早期失败）已删除，共6.46 MiB；仅保留约0.64 MiB状态、小日志和文本报告。

### 2026-08-26 pipelined final tensor-address strength reduction

- `PIPELINED_TENSOR_ADDRESS=1` 的final-address函数不再执行64-bit通用pixel×groups和bank乘法；合法groups 1–8改为32-bit移位/加减，bank 0/1/2改为常量分支。legacy路径和FSM周期数不变。
- 流水adapter `finaladdr_shiftadd_pipeline_20260826` 与完整8×8 SoC `finaladdr_shiftadd_soc8x8_20260826` 均PASS，地址序列、22 descriptors及AXI计数不变。
- proxy `finaladdr_shiftadd_ticket_proxy_20260826` 为 `44604 LUT/31656 FF/5832 LUTRAM/20 RAMB36/9 RAMB18/78 DSP`。相对上一阶段 `+60 LUT/+15 FF/-2 DSP`，direct WNS `-0.587→-0.380 ns`，Q→D保持 `-0.380 ns`；最终地址DSP链退出top-20。
- 当前唯一首路径为frame manager三slot `input_state`→ready候选搜索/索引→状态更新（17 levels、8 CARRY4）。100 MHz仍差0.380 ns；下一阶段转向候选搜索与状态写回分层。
- 本轮三个仿真/综合工作目录已删除（6.51 MiB）；仅保留约0.64 MiB状态、小日志和文本报告。

### 2026-08-26 frame-manager ordered READY queues

- `c1_frame_manager` 不再通过三槽/两槽的32-bit frame-id比较选择最老READY项，而是维护3-entry input READY和2-entry output READY顺序队列。单路capture与单路CNN保证完成顺序等于原frame-id顺序，因此该变化不增加grant/swap latency，也不改变drop-oldest与display引用计数语义。
- 新定向 testbench `tb_c1_frame_manager_ready_fifo.sv` 覆盖输入队满、两次drop-oldest、输入和输出各自的同周期pop+push，以及abort只清除非display ownership；`ready_fifo_directed_20260826`、controller与完整8×8 SoC均PASS。
- proxy `ready_fifo_ticket_proxy_20260826` 为 `44272 LUT/31597 FF/5832 LUTRAM/20 RAMB36/9 RAMB18/78 DSP`。相对上一阶段 `-332 LUT/-59 FF`，direct WNS `-0.380→-0.306 ns`，Q→D `-0.380→-0.060 ns`；frame-manager旧路径和新queue均不在两份top-20。
- 当前direct瓶颈转为resize插值DSP/carry链，Q→D瓶颈转为descriptor scheduler→decoder command-valid。100 MHz仍未签核，但寄存器到寄存器最差仅余0.060 ns；下一阶段需分别评估插值算术边界与descriptor verdict边界，避免把direct和Q→D混为同一问题。
- 本轮四个工作目录已删除（173个文件、6.034 MiB），保留证据0.632 MiB；新增专用runner会自动删除自身xsim工作目录。

### 2026-08-26 bilinear complement-weight range reduction

- `r1_bilinear_interp_rgb888` 利用公开的Q0.12 complement-weight合同，将每个pair的两个20-bit product和rounded sum保持在20 bit，直接选择 `[19:12]` 作为u8结果；移除对合法输入恒假的 `>255` 饱和比较。输入accept时新增simulation-only X/Y权重和断言。
- primitives回归覆盖50组坐标配置、3,211 requests和10,726组插值向量；完整resize system覆盖12组配置、313 requests/outputs；8×8 SoC的帧、descriptor和AXI守恒继续PASS。
- proxy `interp_nosat_ticket_proxy_retry1_20260826` 为 `44175 LUT/31595 FF/5832 LUTRAM/20 RAMB36/9 RAMB18/78 DSP`；相对上一阶段 `-97 LUT/-2 FF`，direct WNS `-0.306→-0.291 ns`，Q→D保持 `-0.060 ns`。原DSP cascade→饱和carry路径完全退出top-20。
- 当前direct路径已转为parameter generation合同错误→CNN error/egress ready→adapter final-ready→`output_x_q.CE`的15-level跨层反馈；下一阶段处理该error/ready边界。100 MHz仍未签核。
- 首次proxy为Vivado runtime `common.tcl`瞬时不可见，未进入HDL综合；retry通过。五个工作目录均已删除（184个文件、6.692 MiB），保留证据0.649 MiB。

### 2026-08-26 registered launch-contract fault boundary

- `c1_r1_microstyle_system_bridge` 的live generation合同比较仍用于双sink START抑制，但公开error、error code和运行期VALID/READY门改为使用sticky `start_contract_fault_q/code_q`，切断parameter-bank到tensor-adapter CE的跨层组合反馈。
- 故障捕获边沿最多允许一个已经present的输出beat退休；该job随后进入error/abort，output frame永不转为display ownership。新增定向回归覆盖parameter/config generation `0x04/0x03`、一拍边界、sticky停止和abort恢复，并修复组合块中error先读后写造成的事件仿真滞后一拍。
- 正常完整8×8 SoC保持22 descriptors、帧交换及全部AXI计数。proxy `contract_fault_boundary_ticket_proxy_20260826` 为 `44165 LUT/31592 FF/5832 LUTRAM/20 RAMB36/9 RAMB18/78 DSP`；相对上一阶段 `-10 LUT/-3 FF`，direct WNS `-0.291→-0.191 ns`，Q→D保持 `-0.060 ns`。
- 当前direct/Q→D均统一到descriptor scheduler→decoder：`descriptor_q.CE`与`command_valid.D`。下一阶段处理descriptor verdict/command-valid边界；100 MHz仍未签核。
- 本轮四个工作目录已删除（202个文件、7.390 MiB），保留证据0.644 MiB；定向runner自动清理xsim目录。

### 2026-08-26 pipelined descriptor verdict boundary

- `c1_layer_command_decoder` 新增可选 `PIPELINED_VALIDATION`；config-loader默认启用，依次执行512-bit capture、完整ABI validation到5-bit verdict寄存器、command/error publish。每descriptor增加2拍，校验函数与错误优先级未修改；standalone decoder默认保持原零额外周期模式。
- 默认decoder 429向量、config-loader 5次启动/错误/abort/双bank和完整8×8 SoC均PASS；SoC仍为22 descriptors、一次swap、无drop且AXI计数不变。
- proxy `descriptor_verdict_pipe_ticket_proxy_retry2_20260826` 为 `44202 LUT/31605 FF/5832 LUTRAM/20 RAMB36/9 RAMB18/78 DSP`，相对上一阶段 `+37 LUT/+13 FF`。旧descriptor首路径退出两份top-20；direct WNS `-0.182 ns`，Q→D WNS `+0.344 ns`且20条均满足100 MHz。
- 剩余direct top-20统一为resize插值DSP内部输入路径；这是下一阶段唯一时序目标。综合runner已改用run-local runtime并自动复制报告、删除工作目录。
- 本轮删除646个临时文件、92.464 MiB（含旧持久runtime副本），保留证据0.634 MiB。

### 2026-08-27 preserved four-stage bilinear pipeline

- `r1_bilinear_interp_rgb888` 现为四级弹性流水：水平插值、垂直operand寄存、垂直双乘积寄存、求和/half-up输出；新增两拍延迟但填充后II=1，所有metadata与算术payload同步停顿。
- 两次无保层实验虽分别增加product和operand RTL寄存级，Vivado仍把寄存器平衡进相邻DSP，direct保持 `-0.182 ns`。最终仅对operand/product算术payload使用 `DONT_TOUCH`，保证综合后真实断开DSP链；控制和metadata未禁止优化。
- 最终10,726组插值向量PASS；同结构system的313输出和完整8×8 SoC也PASS，22 descriptors、帧交换及AXI计数不变。proxy为 `44568 LUT/32064 FF/5832 LUTRAM/20 RAMB36/9 RAMB18/78 DSP`，相对上一阶段 `+366 LUT/+459 FF`。
- overall direct WNS `+0.136 ns`，Q→D `+0.340 ns`，两份top-20均无违例。Artix-7 100 MHz综合代理已闭合，但尚无place/route和Ti60/Efinity签核；后续优先级转向15 fps吞吐与带宽架构。
- runner已验证成功/失败自动清除综合目录，短路径runtime cache成功后也删除。本轮删除1,322个临时文件、187.044 MiB，保留证据1.880 MiB。

### 2026-08-27 AXI packing/MLP 吞吐阶段：响应反压与双 lane 写通路

- 写 leaf 的 `rsp_space` 原先把下游 `rsp_pop` 加入 `free_slots` 算术，形成
  tag FIFO→`rsp_pop`→carry→`BREADY`→leaf FSM 的跨层组合路径。现改为只比较
  `rsp_count_q < RSP_FIFO_DEPTH`；满槽同拍出队/入队时最多多一个气泡，但不会
  接收无空间的 B 响应。读 leaf 的 `rsp_capacity` 同样改成按本拍 0/1/2 个
  logical half 的静态阈值，不再由 `rsp_pop` 反馈到 AXI `RREADY`。
- 读 leaf、两客户端 read fabric 和双 lane write fabric 的 xsim 均重新通过；
  双 lane 场景保留 `req=16/AW=4/W=8/packed=8/errors=4/max_outstanding=2`。
- Artix-7 100 MHz proxy：两 leaf+read fabric 从 `32784 LUT/10078 FF/+0.214 ns`
  改善为 `31905/10075/+1.928 ns`；双 lane write fabric 从首版
  `4374/10091/-0.160 ns` 改善为 `4308/10091/+1.203 ns`。两者均为可选
  boardless seam，legacy portable-SoC top 未改接；response arrays 在该 proxy
  仍映射为 LUTRAM，Ti60/Efinity 需另做 EBR 对照。
- 修正写 leaf simulation-only W payload monitor 为 145 bit（128+16+1），并增加
  孤立 B 回归，避免误报和计数下溢。下一阶段应把真实 tensor/cache client
  接入 fabric，再评估同步 EBR、单 writer 多 descriptor/B FIFO 和并行 MAC
  scheduler；当前结果仍不是 native 640×480@15 fps signoff。

### 2026-08-27 AXI beat-record FIFO 与 inter-pixel MAC overlap

- `c1_tensor_mem_axi128_read_burst_client` 新增默认关闭的
  `RSP_FIFO_BEAT_MODE`。beat 模式每个 response slot 保存完整 AXI128 beat、
  lane 顺序和错误位，local 64-bit 接口用 `rsp_lane_q` 依次拆出一/两项；
  logical-entry 模式的顺序、错误和 early/missing `RLAST` 语义保持不变。
- 正常 beat-FIFO、early-RLAST/missing-RLAST malformed 回归均通过；默认
  logical 回归也重新通过。相同 `REQ16/BURST16/MAX4/RSP64` Artix proxy 中，
  logical 为 `12045 LUT/5378 FF/+1.046 ns`，beat 为
  `1714 LUT/1182 FF/+1.380 ns`。这主要减少双写、指针和 occupancy 逻辑，
  不减少 AXI payload；集成 wrapper 仍保持 mode=0，等待 Efinity EBR 对照。
- 新增 `c1_dot8x8_requant_pingpong`：两个完整 bank 轮转接受事务，tag FIFO
  恢复输出顺序，使下一像素可在前一像素 requant/retire 时启动。6 事务 xsim
  覆盖 `max_inflight=2` 和首个 overlap 提前 8 cycles；full-tree Artix proxy
  为 `31162 LUT/22833 FF/64 DSP/+1.938 ns`。这是事务级 seam，尚未接入真实
  22-stage scheduler、权重供数或 frame-level FIFO。
- 本阶段继续遵守 detached Vivado/xsim 约束：新增 runner 用 WMI worker、
  run-local runtime cache，结束时删除私有工程和 cache，仅保留小型 status、
  summary 与日志；没有把大仿真工程纳入工作区。

### 2026-08-27 beat FIFO 转发到 read fabric

- `c1_tensor_mem_axi128_read_fabric_2c` 新增 `LEAF_RSP_FIFO_BEAT_MODE`，并由
  `c1_window_line_cache_c8_burst_shell` 增加同名 leaf 参数转发；默认值均为
  0，因此现有 portable SoC 接线和逻辑响应 ABI 不变。
- 集成两客户端 beat 模式 xsim 通过：`req=16/ar=6/beats=8/packed=6/
  max_inflight=5`，跨客户端顺序和 fabric 错误标志保持正常。2-client proxy
  资源为 `2194 LUT/1630 FF/0 BRAM/0 DSP/WNS +1.815 ns`，同尺寸 logical
  proxy 为 `31905/10075/+1.928 ns`（beat leaf RSP16、logical leaf RSP64；
  集成对照包含 record-depth 缩减）。
- 该参数转发使 beat FIFO 可作为真实 tensor/cache client 的逐 leaf 试验开关；
  仍需在 Efinity 验证 EBR 推断、同步读延迟、满槽 bubble 和 native 长帧
  flush/abort，暂不修改默认 top。
- `c1_window_line_cache_c8_burst_shell` 的 beat-mode refill/tap xsim 也通过：
  `taps=6/refills=5/words=80/bursts=10/beats=40/max_outstanding=2`。cache
  仍只消费逻辑 64-bit 供数，因而该回归确认的是接口透明性，不是 EBR 资源或
  native frame-rate 结论。

### 2026-08-27 burst-level write MLP seam 与四-bank MAC A/B

- 新增 `c1_axi128_write_mlp`（`rtl/dma/c1_axi128_write_mlp.sv`）：每个 descriptor
  先收集固定宽度 AXI128 payload，再允许 AW 预排；W 按 descriptor 顺序发送，B
  以 descriptor response FIFO 有序返回。接口同时记录 early/late `TLAST`、flush、
  orphan payload/B 和下游 stall，因而可在板卡前验证 framing 与错误隔离。
- 专项 xsim `run_axi128_write_mlp_xsim_detached.ps1` PASS：
  `desc=6/aw=3/w=12/b=3/max_out=3/aw_stall=18/w_stall=5/b_stall=49/errors=4`。
  Artix-7 100 MHz proxy `run_axi128_write_mlp_proxy_synth_detached.ps1` PASS，
  `5882 LUT/10308 FF/0 BRAM/0 DSP/WNS +3.249 ns`（`MAX_OUTSTANDING=4`、
  `MAX_BEATS=16`）。该 backend 已由新的 logical write adapter 消费，但两者仍
  未接入七客户端 fabric 或默认 SoC，不能宣称单 writer 已完成真正整帧 MLP。
- 新增 `c1_tensor_mem_axi128_write_mlp_adapter`：小配置 `MAX_BEATS=4` 的 xsim
  通过 `desc=5/req=26/rsp=26/aw=4/beats=12/packed=13/errors=2/max_out=4`；
  `MAX_OUTSTANDING=4/MAX_BEATS=16` 的 Artix-7 proxy 为
  `15961 LUT/27771 FF/0 BRAM/0 DSP/WNS +2.551 ns`。该 seam 已闭合
  logical 64-bit→pack2→burst MLP→logical response，但 flush/abort/generation/
  ownership 及 payload 的 Ti60 EBR 映射仍待集成验证。
- 新增可选 `c1_tensor_mem_axi128_write_mlp_fabric_2c`，把上述 adapter 作为
  client-0 与 raw AXI128 peer 接入 ID-less write arbiter；用于验证共享总线的
  AW ahead、W/B 有序和跨 client 背压，xsim `aw=4/w=7/b=4/adapter_rsp=8/
  peer_b=2/max_inflight=4/packed=4`，Artix proxy `16291 LUT/28296 FF/0 BRAM/
  0 DSP/WNS +2.197 ns`，仍不改默认 top。
- `c1_tensor_mem_axi128_write_parallel_fabric` 追加四 lane A/B（四个单
  outstanding leaf、block 轮转、全局 tag FIFO 保序）。
  `run_tensor_mem_axi128_write_parallel_fabric_lanes4_xsim_detached.ps1` PASS：
  `req=32/aw=8/beats=16/packed=16/errors=4/max_outstanding=4`；对应
  `run_tensor_mem_axi128_write_parallel_fabric_lanes4_proxy_synth_detached.ps1`
  为 `9858 LUT/20168 FF/0 BRAM/0 DSP/WNS +2.166 ns`。该配置用于测量横向
  并行度上限，不等于单 writer AXI-ID/乱序 B，默认 SoC 仍未接入。
- `c1_dot8x8_requant_pingpong` 增加可选 `BANKS=4` 回归和 proxy。四-bank×双
  lane 的 12 事务 xsim PASS：`max_inflight=4/first_overlap=8/cycles=47`；
  full-tree Artix proxy 为 `59912 LUT/45674 FF/128 DSP/WNS +0.337 ns`。
  这只是二-bank (`31162 LUT/22833 FF/64 DSP/+1.938 ns`) 的并行度 A/B，尚未
  替换真实 22-stage scheduler、权重预取或 egress FIFO；四-bank 配置暂不作为
  默认 top。
- `c1_r1_microstyle_engine` 新增两个默认关闭的板前开关：
  `CACHE_DW_WEIGHT_TILES` 将每个 DW output group 的 9 拍权重搬到 tile RAM，
  `MAC_PREFETCH_OVERLAP` 则在 Conv/1x1 输入握手时捕获下一 tile，使稳态
  prefetch/feed 从 II=2 变为 II=1。22-stage engine xsim 均保持 bit-exact：
  baseline/cache/overlap/cache+overlap 的小测试首轮 cycles 为
  `30570/28553/29192/27174`；native 模型相应为
  `39571200/30048184/31238400/21715384`。tap-bank×64-bit cache 与 MAC
  overlap 联合 full-top proxy 为 `36413 LUT/14889 FF/2 BRAM/35 DSP/WNS
  -4.959 ns`，资源较旧宽数组实现下降但 timing 仍未闭合；因此当前只保留
  实验开关，必须先做 Ti60 EBR/同步读对照和 Efinity timing。
- 以上 runner 均通过 WMI detached worker 执行，并在结束时删除私有 Vivado/xsim
  工程；工作区只保留小型 status、日志、报告和 JSON。下一步是把 adapter/fabric
  seam 接到真实 tensor client，补 generation/flush/abort drain/ownership 门控，
  再做 EBR 映射和 native 长帧 outstanding/QoS 测量。

### 2026-08-27 吞吐阶段补充：长 burst、响应边界与缓存压力

- 读 burst client 的 `-LongBurst` detached profile（`BURST_BEATS=16`,
  `MAX_OUTSTANDING=4`）通过：`req=19/ar=6/beats=10/packed=7`。新增独立
  `run_tensor_mem_axi128_read_burst_profile_xsim_detached.ps1` 做 16/32-beat
  A/B：同一 189-request stream 均为 `beats=94/packed=94/max_outstanding=3/
  page_split=1/cycles=397`，AR descriptor 为 `9→7`。profile 还覆盖同 lane
  duplicate、misaligned local error、AXI INCR 属性和 4-KiB no-crossing；仅
  32-beat 参数实验，不改 default top。cache shell 也完成同参数长行压力回归：
  `taps=6/refills=5/words=640/bursts=20/beats=320/max_outstanding=4/
  cycles=1883`。默认小 smoke 仍为 `BURST_BEATS=4/MAX_OUTSTANDING=3`。
- 写 MLP 的 response FIFO pop/refill 已沿 leaf→logical adapter→2-client
  fabric 转发并完成 A/B 编译/回归。leaf：默认/可选 `B stall=49/48`，adapter
  可选 `full_pop_push=1` 且 `desc=5/req=26/rsp=26/aw=4/beats=12/packed=13`；
  fabric 可选 marker 的 `full_pop_push=0` 是其两 descriptor BFM 的激励限制。
  该开关仍默认关闭，因其把 `rsp_ready` 引入 BREADY 组合路径。
- `EMPTY_AW_BYPASS` A/B 只把首个 AW latency 从 1 cycle 降到 0，steady-state
  AW/W/B 与 outstanding 计数完全相同；同样默认关闭，等待目标器件时序确认。
- 缓存 shell TB 新增 `C1_CACHE_LONG_BURST_TB`，通过参数 profile 验证了
  长 burst 与多 descriptor 并发；这不是行预取实现。当前 cache 仍按 row miss
  串行 refill，后续若要继续逼近 15 fps，应先在真实 tap scheduler 中证明
  下一行请求可安全提前，再引入预取队列。
- 新增 `model/write_rsp_pop_refill_model.py` 及测试，模型 marker 为
  `baseline_stalls=6/refill_stalls=5`；它和读侧 pop/refill 模型都只量化 FIFO
  调度，不构成 DDR/fps 证据。

### 2026-08-27 吞吐阶段：读 AR 直通与 MAC 同拍重启

- `c1_axi_n_read_burst_arbiter_128` 新增默认关闭的 `EMPTY_AR_BYPASS`。当
  pending/response ring 均为空时，首个被选 client 的 AR 可直达 downstream；
  downstream 未 ready 时由一-entry hold register 锁存，因而不依赖同步 EBR
  异步读且不改变 payload hold 或 ID-less R 路由。独立 xsim A/B：
  `first_ar_latency=1→0`、`hold_capture=0→1`，正常/畸形 beat
  `16/10`、`max_inflight=4` 和 early/missing 标志一致；two-client fabric
  可选编译也通过。
- `c1_dot8x8_requant_core` 新增默认关闭的 `ALLOW_OUTPUT_RESTART`，并沿
  bank/ping-pong 贯通。二 bank×二 lane full-tree detached xsim：默认
  `cycles=40/max_inflight=2/same_bank_restart=0`，可选
  `cycles=37/max_inflight=3/same_bank_restart=4`；组合 first-beat skid 后仍
  `cycles=37`。四 bank×二 lane 兼容 A/B 也由 `47→45` cycles、同 bank
  restart `0→1`，数据、metadata、顺序与 overflow 检查通过。独立模型
  `model/mac_output_restart_model.py` 输出 `22→20` cycles、4 次同拍重启。
- 同一参数化 Vivado proxy 的资源对照也已完成：default/optional 分别为
  `31165/31163 LUT、22833 FF、64 DSP、WNS +1.247/+1.247 ns`；早先
  `31162 LUT/+1.938 ns` 为不同源码/综合快照，仅保留作历史参考，不能解释成
  output-restart 的时序收益。
- 这两项都只减少边界 bubble：AR 直通不减少 AXI payload，MAC 同拍重启不复制
  DSP，也没有把共享 22-stage FSM 变成 stage-overlapped pipeline。新增
  `READ_AR_EMPTY_BYPASS_OPTIMIZATION.md`、`MAC_OUTPUT_RESTART_OPTIMIZATION.md`
  记录了确切 marker、风险和启用条件；默认 SoC 仍保持关闭。
- 当前建议的下一条主线仍是：将真实 tensor/cache client 接到已有 read/write
  fabric，先用 `MAX_OUTSTANDING=2` 做 Efinity EBR/QoS/abort 回归；只有确认供
 数持续、且二 bank output scheduler 不被反压后，才在局部打开同拍重启。小 TB
 的 3-cycle 改善不能直接换算为 native 640×480@15 fps。

### 2026-08-27 并行 MAC 满 TAG FIFO pop/push

- `c1_dot8x8_requant_pingpong.sv` 新增末尾参数 `ALLOW_TAG_POP_PUSH=0`。当
  `tag_count_q == TAG_FIFO_DEPTH` 且队首结果本周期 `out_fire` 时，显式打开
  该选项可让新的 `START` 写入待退休槽；原有 `{start_fire,out_fire}` 计数和
  指针更新保持不变。默认值关闭，兼容路径不变。
- `tb_c1_dot8x8_requant_pingpong.sv` 增加 `C1_PINGPONG_TAG_POP_PUSH_TB`，将
  FIFO 深度压到 bank 数并加入 signed-8 饱和期望。2-bank×2-lane A/B：基线
  `52 cycles/max_inflight=2/full_tag_pop_push=0`，组合
  `ALLOW_OUTPUT_RESTART+ALLOW_TAG_POP_PUSH` 为 `48 cycles/max_inflight=3/`
  `same_bank_restart=6/full_tag_pop_push=6`；4-bank×2-lane 为 `59→57 cycles`、
  `full_tag_pop_push=0→2`，数据、metadata、顺序和 overflow 均 PASS。
- 新增 `model/mac_tag_pop_push_model.py` 与测试，事件模型输出
  `35→31 cycles/saved=4/full_pop_push=6/max_tag=2`；已纳入 Python regression
 （命令数 21）。细节见 `MAC_TAG_POP_PUSH_OPTIMIZATION.md`，A/B 汇总写入
  `model/axi_burst_proxy_summary.json`。该 seam 只消除满 FIFO 窄气泡，不增加
  MAC/DSP，不能解释为 15 fps 或 Ti60/Efinity signoff。
- 同一 2-bank×2-lane、`ALLOW_OUTPUT_RESTART=1` 的 Artix-7 小 proxy 仅切换
  `ALLOW_TAG_POP_PUSH` 也通过：`31163/22833/64/+1.247 ns` →
  `31159/22833/64/+1.845 ns`（LUT/FF/DSP/WNS，TNS=0）。该 WNS 差异只记录
  为综合启发式观察，不作因果时序收益；run id 为
  `tagpop_proxy_base_20260827`、`tagpop_proxy_opt_20260827`，runRoot 已清理。

### 2026-08-27 吞吐阶段：写 request FIFO pop/refill

- `c1_tensor_mem_axi128_write_burst_client` 新增末尾 named parameter
  `ALLOW_REQ_POP_REFILL=0`。打开时仅在 request FIFO 满且 burst builder 消费
  head 的同一边界接受替换请求；`req_pop` 不依赖 `req_ready`，因而不引入组合环。
  同拍 push/pop 保持 occupancy，诊断计数器不会虚报 `DEPTH+1`。
- `c1_tensor_mem_axi128_write_parallel_fabric` 已将该参数透传到各 leaf；默认值
  保持关闭，legacy SoC 和 AXI mux 均未改变。
- 专用 detached xsim A/B（`REQ_DEPTH=4`）均通过：基线
  `full_to_accept=6/same_cycle=0`，可选 `5/1`，两者均
  `req=12/aw=12/beats=12/max_req=4`；原有默认 leaf 也保持
  `req=21/aw=10/beats=13/packed=7/errors=2`。Python 调度模型
  `WRITE_REQ_POP_REFILL_MODEL_PASS` 为 `baseline_stalls=10→9`。
- 该项只削减 producer ready 边界的一拍，不改变 AXI payload 或 outstanding；
  开启前仍需在 Ti60/Efinity 检查 request RAM（同步读）到 `req_ready` 的时序、
  VALID hold 以及 abort/flush 交互。细节见
  [`WRITE_REQ_POP_REFILL_OPTIMIZATION.md`](WRITE_REQ_POP_REFILL_OPTIMIZATION.md)。

### 2026-08-27 读 response FIFO 与 cache 组合收口

- cache burst shell 新增 `ALLOW_RSP_POP_REFILL` 的参数/runner 开关
  `-RspPopRefill`。长 burst、beat-record FIFO、tail flush、读 request
  pop/refill 和 response pop/refill 五项组合 xsim 通过：
  `640 words/20 bursts/320 beats/max_outstanding=4/tail_flush=5/cycles=1883`；
  默认配置和 legacy top 未改变。
- 该组合测试用于发现参数传播或 ready/valid 协议回归；真正的满 response
  FIFO 同拍释放槽由 read-leaf 专用 A/B 覆盖。由于 cache BFM 不承诺连续 DDR
  服务，不能从组合周期声称吞吐提升。默认仍关闭，待 EBR 映射、RREADY 路径、
  QoS 和真实长帧 gate 后再启用。

### 2026-08-27 tensor client 接入审计与 native shape compile gate

- `c1_tensor_window_cache_axi_client` 当前仍把 adapter 的单个 64-bit
  `mem_req/mem_rsp` 接到 `c1_tensor_mem_axi128_bridge`；该 bridge 的 AXI
  `AR/AW LEN=0`，cache refill 也逐 word 等待响应。read burst shell 是只读、
  只服务 cache refill 的独立 seam，write MLP 则需要 descriptor/payload/last
  合同，不能直接替换 client-6。generation、统一 epoch、flush/abort drain、
  ID-less owner/retirement 约束已整理到
  [`TENSOR_CLIENT_INTEGRATION_AUDIT.md`](TENSOR_CLIENT_INTEGRATION_AUDIT.md)。
- 因而本阶段不改默认 SoC 接线、不打开 burst/MLP 参数；下一步应先做
  `read-only cache refill → direct-bypass mux → read/write epoch scheduler`
  三步门控，每步用小帧和负向 drain/ordering 回归验收。
- native `640×480` compile-only detached gate 已通过：runner 使用私有
  `xvlog -f` 源文件清单，规避长命令行造成的假性 access-denied；worker 在
  success/failure 两条路径都删除私有 runRoot，只保留 status 与小日志。该
  gate 仅代表 xvlog/xelab 可完成，不代表 native CNN、DDR QoS 或 15 fps。

### 2026-08-27 最大行 cache burst32 门控

- `run_window_line_cache_c8_burst_shell_xsim_detached.ps1 -MaxRow` 新增
  `C1_CACHE_MAXROW_TB`：`W=640/H=1/G=2`、`MAX_ROW_WORDS=1280`、
  `BURST_BEATS=32`、`MAX_OUTSTANDING=4`、BFM descriptor queue=16。
- detached xsim 通过：
  `taps=8/refills=1/words=1280/bursts=20/beats=640/packed=640/`
  `ar=20/ar_beats=640/page_splits=2/max_outstanding=4/cycles=1636`。
  bounded-log 复核 run 为 `maxrow_burst32_compact_20260827`。
  该测试还检查跨页后的 AR 连续性和两条 packed lane，不会把一个通过的
  descriptor 计数误认为 payload 完整。
- 该结果只证明最大行的 RTL 几何、排序和 4-KiB 边界；BFM 周期不是 DDR
  服务时间，默认 SoC 仍未切换到 32-beat 或多 outstanding。私有 runRoot 已
  自动清除，仅保留小型 status/日志。

### 2026-08-27 只读 cache-refill scheduler seam

- 新增 `rtl/dma/c1_cache_refill_scheduler.sv` 与
  `CACHE_REFILL_SCHEDULER.md`。该 seam 接受带 base/stride/row/word_count/
  epoch 的命令 FIFO，仅运行一个 active row；注册 pending request 保证
  abort/flush 边沿不会撤回 stalled `leaf_req_valid`。
- `MAX_OUTSTANDING` 元数据 FIFO提供 credit、按序响应 epoch/row/index/last
  sideband；`leaf_req_flush` 等待 leaf request occupancy 清零，完成 fence
  还要求 `leaf_quiescent`。旧 epoch 和无 metadata orphan response 均被
  消费并计数，epoch 到全 1 时饱和并停止 admission。
- 紧凑 detached xsim 通过：
  `C1_CACHE_REFILL_SCHEDULER_PASS cmd_accept=3 req=4 rsp=5 words=3 /
  stale_drop=1 orphan=1 max_outstanding=2 epoch=2 abort_done=1 flush_done=1`。
  默认 SoC 未接线；这是协议/排序 gate，不是 15-fps signoff。

### 2026-08-27 scheduler fence/drain 与 AXI128 read leaf composition

- scheduler 的维护边沿现在采用 deferred fence：若 current-epoch word 在
  `word_ready=0` 时已呈现，先保持该 word，握手后的下一拍才启动 fence；
  这样不会撤回 VALID，也不会让下一条旧响应误进 normal word stream。新增
  `EMIT_DRAIN_WORDS=1` 时，已接受的 stale response 通过独立
  `drain_word_*` 流排水，drain sink 的反压会传回 leaf，且 normal/drain
  两流互斥。
- 新增 `rtl/dma/c1_cache_refill_scheduler_read_client.sv`，把 scheduler 与
  `c1_tensor_mem_axi128_read_burst_client` 封装成可复用 boardless seam。
  `SCHED_MAX_OUTSTANDING=16` 是 logical-word metadata credit，
  `READER_MAX_OUTSTANDING=4` 是 AXI burst descriptor credit，二者不再强绑；
  `leaf_req_occupancy`、`leaf_quiescent`、`leaf_req_flush→req_flush` 的连接
  已固定并透明导出 reader 诊断计数器。
- 最新 detached xsim 小回归均通过：
  `C1_CACHE_REFILL_SCHEDULER_PASS ... epoch=2`；
  `C1_CACHE_REFILL_SCHEDULER_FENCE_STALL_PASS req=2 rsp=2 words=2 flush_done=2 epoch=2 cycles=31`；
  `C1_CACHE_REFILL_SCHEDULER_DRAIN_PASS req=2 rsp=2 drain=2 stale=2 max_outstanding=2 epoch=1 flush=1 cycles=23`；
  `C1_CACHE_REFILL_SCHEDULER_READ_CLIENT_PASS commands=2 words=25 req=25 rsp=25 ar=13 axi_beats=13 max_outstanding=2 flush=1 cycles=156`；
  `C1_CACHE_REFILL_SCHEDULER_READ_CLIENT_WRAPPER_PASS words=3 bursts=1 beats=2 cycles=18`。
- 裸 scheduler 最新 Artix-7 proxy（`xc7a200tsbg484-1`、100 MHz、
  `CMD_FIFO_DEPTH=8/MAX_OUTSTANDING=4/EPOCH_W=4`）为 839 LUT、1647 FF、
  0 BRAM tile、0 DSP、WNS +1.274 ns、TNS 0。该数字包含可选 drain 端口，
  只用于控制面边界估算，不是 Ti60/Efinity 或 native 15 fps 签核。
- drain 只覆盖已经 handshake 进入 leaf 的请求；line-cache 仍要求完整的
  declared word count，因此未发出的 suffix 需要后续的 cancellation-token/
  completion adapter（或修改 line-cache ABI）；该 adapter 已在本轮独立
  实现并验证，但还没有接入默认 SoC。当前默认 SoC、legacy client-6 和所有
  吞吐选项保持不变，尚未宣称端到端性能收益。

### 2026-08-27 exact-count completion adapter 与组合收口

- 新增 `rtl/dma/c1_cache_refill_completion_adapter.sv`。它把 scheduler 的
  normal/drain 两流合成 line-cache 可消费的单流；在 `abort_done`/
  `flush_done` 或 `cmd_done_error` 先于 declared count 到达时，补发
  zero/error suffix，保证 `refill_word_last` 仍落在声明的最终 index。
- 修复了一个实际的 late-token 竞态：最后一个正常词可能早于 scheduler
  `cmd_done` 数拍到达。适配器现在只有在 exact-count 完成且观察到
  `cmd_done`/`abort_done`/`flush_done` 后才清 `active`、产生 `refill_done`
  和重新拉高 `cmd_ready`；terminal token 也会置协议/错误诊断。集成时不能
  将这些 token 留空或绑 0。该 correctness-first 策略会引入行间收口气泡。
- 新增 `rtl/dma/c1_cache_refill_scheduler_read_client_exact.sv`，将上述
  adapter 固定接入 `scheduler_read_client`（强制 `EMIT_DRAIN_WORDS=1`），
  并导出统一 refill、raw scheduler 和 AXI128 reader 诊断端口。
- 新增/通过 detached xsim：

  ```text
  C1_CACHE_REFILL_COMPLETION_ADAPTER_PASS words=5 drained=2 synthetic=3 req=2 rsp=2 flush=1 cycles=23
  C1_CACHE_REFILL_COMPLETION_ADAPTER_NORMAL_PASS normal=5 synthetic=2 done=4 error_done=2 req=5 rsp=5 cycles=46
  C1_CACHE_REFILL_SCHEDULER_READ_CLIENT_EXACT_PASS words=5 drained=2 synthetic=3 req=2 rsp=2 ar=1 beats=1 flush=1 cycles=25
  ```

  normal gate 在第一行最终词后立即保持第二个 command，验证旧 `cmd_done`
  不会污染下一行；同时覆盖 zero-length reject 与 epoch-mismatch poison。
- 当前 exact composition 的 Artix-7 wrapper-only proxy（100 MHz、
  `SCHED_MAX_OUTSTANDING=16`、reader 4 bursts、32-entry req FIFO、16-beat）
  为 `35435 LUT / 11743 FF / 0 BRAM / 0 DSP / WNS +0.799 ns / TNS 0`；裸
  scheduler 在最新 RTL 为 `839 LUT / 1647 FF / WNS +1.274 ns`，读 leaf
  wrapper 为 `35202 LUT / 11683 FF / WNS +0.799 ns`。这些数字只做结构
  边界参考，不是 Ti60/Efinity 或整网 15-fps 签核。
- `word_count=0` 只生成错误 completion，不生成 refill word；line-cache
  接线必须保证 `word_count>=1`。synthetic suffix 是 poison，不可作为真实
  tensor 数据提交。默认 SoC、legacy client-6、读写 mux 和吞吐开关均未改动。

### 2026-08-28 真实 line-cache exact shell 接线 gate

- 新增 `rtl/dma/c1_window_line_cache_c8_exact_burst_shell.sv`，将
  `c1_window_line_cache_c8` 的 `{refill_req_row, refill_req_word_count}`
  请求接到 `c1_cache_refill_scheduler_read_client_exact`。`stage_base_addr`
  在同一个 `group_start` handshake 捕获；`row_stride_bytes` 由
  `frame_width * frame_groups * 8` 的显式 shift/add 计算。command holding
  register 将 `base=stage_base+row*row_stride`、`stride=8`、row/count/epoch
  一并锁存，避免维护边沿改变 stalled command 的 epoch。
- exact stream 与 cache 之间加入默认深度 2 的 `REFILL_SKID_DEPTH` 注册 FIFO；
  输入 ready 仅依赖 occupancy，并保留 data/error/last/row/index/epoch，切断
  原先 cache→adapter→scheduler→AXI RREADY 的组合路径，但增加至多两词缓冲
  和固定行间延迟。
- abort/flush 同时扇出到 cache 与 exact reader；壳内用两路 done join 保留
  先到的 pulse，只有 cache 与 scheduler/reader 都完成排水才向外报告
  `abort_done/flush_done`。`group_start_ready` 在 stage base 缺失、旧读侧未
  quiesce 或 command/fence pending 时保持低，防止跨 epoch 覆盖几何。
- 真实 line-cache 接口只接受 exact 单流的 valid/data/error/last；row/index/
  epoch 在 completion adapter 内校验。取消行的 accepted prefix 由 drain
  stream 消费，未发 suffix 由 zero/error synthetic words 补齐；cache 看到
  error 后丢弃行并让挂起 tap 重试。`word_count>=1` 仍是接线前提。
- detached xsim 端到端 gate 通过（run id
  `line_cache_exact_counter_v2_20260828`）：

  ```text
  C1_WINDOW_LINE_CACHE_C8_EXACT_BURST_SHELL_PASS responses=4 refills=3 words=24 ar=5 beats=10 flush=1 epoch=1 cancel_req=3 cancel_source=3 cancel_drain=3 cancel_synthetic=5 cancel_unified=8 cycles=143
  ```

  取消的 8-word 行明确观察到 3 个 accepted logical request/3 个 drain
  words/5 个 synthetic words，统一 refill 仍为 8 个 handshake；正常行和
  flush 后新 epoch 行均返回正确的 base/row 地址数据。TB 在 flush edge 后
  下一拍恢复 AR 服务，说明板级 QoS 必须最终服务已接受的 AR/R 请求；若
  长期封锁 AR，ID-less reader 的排水会按协议反压并等待 `leaf_quiescent`。
- 该 gate 只覆盖 wrapper/协议/地址映射，不是 Ti60/Efinity 资源或 native
  15-fps signoff。包含真实 line-cache 的 Artix-7 proxy 在注册 FIFO 版本
  （run id `exact_cache_shell_proxy_skid2_v2_20260828`，
  `REFILL_SKID_DEPTH=2`）为 `35639 LUT / 11930 FF / 7.5 BRAM tile /
  0 DSP / WNS +0.302 ns / TNS 0`，已通过 100 MHz proxy timing；未插 FIFO
  的对照为 `35543 LUT / 11923 FF / WNS -1.622 ns / TNS -97.709 ns`。
  这表明注册 FIFO 确实切断了长反压路径，代价约 96 LUT、7 FF 和最多两词
  缓冲。Vivado 仍提示 7 个 data_mem BRAM 未合并可选输出寄存器；exact-only
  的 35,435 LUT / +0.799 ns proxy 不包含 line-cache。默认 SoC、读写
  owner+epoch mux 和 legacy client-6 仍未接线。

### 2026-08-28 共享 read/write owner+epoch fence 与真实 arbiter status seam

- `rtl/dma/c1_axi_n_serial_arbiter_128.sv` 只新增观测输出：
  `read_busy/read_quiescent/write_busy/write_quiescent` 以及当前
  `read_owner/write_owner`。这些端口由既有状态机/owner 寄存器组合导出，
  不改变原有 round-robin、事务锁定、VALID 保持或 R/B 路由行为，因此现有
  named instantiation 不需要修改。
- `rtl/dma/c1_axi_shared_owner_epoch_fence.sv` 是独立的控制面 authority，
  不承载 AXI payload。`read_admit/write_admit` 在 abort/flush 边沿同周期关闭
  新 owner；若 arbiter 已经锁住一个 stalled AR/AW，则由
  `read_busy/write_busy + *_owner` 保留该 owner，允许其完成终止 R/B，再等待
  两个方向同时 `quiescent && !busy`。只有排空后才发出 `abort_done`/
  `flush_done` 并递增一次 `current_epoch`；abort 清除 context，flush 保留
  context。
- focused detached xsim 已通过：

  ```text
  C1_AXI_SHARED_OWNER_EPOCH_FENCE_ARBITER_PASS ar=1 r=1 aw=1 b=1 epoch=2 cycles=23
  ```

  该回归特意让读/写 owner 在维护边沿处于停顿，验证新 owner 被挡住而当前
  owner 继续排空，并检查 fence 的 epoch、完成脉冲和 sticky protocol-error
  合同。它是共享边界/协议证据，不是 native 长帧 QoS 或 15 fps 证明。
- owner/epoch fence 的 Artix-7 100 MHz proxy（run
  `owner_epoch_fence_proxy_v1`）为 `24 LUT / 206 FF / 0 BRAM / 0 DSP /`
  `WNS +5.948 ns / TNS 0`。arbiter 的六个 status 输出不增加独立状态存储；
  shell 还将 `read_admit/write_admit/read_fire/write_fire` 作为显式诊断端口
  导出，避免后续 SoC 依赖层次探针；
  真正接入 owner/QoS mux 后的组合路径、仲裁器总资源和 Ti60/Efinity 映射仍
  必须重新综合。
- 在上述控制 seam 之上新增了可选的
  `rtl/dma/c1_axi_shared_owner_epoch_arbiter_128.sv` integration shell。它在
  RTL 内执行 `raw_valid && (admit || selected_busy_owner)` 的地址/数据 gate，
  并把下游 AR/AW handshake 作为 fence 的 `read_fire/write_fire` 观测；真实
  arbiter 的 R/B/READY 路径不被复制或改写。独立 2-client focused xsim 已通过：

  ```text
  C1_AXI_SHARED_OWNER_EPOCH_ARBITER_PASS ar=1 r=1 aw=1 b=1 epoch=2 cycles=23
  ```

  同一 shell 的 detached Artix-7 proxy 资源为：2 clients、无 read skid 时
  `434 LUT / 233 FF / 0 BRAM / 0 DSP / WNS +5.769 ns`；按默认 7-client
  fabric、`READ_RESPONSE_SKID=1` 综合为 `1411 LUT / 407 FF / 0 BRAM /
  0 DSP / WNS +2.144 ns / TNS 0`。这两组数字只覆盖 shell+serial arbiter+
  fence 控制/AXI mux，不包含 DDR、CNN、line-cache 或 SoC；7-client 结果才是
  资源预算参考，仍需 Ti60/Efinity 映射复核。
- 当前默认 `c1_r1_portable_soc`、client-6、shared read/write payload mux
  仍保持原接线；本 shell 尚未替换默认路径、也未打开任何吞吐选项，不能把
  该 focused marker
  解读为系统性能签核。下一步才是把 admission/epoch 端口接入真实 fabric，
  再以 native 长帧回归验证 QoS、display underflow、abort/drain 和 deadline。

### 2026-08-28：生产 RTL QoS 观测边界与 native 长帧统计

为把上述诊断从 bind-only testbench 提升为可复用的 RTL 边界，新增
[`rtl/dma/c1_axi_shared_qos_monitor.sv`](rtl/dma/c1_axi_shared_qos_monitor.sv)。
它只采样真实七客户端 `VALID/READY`、serial arbiter 的
`busy/quiescent/owner`、display underflow 和帧边界，不驱动任何 AXI payload、
owner select 或 READY。`csr_clear_stats_pulse` 可同步清零；per-client 向量继续
保留在顶层层次内，选定 aggregate 已通过 APB `0x108..0x12c` 提供软件只读
live read window（非冻结快照）。
monitor 关闭时该窗口确定性返回 0，便于固件探测。

为避免诊断逻辑反过来制造新的时序瓶颈，per-client/run/max 计数采用 24 bit
饱和计数（100 MHz 连续等待约 167 ms），owner max 改为一个标量最大值加
owner ID，并把同周期协议异常合并为一个事件。Artix-7 100 MHz 代理综合结果为
`2268 LUT / 4000 FF / 0 BRAM / 0 DSP / WNS +1.465 ns / TNS 0`；这是监视器
本身的增量参考，不应与完整 SoC 直接相加。独立 xsim marker 为：

```text
C1_AXI_SHARED_QOS_MONITOR_PASS aw0_wait=3 ar1_wait=2 b0_stall=2 r1_stall=4 read_hold=4 write_hold=3 underflow=1 deadline_miss=1
```

顶层 cache-wiring smoke 已用 `ENABLE_SHARED_QOS_MONITOR=1` 重新通过，且默认
参数仍为 0。native 8×8 DDR BFM（无旧 bind monitor，`native_qos_8x8_tagged_twoframe_v7`）
也通过真实端到端统计：

```text
C1_R1_PORTABLE_SOC_SHARED_QOS_STATS frame_count=2 last_frame_cycles=3446518 deadline_miss=2 underflow=2 read_busy=5358372 write_busy=12955 r4_stall=5338987 r5_stall=2205 ar4_wait=2365 ar5_wait=5339177 protocol=0 overflow=0 event_start=2 event_prefetch_done=3 event_new_done=2 event_swap=2
```

帧窗口从 accepted boardless start 到
`display_prefetch_new_done_event`；raw `display_prefetch_done` 还会统计
current-pair 后台刷新，不能作为跨帧 terminal。此前用 `control_done_event` 只得到
约 65,811 周期，会掩盖约 1.95 M 周期的 ID-less R hold。两帧回归的功能 marker
为 `C1_R1_PORTABLE_SOC_CACHE_DDR_BFM_TWO_FRAME_PASS`，并额外验证
`C1_QOS_APB_READBACK pass=1`（APB 多寄存器读期间 live busy/owner 计数允许继续
增加）；deadline/underflow 是当前默认 serial/display
路径的真实 QoS 风险证据，不是功能回归失败，也不是 640×480/15 fps 结论。
`display_swap_event` 是独立的 VSYNC ownership commit，当前可早于 tagged done。
`ENABLE_SHARED_QOS_MONITOR` 默认关闭，owner/epoch payload mux 仍未替换 default
SoC；下一步是在 response-FIFO/owner-fence 候选路径上重复同一 native 统计。

同一 tagged two-frame BFM 打开 `C1_DISPLAY_RESPONSE_FIFO` 的 A/B
(`native_qos_fifo_tagged_twoframe_v1`) 已通过：display client-4/5 的
`r4/r5` stall 为 `27/27`、`ar4/ar5` wait 为 `194/234`，相对 bypass 的约
5.34 M-cycle HOL 显著下降；但 `last_frame_cycles=3446518`、deadline/underflow
仍为 `2/2`。这证明 FIFO 是 response 隔离修复而非端到端吞吐修复，下一优化
目标转到 client-6 tensor/compute-start 与共享调度。

随后在同一 tagged 端点上完成 64×48 两帧 FIFO 回归
(`native_qos_fifo_tagged_64x48_twoframe_v2`)：`done=2/swaps=2/drops=0`，
`frame_count=2/active=0`，`last_frame_cycles=5086618`，
`read_busy=626599/write_busy=623169`，`r4/r5 stall=4305/3499`，
`ar4/ar5 wait=941/1005`，`protocol=0/overflow=0`，APB readback 通过。
首轮 v1 的 5 M-cycle 超时只是固定观察窗口不足；按形状提升到 20 M 后第二个
tagged terminal 在约 90.48 ms 到达。该动态回归将 SoC 图像缩到 64×48，但显示
compositor 仍使用固定 720p/640×480 请求窗，因此 `underflow=3` 是尺度映射
诊断，不应与 native 640×480 画面质量混用；native display-only FIFO 预检为
`underflow=0/0`。测试台等待上限的调整不改变 DUT，也不是帧率优化。

### 2026-08-28：client-6 可选 burst/refill 维护闭环

在不改变默认 `ENABLE_TENSOR_BURST_REFILL=0` 路径的前提下，新增
`rtl/dma/c1_tensor_window_cache_burst_axi_client.sv`，将 cacheable 3×3
读的三行 C8 refill 接到 exact-count/AXI128 burst reader；写、普通读和
fallback 仍走历史 one-beat bridge。此次增量完成了：

- pending tap 在 abort/flush 期间的 `ready/valid` 门控和 owner 保持；
- exact shell 在 `REFILL_REQ` 尚未完成 command handshake 时的 command capture；
- flush-before-AR 与 abort-before-AR 的对称 directed test；
- `CANCEL_IS_PROTOCOL_ERROR` 从 exact reader 透传到 shell/client/top 的显式
  取消策略参数。

最新 standalone xsim marker：

```text
C1_TENSOR_CACHE_BURST_AXI_CLIENT_PASS burst_ar=4 single_ar=5 beats=13 aw/w/b=2/2/2 flush_done=2 abort_done=3 ar_stall=3 r_stall=0 r_gap=21 aw_stall=1 w_stall=2 cycles=265
```

64×48 的 `SharedQosMonitor + TensorBurstRefill + DisplayResponseFifo`
compile/elaboration 也通过；此前同条件两帧 full BFM 的 client-6 统计为
`AR/R=59664/76800`，legacy 为 `96384/96384`，但端到端
`last_frame_cycles=5086618` 没有下降。故该 seam 目前是板前协议/带宽候选，
不是 15 fps 签核；共享 fabric 仍为 ID-less serial owner，尚未形成真正的
跨 logical request MLP。

同一 optional 参数组合的 640×480 compile-only gate 也通过
`C1_R1_PORTABLE_SOC_SHAPE_ELAB_PASS frame=640x480`；这只确认 native 几何
展开，不代表长帧动态、Efinity 资源/时序或 15 fps。

具体参数、资源判断、验证证据和板卡后 bring-up 顺序见
[`TENSOR_CLIENT_BURST_REFILL_INTEGRATION.md`](TENSOR_CLIENT_BURST_REFILL_INTEGRATION.md)。

### 2026-08-28：full-top tensor burst logical/beat 与 native beat 验证

logical-entry full-top proxy 的最终 v4 结果为综合完成但 timing failed
（`portable_soc_tensor_burst_logical_v4`，`80791 LUT/39369 FF/32 BRAM/100 DSP`，
WNS `-52.20 ns`；此前 v3 的 `+14.92 ns` 解析值已废弃）。beat-record proxy
`portable_soc_tensor_burst_beat_v1` 综合 marker PASS（`48411 LUT/30950 FF/32 BRAM/100 DSP`），
但 WNS `-52.55 ns`，当前实现状态为“功能路径已综合、时序未闭合”。在 native
BFM 中，`tensor_burst_beat_8x8_twoframe_v1` 和
`tensor_burst_beat_64x48_twoframe_v1` 均通过 `done=2/swaps=2/drops=0`、
`descriptors=44`、`display_done=1`；对应 `AR/R=1451/2970` 和 `60165/84187`。
该结果确认 beat-record 选项的 shape-scaled 生命周期与 drain 合同，尚未改变
默认 `ENABLE_TENSOR_BURST_REFILL=0`，也不构成 native 实时性能签核。

### 2026-08-28：REGISTER_ABORT_RESET A/B

REGISTER_ABORT_RESET A/B 已完成 native 与 proxy 对照：native resize PASS，native
8×8/64×48 abortreg 均 PASS 且 `protocol=0`。proxy baseline 为
`48192 LUT/31227 FF/32 BRAM/88 DSP`、WNS/TNS `-5.900/-67577.578`；abortreg v2
为 `48211 LUT/31237 FF/32 BRAM/88 DSP`、WNS/TNS `-5.416/-66644.070`，
`timing_met=false`。当前剩余最差路径为 reset 相关的 descriptor decoder path。

### 2026-08-28：PIPELINED_DECODER_VALIDATION

PIPELINED_DECODER_VALIDATION 已在 engine→cnn_top→system_bridge→portable_soc
参数化，默认值为 0。MicroStyle engine xsim PASS marker 为
`C1_R1_MICROSTYLE_ENGINE_PASS ... outputs=836 ... first_run_cycles=30570`。
完整 8×8 两帧组合（burst+beat+address+adapter descriptor pipeline+narrow+abort
reset+QoS+display FIFO+decoder pipeline）PASS：`done=2/swaps=2/drops=0`、
`protocol=0`、`last_frame_cycles=3446518`、`r4/r5 stall=29/29`、
`ar4/ar5 wait=202/244`。

proxy `tensor_burst_beat_pipelined_split_addr_abortreg_decoderpipe_v1` 为
`47493 LUT/31441 FF/32 BRAM/88 DSP`、WNS/TNS `-5.362/-66042.227 ns`，
`timing_met=false`；abortreg v2 对比为 `48211/31237/-5.416/-66644.070`。
配置阶段每 descriptor 固定增加两拍，运行期协议不变，仍非 timing signoff。

### 2026-08-28：REGISTER_FATAL_TICKET 与 replicate 对照

full-top decoderpipe proxy 在 `REGISTER_FATAL_TICKET=1`、`REPLICATE=0` 下为
`47467 LUT/31471 FF/32 BRAM/88 DSP`，WNS/TNS `-4.601/-960.989`，
`timing_failed`；最差路径为 `dot_weight_tile_q_reg C→dot_core/g_dot[*]/acc_overflow_reg D`。
同配置 `REPLICATE_ABORT_CONTROL=1` 为 `47474 LUT/31502 FF/32 BRAM/88 DSP`，
WNS/TNS `-4.601/-969.458`，几乎无收益。native 8×8 two-frame ticket PASS：
`done=2/swaps=2/drops=0`、`protocol=0`、`last_frame_cycles=3446518`，client-6
`AW/W/B=1672/1672/1672`、`AR/R=1268/1600`。ticket 仅作为 timing candidate，
replicate 默认关闭，结果不构成 timing signoff。

### 2026-08-28：deep pixel-index 实验

新增 `PIPELINED_TENSOR_PIXEL_INDEX`，默认值为 0。standalone adapter PASS：
`requests=2230 reads=1810 writes=420 pipeline=1`；8×8 两帧 full BFM PASS：
`done=2/swaps=2/protocol=0`。

proxy `tensor_burst_beat_pipelined_deeppixel_abortreg_decoderpipe_v1` 为
`47522 LUT/31431 FF/32 BRAM/88 DSP`、WNS/TNS `-5.544/-66243.875`；相对
decoderpipe baseline `47493/31441/-5.362/-66042.227` 变差 `0.182 ns`，worst
path 转为 `camera FIFO→tensor_adapter/state_q CE`。该配置保留为可回退研究开关，
默认弃用，不再加深。

### 2026-08-28：dot-tree full A/B

推荐组合 functional 8×8 two-frame PASS：`done=2/swaps=2/drops=0/protocol=0`，
`AW/W/B=1704/1736/1704`、`AR/R=1451/2970`、`last_frame_cycles=3446518`。
full-top proxy `recommended_fatal_ticket_dotfull_v1`（Beat+PipelinedAddress+
descriptor pipeline+narrow+abort reset+decoder pipeline+REGISTER_FATAL_TICKET+
PIPELINED_DOT_TREE_FULL）为 `47392 LUT/34763 FF/32 BRAM/88 DSP`、WNS/TNS
`-3.450/-33.977 ns`；dotbase ticket 同组合为 `47464/31504/32/88`、
`-4.601/-969.458`。瓶颈由 dot weight→acc_overflow 转为 descriptor size narrow
return→`descriptor_input/output_size_result_q`（`-3.450`）。dotfull 为可选
timing candidate，默认 0，非 timing signoff。

### 2026-08-28：descriptor-size arithmetic / fixed-threshold A/B

descriptor size arithmetic v3 standalone PASS；完整 8×8 两帧 full BFM PASS，
marker 为 `done=2/swaps=2/drops=0/protocol=0`、`last=3446518`，AXI
`1704/1736/1704/1451/2970`（AW/W/B/AR/R），QoS `r4/r5=36/35`。

同批 proxy 对照：size0 为 `47399 LUT/34764 FF/32 BRAM/88 DSP`、WNS/TNS
`-2.907/-24.206`；size1 为 `47544 LUT/34819 FF/32 BRAM/87 DSP`、
`-2.363/-62.605`；fixed-threshold 为 `47512 LUT/34821 FF/32 BRAM/85 DSP`、
`-1.079/-20.120`。fixed 相对 size1 为 LUT `-32`、FF `+2`、DSP `-2`、WNS
`+1.284`、TNS `+42.485`，最差路径转为 `16x16 pixel_count`。该实验默认关闭，
Case1 固定 8MiB/22-stage 严格条件，仍非 timing signoff。

### 2026-08-28：pixel-count split

standalone 与完整 8×8 两帧 BFM 均 PASS；BFM AXI 为
`1704/1736/1704/1451/2970`（AW/W/B/AR/R），`last_frame_cycles=3446518`，
QoS `r4/r5=28/27`，配置标志为 `descriptor_size_arith=1 fixed=1 pixel=1`。
proxy 为 `47542 LUT/34818 FF/32 BRAM/83 DSP`、WNS/TNS `-1.217/-18.572`，
相对 fixed baseline WNS `-0.138 ns`；最差路径为 `cache height_q→adapter state CE`。
pixel-count split 默认关闭，仍非 timing signoff。

### 2026-08-28：iterative descriptor pixel-count shift-add

standalone PASS marker；BFM two-frame PASS：AXI
`1704/1736/1704/1451/2970`（AW/W/B/AR/R），`last_frame_cycles=3446518`，
`protocol=0`，QoS `r4/r5=27/27`。

iterative native-control proxy 为 `47611 LUT/34917 FF/32 BRAM/82 DSP`、WNS/TNS
`-1.206/-23.233`；同 runner fixed native control 为
`47512 LUT/34821 FF/32 BRAM/85 DSP`、`-1.079/-20.120`。迭代 WNS 为
`-0.127 ns`，资源相对 fixed 为 LUT `+99`/FF `+96`/DSP `-3`，瓶颈迁移为
`cache height_q→state CE`。两次旧 cache env failure 后最终使用 native runtime；
默认关闭，仍非 timing signoff。

### 2026-08-28：PRECLAMPED_TAP_COORDS 语义修正与功能 gate

`PRECLAMPED_TAP_COORDS` 已沿 adapter→legacy cache seam→burst exact shell→
portable SoC 完成参数化，默认值为 `0`。启用值 `1` 时，adapter 在已有 request-Q
边界复用 `tap_source_x/y_fn` 生成并寄存 Conv3x3/DWConv3x3 的物理钳位坐标；这
避免 cache 侧重复的 width/height 比较，同时不引入新的 ready→state 组合回路。
该开关只对合法 window descriptor 生效，仿真断言会拒绝越界或未配置请求。

`preclamped_registered_tap_8x8_twoframe_v1` 已通过 full BFM：
`done=2/swaps=2/drops=0/descriptors=44/stage_mask=1fffff/display_done=1`，
`drain_cycles=3464876`、`protocol=0`。它与 fixed baseline 的 AXI 计数严格相同
（`AW/W/B=1704/1736/1704`、`AR/R=1451/2970`，stall
`231/464/212/1879`），并通过 APB QoS readback（`pass=1 status=00000019`
、`frame=2`）。这建立了功能、ownership、背压和流量等价证据，但不等于像素
CRC、时序或 15 fps 签核。

早期 `preclamped_tap_8x8_twoframe_v1` 直接对 adapter 的 signed logical 坐标做
sign-only clamp；它虽然通过生命周期 marker，却产生 `AR/R=1463/3042`（client-6
`1280/1672`），已判定为坐标语义错误并拒绝。随后 native helper=all 修复了
full-top `common.tcl` runtime failure，并完成了有效的严格 A/B（详见文末）；该
结果仍是 xc7a proxy 的 `timing_failed`，不能当作 Ti60/Efinity timing signoff。

### 2026-08-28：native helper=all registered PRECLAMP full-top A/B

native helper=all 已修复此前 full-top Vivado `common.tcl` runtime failure，使两次
严格同条件 proxy 都真正进入 HDL 综合并产出完整资源/时序报告。A/B 仅切换
`PRECLAMPED_TAP_COORDS`（其余为 beat-record、`RSP_FIFO_DEPTH=64`、strict
descriptor、pipelined address/decoder/size arithmetic、fixed limits、dot-tree
full、narrow return、abort reset、fatal ticket 等相同配置），器件为
`xc7a200tsbg484-1`、frame `640×480`：

| run | PRECLAMP | LUT | FF | BRAM tile | DSP | WNS | TNS | 状态 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `baseline_helper_all_v1` | 0 | 47,512 | 34,821 | 32 | 85 | -1.079 ns | -20.120 ns | `timing_failed` |
| `preclamped_registered_helper_all_v1` | 1 | 47,443 | 34,784 | 32 | 81 | -1.079 ns | -15.868 ns | `timing_failed` |

registered preclamp 相对 baseline 的 delta 为 LUT `-69`、FF `-37`、BRAM `0`、
DSP `-4`、WNS `0.000 ns`、TNS `+4.252 ns`（违例总量减小但仍为负）。因此这
是一个真实的资源收缩/时序不恶化结果，同时也确认 WNS 尚未闭合；helper=all
解决的是 Vivado 运行环境，不应误写成 RTL 本身的时序修复。两组结果均只是
Xilinx Artix-7 proxy、未做 P&R，不能外推为 Ti60/Efinity 资源或 timing signoff；
`PRECLAMPED_TAP_COORDS` 仍保持默认关闭。

### 2026-08-28：默认回归保护与跨仿真器全 RTL smoke

本阶段修复了 portable-SoC BFM 对可选 `C1_SHARED_QOS_MONITOR` 层级的无条件
引用。关闭 monitor 的默认 xelab 现在不再解析不存在的层级，修复后的 8×8
单帧 detached xsim 重新通过（`done=1/swaps=1/drops=0/descriptors=22`，
`AW/W/B/AR/R=852/868/852/1119/2199`）。这是测试台健壮性修复，不是 DUT
时序或功能路径改动；旧的 monitor-off xelab 失败记录不应再当作 RTL 失败。

同时完成了一个受控的可选组合验证：8×8 两帧打开 display response FIFO、共享
QoS monitor、tensor burst beat-record 和 registered preclamp，得到
`done=2/swaps=2/drops=0/descriptors=44/protocol=0`，QoS APB 读回一致；但
`deadline_miss=2/underflow=2`，故仍不满足性能门。该结果只证明候选 seam 可
拼接和能安全收口，不能外推 native 长帧。

新增 `scripts/run_iverilog_rtl_compile.ps1` 与
`efinity/IVERILOG_RTL_COMPILE.md`。Icarus 14.0 (devel) 以固定 package 顺序
编译全 RTL，顶层 `c1_r1_portable_soc`，127 个源文件退出码 0、596 条兼容性
告警、0 错误；所有临时 response/VVP/诊断均在 `%TEMP%` 并自动删除。这为
Efinity 前的包依赖/语法回归提供了轻量入口，但 Icarus 不展开加密 Soft
Sapphire/DDR/MIPI/HDMI IP，也不替代 Vivado/xsim 或 Ti60 P&R。

同日 `scripts/run_python_regression.ps1` 的 21 个 Python/golden 命令也全部通过。
另有独立的 `artifact_probe_8x8_20260828c` detached xsim/Icarus 双仿真证据，已将
真实 trained artifact 的 engine+arena 小尺寸逐阶段 bit-exact 边界闭合：
`stages=22 records=896 outputs=836 cycles=28276`。这不等于完整系统闭合；
tensor adapter 地址/window/cache、portable SoC 共享 DDR、native 640×480 长帧、
时序和 15 fps 仍未完成。

同一日新增的 descriptor-size 数学护栏覆盖固定 8 MiB bank 的六种合法
bytes-per-group 阈值及越界边界，输出 `C1_DESCRIPTOR_SIZE_LIMITS_PASS
groups=6 boundary_checks=36`。这只是可选 fixed-limit RTL 分支的等价性检查；
当前 full-top 首违例仍为 `descriptor_pending_q→pixel_count`（WNS `-1.079 ns`），
因此不能把该护栏或 preclamp 资源收缩误写成时序已闭合。

随后新增的 `tb_c1_r1_microstyle_artifact_tensor_engine_8x8.sv` 将同一真实
descriptor/parameter arena 接入真实 tensor adapter 与 `c1_r1_microstyle_cnn_top`，
并用有界三 bank DDR BFM 将每一级 engine 结果写回、供下一级地址/window 调度读取。
adapter operand、engine output 和最终 64 个像素均逐拍比较；detached xsim 与
Icarus 同一 TB 均通过：

```text
C1_R1_MICROSTYLE_ARTIFACT_TENSOR_ENGINE_8X8_PASS stages=22 operands=896 results=836 final=64 cycles=46326 stage_done=22
```

这把 trained artifact→engine 的证据边界再推进到 adapter 地址/窗口/残差/写回
闭环，但仍只覆盖 8×8、单 outstanding 和独立 BFM；portable SoC 共享七客户端
DDR、native 640×480 长帧、burst/多 outstanding、QoS、时序和 15 fps 仍未闭合。

同日继续把真实工件接入现有 `c1_r1_portable_soc` 的 8×8 全生命周期 BFM（通过
`-TrainedArtifact`，默认回归不受影响）。该运行实际从 DDR BFM 读取训练参数
arena，而不是只替换 descriptor；参数加载器、共享七客户端 AXI、boardless
input/output DMA、tensor adapter、22-stage engine、display prefetch 和 ownership
drain 均完成：

```text
C1_R1_PORTABLE_SOC_TRAINED_ARTIFACT_8X8_PASS descriptors=22 weight_ar=66 axi_r=2199 done=1 stage_mask=1fffff
```

同一 run 的普通生命周期 marker 也通过（`done=1/swaps=1/drops=0/display_done=1`），
detached Vivado/xsim 总耗时约 51 s；xvlog/xelab/xsim stderr 无错误，临时 runRoot
已由 runner 删除。该证据只说明真实参数已经穿过 portable SoC 并完成 8×8 事务
闭环，不代表输入像素与 Python golden 逐像素相同，也不覆盖 native 640×480、
burst/多 outstanding、15 fps、Ti60 Efinity P&R 或板上 IP 调试。

为推进 native 边界，又修复并重跑了 `run_r1_microstyle_artifact_abi_xsim_detached.ps1`：
runner 现在在 WMI 被策略拒绝时使用 `CREATE_BREAKAWAY_FROM_JOB` fallback，将
native `descriptors.mem`/`parameter_arena.mem` 复制到私有 runRoot，结束后删除完整
Vivado/xsim 工程。`native_artifact_abi_breakaway_20260828b` 通过：

```text
C1_R1_MICROSTYLE_ARTIFACT_ABI_PASS stages=22 param_bytes=16896 param_words=1056 param_payload_bytes=16379 nonzero_words=1030 param_reads=1030 cache_writes=1030 boundary=RTL_DECODER_SCHEDULER_ARENA_ONLY_NATIVE_640x480
C1_R1_PARAMETER_SCHEDULER_DIRECTED_PASS negative=6 validate_aborts=1 captured_configs=1
```

这确认 native 640×480 工件的 22 个 descriptor、16,896 B arena、对齐/边界和
parameter scheduler 读写合同均可由当前 RTL 接收；仍未执行 native 数据平面 CNN
长帧，不能据此宣称 native 算术、QoS 或 15 fps 已完成。

同时新增无依赖的 `golden/test_native_artifact_abi.py` 静态护栏，对原始
`descriptors.bin`/`parameter_arena.bin`、RTL scheduler 的 region/地址/affine
约束及 `$readmemh` `.mem` 镜像做逐项检查。结果为
`C1_NATIVE_ARTIFACT_ABI_PASS`（22 descriptors、1408 B descriptor、16896 B
arena、16379 B payload、1030 个 128-bit words、926 个 affine 值）；这加强了
文件 ABI 证据，但边界仍是 descriptor/parameter，不替代 native CNN 长帧验证。
