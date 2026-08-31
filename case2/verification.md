# 赛题二 RTL/XSIM 回归记录

Vivado Simulator 按 `xvlog`、`xelab`、`xsim -runall` 分阶段执行，但分开命令或
新建进程本身不保证脱离 Windows Job。此前把“分阶段”直接等同于“未绑定 Job”的
表述不准确：本机实测普通 breakaway worker 仍返回 `worker_in_job=true`，检查逻辑
因此阻止了 Vivado 启动。

当前实际调用器为
[`scripts/Start-DetachedEdaTool.ps1`](scripts/Start-DetachedEdaTool.ps1)，它经 WMI
`Win32_Process` 服务隐藏创建 `run_detached_tool.py` 的 Python worker；worker
调用 Windows `IsProcessInJob`，只有确认 `worker_in_job=false` 才启动相应工具，
并将 PID、返回码、状态和日志持久化。不能仅靠 `DETACHED_PROCESS`、breakaway
标志或三个独立命令声称进程隔离成功。

## 1. 当前回归结果

2026-08-31 最终完整回归由
[`scripts/Run-NewguideRegression.ps1`](scripts/Run-NewguideRegression.ps1) 执行，
结果为 10 项自检仿真 + 11 项展开全部通过，目录为
`tb/xsim_newguide_signoff_20260831`。一次统一编译、11 次展开和10 次仿真共22个
状态 JSON 均为 `worker_in_job=false`、`state=completed`、`returncode=0`。
该轮覆盖最终 AW/W 独立时序及 odd-stride 修正；旧 `axi_final_xsim_wmi.log` 仅属于
此前 AXI 单元验证，不再代表最后版本。

脚本本轮执行 AXI-Lite、AXI64、AXI128、行读、行写兼容路径、读写 engine 集成、
stride 对齐、legacy command memory、system scanout、AXI system shell 共10项
仿真，另展开无行为的 IP stub。下表也保留未纳入这10项的既有模块专项记录，
本轮执行集合以脚本与上述目录的逐项日志为准。

| 测试 | 覆盖内容 | 最新结果 |
|---|---|---|
| `tb_renderer_pkg` | 256-bit 命令 pack/unpack | `TB_RENDERER_PKG_PASS` |
| `tb_c2_sync_fifo` | 入出队、满/空、同步背压 | `TB_C2_SYNC_FIFO_PASS` |
| `tb_c2_burst_planner` | 行拆 burst、4 KiB 边界、行/帧结束 | `TB_C2_BURST_PLANNER_PASS` |
| `tb_pixel_ops` | RGB565/RGB888 pack、Alpha、Color Key、流背压 | `TB_PIXEL_OPS_PASS` |
| `tb_c2_video` | 小栅格 timing、blanking/sync 和 page flip | `TB_C2_VIDEO_PASS` |
| `tb_c2_framebuffer_reader` | 扫描地址、stride、响应/输出背压和非法几何 | `TB_C2_FRAMEBUFFER_READER_PASS` |
| `tb_c2_mem_arbiter_2m` | legacy 双主仲裁、响应归属和背压 | `TB_C2_MEM_ARBITER_PASS` |
| `tb_c2_burst_read_stream` | 多 beat 读响应、`rsp_last` 和背压 | `TB_C2_BURST_READ_STREAM_PASS` |
| `tb_c2_line_fifo` | 块 RAM 前取结构、行尾标记、满/空、overflow、flush | `TB_C2_LINE_FIFO_PASS seen=4` |
| `tb_c2_line_fifo_corner` | occupancy=1 与 full 状态的 push+pop 同拍、指针回绕和前取气泡 | `TB_C2_LINE_FIFO_CORNER_PASS words=7` |
| `tb_c2_mem_arbiter_burst` | legacy 多 beat 读 owner 保持 | `TB_C2_MEM_ARBITER_BURST_PASS` |
| `tb_c2_rect_burst_reader` | 行 stride、planner→stream、坐标和行/帧尾 | `TB_C2_RECT_BURST_READER_PASS` |
| `tb_c2_burst_write_stream` | 独立写数据、背压、`last` 错误和零长度 | `TB_C2_BURST_WRITE_STREAM_PASS` |
| `tb_c2_mem_arbiter_owner` | descriptor→write data→延迟 `wr_rsp` owner 保持、竞争读和错误恢复 | `TB_C2_MEM_ARBITER_OWNER_PASS writes=6 reads=1 rsp=3 recovered=1` |
| `tb_render_cmd_mem_engine_burst` | 保留 legacy 单 beat 读，验证 Fill/Copy/Key/Alpha、行写 burst、4 KiB 分段、写背压和完成响应 | `TB_RENDER_CMD_MEM_ENGINE_BURST_PASS req=21 reads=8 writes=13 pixels=20 beats=20` |
| `tb_render_cmd_mem_engine_read_burst` | Copy/Color Key 行读，`MAX_READ_BEATS` 与 4 KiB 双重分段、读写背压、`rsp_last` 错误注入 | `TB_RENDER_CMD_MEM_ENGINE_READ_BURST_PASS reads=11 writes=8 pixels=26 errors=1`（1 个错误为主动注入） |
| `tb_c2_cmd_mem_engine_burst` | 读写行级 burst engine + owner arbiter + 行为内存集成，覆盖 Fill/Copy/Key/Alpha | `TB_C2_CMD_MEM_ENGINE_BURST_PASS req=18 reads=8 writes=10 wr_rsp=10 pixels=15` |
| `tb_c2_axi4lite_csr_adapter` | AW/W 任意顺序、读写仲裁、CSR/B/R 背压稳定、partial `WSTRB` 拒绝 | `TB_C2_AXI4LITE_CSR_ADAPTER_PASS csr=5 writes=3 reads=2` |
| `tb_c2_mem_to_axi4_adapter` | 16→64-bit 聚合/拆包、独立 AW/W 时序、背压、RID、提前/延后 RLAST、4 KiB 拒绝 | `TB_C2_MEM_TO_AXI4_ADAPTER_PASS width=64 aw=6 ar=14 r=25 protocol=5 axi=5` |
| `tb_c2_mem_to_axi4_adapter_128` | 与64-bit专项同样的边界测试，验证系统默认128-bit数据宽度 | `TB_C2_MEM_TO_AXI4_ADAPTER_PASS width=128 aw=6 ar=14 r=25 protocol=5 axi=5` |
| `tb_c2_stride_alignment` | parser与engine直连入口拒绝实际使用的奇数字节stride，合法例外和正常多行读写 | `TB_C2_STRIDE_ALIGNMENT_PASS parser_rejected=7 direct_rejected=7 allowed=6 requests=12 reads=4 writes=8 pixels=32 errors=7` |
| `tb_cmd_mem` | legacy FIFO→parser→单 beat engine→行为内存 | `tb_cmd_mem PASS: req=25 read=11 write=14 pixels=15` |
| `tb_c2_display_prefetch` | 首帧黑屏、vblank 预取、空帧不 arm、active PHY 背压报错 | `TB_C2_DISPLAY_PREFETCH_PASS pixels=8 errors=2`（2 个错误为测试主动注入） |
| `tb_c2_renderer_system` | CSR→renderer→共享内存→vblank page flip/prefetch→完整 page1 扫描 | `TB_C2_RENDERER_SYSTEM_PASS video=16 page1=8 done=1 active_page=1 underflow=0` |
| `tb_c2_renderer_system_axi_shell` | `USE_AXI4LITE_CSR=1`、`USE_EXT_MEM_IP=1` 的竞赛接口结构；经 AXI4-Lite 提交/读取 NOP | `TB_C2_RENDERER_SYSTEM_AXI_SHELL_PASS submit=1 done=1` |
| `tb_c2_renderer_system_ip_stub` | clock/video/page-CDC/memory-CDC 黑盒及外部 AXI memory 分支结构 | `xvlog/xelab PASS`；不运行无行为黑盒 xsim |

## 2. 新 owner/write-response 契约的验证范围

写 descriptor、写数据和完成响应是三个独立 handshake。`c2_mem_arbiter_2m_owner`
从 descriptor 被接受开始保持同一 owner，写完 `wr_last` 后仍不接收其他 master
事务，直到对应 `wr_rsp` 被原 master 接受。该响应是未来 AXI B 或外存控制器
commit/error 的抽象接口。

Owner 专项回归覆盖正常多 beat 写、竞争 read、延迟 write response、错误写后的
owner 释放与下一事务恢复；`recovered=1` 表示错误路径后成功恢复。集成回归中的
`wr_rsp=10` 表示 10 个写 descriptor 都取得了写完成响应，命令不是在最后一个
write-data beat 上提前完成。

## 3. 行级读写和 4 KiB 分段

`tb_render_cmd_mem_engine_burst` 同时检查：

- 每个 descriptor 的 beat 数不超过 `MAX_WRITE_BEATS`；
- 从 `0x0FFE` 开始的 RGB565 行被拆成 4 KiB 边界两侧的独立 descriptor；
- write-data 在背压期间保持，`wr_last` 与 advertised length 一致；
- Fill、Block Copy、Color Key 和 Alpha 的最终像素内容；
- 引擎等待 `wr_rsp` 后才产生 `done_valid`。

`tb_cmd_mem` 保留为 `WRITE_BURST_ENABLE=0` 的兼容性回归，不能替代 owner-aware
burst 测试。

新的 `READ_BURST_ENABLE=1` 路径不再逐像素发读 descriptor：Block Copy 按行读取
source；Alpha/Color Key 先读取 source 行，再读取 destination/background 行。
每一行分别受 `MAX_READ_BEATS` 和 AXI 4 KiB 边界限制。源数据先进入双口行 RAM，
Alpha/Color Key 在 destination 返回时同步读取并原位覆盖同一 RAM，因而没有增加第二
个 `4096×16` 全行缓存。

`tb_render_cmd_mem_engine_read_burst` 使用 `MAX_READ_BEATS=4`，令首行从 `0x0ff8`
开始，明确观察到 `0x0ff8` 和 `0x1000` 两段 descriptor；它还覆盖每个通道的确定性
背压、Color Key 的完整 source/background 行读取，以及提前 `rsp_last` 必须令命令
报错。`tb_c2_cmd_mem_engine_burst` 则在 owner-aware 仲裁器和行为内存后验证
Fill/Copy/Color Key/Alpha 的读写行 burst 集成闭环。

历史结果 `req=21 reads=11 writes=10 wr_rsp=10` 来自改造前逐像素读取的集成基线；
当前同一功能集合为 `req=18 reads=8 writes=10 wr_rsp=10`，descriptor 数下降来自行读
合并，而非删除功能。

RGB565 的基地址对齐不足以保证后续行对齐：奇数字节 stride 会让第二行起始地址
失去两字节对齐。因此 parser 与 engine 的 parser-bypass 入口均新增“实际使用的
stride 必须为偶数”的校验，与已有 `stride>=width×2` 检查共同在发出任何内存
请求前拒绝非法命令。NOP 不使用 surface；Solid Fill 不使用 source，因此这些
未使用字段不会被误拒绝。`tb_c2_stride_alignment` 分别检查7项 parser拒绝和7项
engine直连拒绝、6项合法操作及32个最终像素；`errors=7` 是预期的错误注入计数。

## 4. 显示和系统回归

系统回归使用 4×2 小栅格及行为内存。Page flip 在 vblank 提交，下一拍显示路径
捕获新的 active page 并开始 prefetch；复位后的第一帧因没有此前的 vblank，按设计
保持黑屏。测试随后逐像素核对 page1 的 8 个 RGB565 值，确认不是旧页或错位数据，
并在该帧每一个 `DE` 位置强制要求 `video_valid=1`，不允许把跨帧有效样本拼成一帧；
最后还读取累计 `display_error_count` 并要求为 0，同时要求
`display_underflow=0`、`system_error=0`。

真实固定光栅没有暂停能力。仿真直连分支把 PHY ready 固定为 1；实际视频 PHY
必须保证 active video 期间 `pixel_ready` 不拉低，否则 RTL 会记录显示错误。

竞赛接口 shell 回归把系统切到 AXI4-Lite CSR 和外部 AXI4 Full 分支，在 DDR3
`init_done=0` 时通过 AXI4-Lite 写入八个命令字并提交 NOP，再读回 completed counter。
NOP 不访问内存，因此该测试证明的是 Sapphire 控制接口至 parser/engine 的系统连线
和 generate 分支，不证明真实 DDR3 数据事务。宽拍读写事务由独立 AXI4 adapter
testbench 覆盖，最终仍需接生成的 DDR3 IP 和板卡做联合验证。

## 5. AXI4 接口层验证

`c2_axi4lite_csr_adapter` 为单 outstanding AXI4-Lite slave。专项回归分别令 W 先于
AW、AW 先于 W，并同时排队读写；检查完整写的 CSR 请求稳定性、写优先仲裁、B/R
背压期间 payload 不变，以及非 `WSTRB=4'hf` 的写返回 `SLVERR` 且完全不触发 CSR。

`c2_mem_to_axi4_adapter` 把 16-bit 抽象 beat 聚合到参数化 AXI 宽拍。最终专项
分别用64-bit与128-bit数据宽度覆盖未对齐到宽拍边界的首尾lane、`WSTRB`、
AW/W/B与AR/R背压、读拆包、单outstanding、错误RID/RESP、提前/延后RLAST，
以及跨4 KiB和未对齐descriptor的本地拒绝。两个宽度的主计数均为
`aw=6 ar=14 r=25 protocol=5 axi=5`，错误计数来自主动注入，不代表回归失败。

最后修正了 WVALID 等待 AWREADY 的写通道依赖：AW与W现独立推进，分别记录
地址握手和最终W握手；只有两者都完成才等待B。测试显式覆盖从机等待WVALID才
给AWREADY、首个W先于AW、全部W完成后再延迟接收AW三种合法时序，并检查AW
延迟期间不多收抽象写数据、不提前接受B。每种时序均被命中，读错误则保持
terminal抽象响应后drain至真实AXI RLAST的收尾规则。

系统默认参数为128 bit，但最终数据宽度和ID宽度仍必须服从Efinity DDR3 IP的
实际生成接口。

可从仓库根目录重跑整套验证：

```powershell
.\case2\scripts\Run-NewguideRegression.ps1
```

默认创建新时间戳目录；`-PythonPath`、`-VivadoBin`、`-RunName` 可覆盖本机参数。
脚本逐阶段检查退出码、out-of-job状态和PASS标记，拒绝覆盖已有运行目录。

## 6. Vivado 综合代理

为避免“仿真正确但大数组被综合成触发器”，另用 Vivado 2023.1 对 Artix-7 做了
无约束综合代理：

- 启用读写burst并包含odd-stride修正的 `render_cmd_mem_engine` 最终独立综合为
  2,265 LUT、647 FF、2×RAMB36E1、0 DSP；顺序重跑状态
  `synth_proxy/engine_axi_final_run/sequential_retry.status.json` 为
  `worker_in_job=false`、`state=completed`、`returncode=0`；
- `c2_line_fifo`：`1024×17` 映射为 1×RAMB18E1；
- 选择 AXI4-Lite、AXI4 Full、clock/video/CDC IP 分支的
  `c2_renderer_system` 最终结果：3,680 LUT、3,840 FF、2×RAMB36E1、1×RAMB18E1、
  0 DSP；其中 `c2_axi4lite_csr_adapter` 为115 LUT/100 FF，
  `c2_mem_to_axi4_adapter` 为459 LUT/439 FF；厂商黑盒内部资源均为0/未计。
  报告在 `synth_proxy` 目录。

system综合采用 `synth_proxy/synth_system_singlethread.tcl` 的单线程方式。较早的
多进程尝试曾因辅助进程读取Vivado安装脚本失败而中止；随后单线程方式恢复通过，
最终资源以上述3,680 LUT/3,840 FF报告为准，未修改工具安装。

此前记录的 system 2,690 LUT/3,108 FF 是加入行级读 burst 和两层 AXI 适配之前的
历史代理结果；中间版本3,602 LUT/3,830 FF也已被最终结果替代，不应继续作为当前
RTL数字引用。

这些结果证明当前大缓存编码对 Vivado 是 block-RAM friendly，并给出一个逻辑规模
代理；没有时序约束，目标器件也不是 Ti60，因此不能据此声称 Efinity 资源、DSP
映射或 Fmax 已通过。

## 7. Efinity newguide 结构映射

`efinity_smoke/outflow_sv_axi_final/case2_rtl_probe_axi_final.map.rpt`
记录了本轮最终AXI修正版的 Efinity v2026.1.132.3.9 Ti60F225 结构map
通过结果：2,384 LUT4、2,134 FF、804 ADD、0 RAM、0 DSP。

该测试使用 `case2_rtl_probe_top_full`，把 AXI ready/response 输入绑 0，且没有
启用 AXI4-Lite CSR 分支。大量下游数据路径因此被裁剪，RAM/DSP 的 0 不代表完整
renderer 不需要这些资源，也不代表其 RAM/DSP 映射已验收。这个结果仅验证当前
源代码与 Efinity 的解析/结构映射兼容；不能替代带真实 IP 和有效端口激励的完整
综合、布局布线、时序或板级验证。

## 8. 验证边界

功能测试使用 `render_owner_mem_model` 等行为模型；这些数组和响应逻辑不是 Efinix
DDR3 controller/PHY，也不是可据此估算资源的综合 RAM。IP stub 只运行 `xvlog` 和
`xelab`，用于检查 generate 分支、端口宽度和黑盒连线；空黑盒没有行为，故不运行
`xsim`。

当前 PASS 不覆盖完整 Efinity 综合/布局布线、Sapphire 生成系统与软件、PLL、DDR3
controller/PHY training 和刷新、真实 CDC、HDMI PHY、引脚/时序约束或板上吞吐。
AXI adapter 的通过不等于它已经与厂商 DDR3 IP 端口、时钟域和初始化流程完成联合
验证；上述项目仍需 Efinity 生成 IP 和实际竞赛板卡。
