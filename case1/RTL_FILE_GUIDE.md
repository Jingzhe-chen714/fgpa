# Case-1 RTL 文件与模块关系说明

本文只描述 `case1/rtl` 下的 SystemVerilog 文件，目的是在接入 Efinity
IP Manager 生成的 Sapphire、DDR3、PLL、MIPI/HDMI 外设前，帮助理解当前
厂商无关 RTL 的层次、数据流和控制流。

当前 RTL 共 127 个 `.sv` 文件，分为：

```text
top       系统组合和回归层级
control   CSR、descriptor、frame/lifecycle 控制
cnn       22-stage MicroStyle 算术与 tensor 适配
video     RAW10 ISP、debayer、resize、色彩处理
dma       AXI/DDR reader、writer、arbiter、cache client
display   framebuffer prefetch、合成、720p timing
common    FIFO、CDC、RAM、定点公共定义
vendor    未来接入 Efinity IP 的适配边界/stub
```

## 1. 先看最终主路径

最终板卡无关组合顶层是 `top/c1_r1_portable_soc.sv`。Efinity GUI 生成的
Sapphire APB、DDR3 AXI、camera、video/pin 外壳应当在这个边界外连接。

```text
Sapphire APB/UART/IRQ
        │
        ▼
 c1_apb_r1_mux ── c1_apb_csr + c1_apb_isp_config
        │                         │
        ▼                         ▼
 c1_r1_soc_control        c1_r1_parameter_subsystem
        │                         │
        │                         └─ descriptor/parameter AXI reader
        │                            → atomic parameter bank
        ▼
 c1_frame_manager / frame pair ownership
        │
        ├─ camera RAW10 → CDC FIFO → R1 ISP → capture XRGB writer
        ├─ input framebuffer reader → resize/C8 → tensor adapter
        │                                      │
        │                                      ├─ optional 3-row C8 cache
        │                                      └─ 64-bit tensor path → AXI128
        │
        ├─ 22-stage MicroStyle engine
        │       descriptor dispatcher → parameter scheduler
        │       → Conv/DW/upsample/residual/final → RGB stream
        │
        └─ output XRGB writer → display pair prefetch → line stores
                                                → compositor → 720p timing

 所有 DDR client
        └─ c1_axi_n_serial_arbiter_128 → Efinity DDR3 controller
```

当前七个共享 AXI client 的约定：

| client | 来源 | 方向 | 用途 |
|---:|---|---|---|
| 0 | boardless/frame job | R/W | framebuffer table、输入读、输出写 |
| 1 | capture subsystem | W | camera 捕获后的 XRGB 写回 |
| 2 | parameter subsystem | R | descriptor/weight/parameter arena |
| 3 | capture subsystem | R | framebuffer table |
| 4 | display subsystem | R | original framebuffer prefetch |
| 5 | display subsystem | R | styled framebuffer prefetch |
| 6 | tensor adapter/cache client | R/W | 中间 tensor、window cache、AXI bridge |

## 2. `top/`：系统组合层

| 文件 | module | 功能和上下游 |
|---|---|---|
| `top/c1_r1_portable_soc.sv` | `c1_r1_portable_soc` | 最终厂商无关 SoC 顶层；组合 APB、ISP、capture、parameter、frame manager、CNN、tensor、display 和七客户端 AXI。 |
| `top/c1_r1_microstyle_system_bridge.sv` | `c1_r1_microstyle_system_bridge` | 将 descriptor/config 快照同时送入 CNN top、boardless frame job 和 tensor adapter；统一 done/error/abort/drain。 |
| `top/c1_r1_soc_control.sv` | `c1_r1_soc_control` | lifecycle 控制器；处理 START、single-shot/continuous、capture admission、NN job、display pair、abort 和 busy。内部实例化 `c1_frame_manager`。 |
| `top/c1_r1_capture_subsystem.sv` | `c1_r1_capture_subsystem` | camera RAW10 输入到 R1 capture frontend、frame-table reader 和 XRGB writer 的完整捕获通路。 |
| `top/c1_r1_capture_frontend.sv` | `c1_r1_capture_frontend` | camera clock 到 core clock 的 CDC、RAW10 接收、SOF/EOL/EOF 和帧边界恢复。 |
| `top/c1_r1_parameter_subsystem.sv` | `c1_r1_parameter_subsystem` | descriptor/weight/parameter arena 的 AXI 读取、双 bank 原子提交和 active generation 管理。 |
| `top/c1_r1_compute_shell.sv` | `c1_r1_compute_shell` | compute ingress→CNN engine→compute egress 的流接口封装；适合独立仿真或替换外部 CNN。 |
| `top/c1_r1_display_subsystem.sv` | `c1_r1_display_subsystem` | original/styled framebuffer 预取、line-store CDC、pair ownership、compositor、OSD 和 timing。 |
| `top/c1_r1_rgb_source_mux.sv` | `c1_r1_rgb_source_mux` | 在原图、风格图、分屏或 fail-black 源之间按 display mode 选择像素。 |
| `top/c1_r1_boardless_frame_system.sv` | `c1_r1_boardless_frame_system` | 不依赖 Sapphire/IP 的 640×480 boardless job；用于 table/descriptor、DMA、CNN echo、输出回读长帧验证。 |
| `top/c1_r1_integration_skeleton.sv` | `c1_r1_integration_skeleton` | 早期系统骨架和接口回归层级；不是最终主顶层。 |
| `top/c1_portable_top.sv` | `c1_portable_top` | 较早的厂商无关 capture/compute/display 组合边界，用于过渡回归。 |
| `top/c1_pixel_pipeline_top.sv` | `c1_pixel_pipeline_top` | 早期端到端像素数据通路，主要用于 ISP/resize/stream smoke。 |

### 主顶层工作顺序

1. 软件写 shadow CSR，`c1_apb_csr` 在合法条件下接受 START。
2. `c1_r1_soc_control` 锁存本次 framebuffer、descriptor、weight、tensor、尺寸和模式。
3. `c1_frame_manager` 分配 3 个输入 slot、2 个输出 slot，形成 capture/NN/display ownership。
4. parameter subsystem 完成 descriptor/arena 读取后发布 active generation。
5. capture、input reader、CNN、output writer 和 display 根据 ownership 并行工作。
6. abort 不是立即撤回 VALID，而是排空已经接受的 AXI/stream transaction 后回到安全边界。

## 3. `control/`：控制面、descriptor 和帧生命周期

| 文件 | module/package | 功能和关系 |
|---|---|---|
| `control/c1_apb_csr.sv` | `c1_apb_csr` | 主 APB3 CSR；保存 frame/table、descriptor、weight、tensor、display、IRQ、status、QoS 等寄存器。 |
| `control/c1_apb_isp_config.sv` | `c1_apb_isp_config` | ISP shadow/commit CSR；Bayer/ROI/BLC/AWB/CCM/gamma 配置在 COMMIT 后原子生效。 |
| `control/c1_apb_r1_mux.sv` | `c1_apb_r1_mux` | APB 地址路由；`0x000..0x1ff` 到主 CSR，`0x200..0x2ff` 到 ISP CSR。 |
| `control/c1_descriptor_pkg.sv` | `c1_descriptor_pkg` | 64-byte descriptor ABI、opcode、shape、stride、tensor/parameter 字段和常量定义。 |
| `control/c1_descriptor_decoder_pkg.sv` | `c1_descriptor_decoder_pkg` | descriptor 校验结果、错误码和验证辅助定义。 |
| `control/c1_frame_buffer_pkg.sv` | `c1_frame_buffer_pkg` | 16-byte framebuffer table entry、slot 状态和像素格式定义。 |
| `control/c1_layer_command_decoder.sv` | `c1_layer_command_decoder` | 将 512-bit descriptor 解码为 Conv/DW/1×1/upsample/residual command，并执行 ABI/range/区域校验。 |
| `control/c1_layer_scheduler.sv` | `c1_layer_scheduler` | 早期/通用 layer scheduler；按 descriptor 顺序发布 layer command。 |
| `control/c1_descriptor_scheduler_subsystem.sv` | `c1_descriptor_scheduler_subsystem` | 将 descriptor reader、decoder 和 layer scheduler 组合成可独立验证的子系统。 |
| `control/c1_r1_config_loader_subsystem.sv` | `c1_r1_config_loader_subsystem` | 读取并缓存 22 个 descriptor，完成连续性、几何和 generation 检查。 |
| `control/c1_r1_config_dispatcher.sv` | `c1_r1_config_dispatcher` | 从 active descriptor bank 向 engine/adapter 分发当前 stage 配置。 |
| `control/c1_r1_stage_config_bank.sv` | `c1_r1_stage_config_bank` | 双 bank stage configuration；整批成功后切换 active bank，避免运行中撕裂。 |
| `control/c1_r1_job_frontend.sv` | `c1_r1_job_frontend` | 对 START 做配置快照、合法性检查、job launch 和 terminal/error 处理。 |
| `control/c1_r1_job_controller.sv` | `c1_r1_job_controller` | 单次 R1 job 的 FSM；连接 frontend、engine、adapter、output 和 abort/drain。 |
| `control/c1_frame_manager.sv` | `c1_frame_manager` | 3 输入/2 输出 slot ownership；状态包括 FREE、CAPTURING、READY_NN、PROCESSING、READY_DISPLAY、DISPLAY。 |
| `control/c1_frame_pair_resolver.sv` | `c1_frame_pair_resolver` | 选择可显示的 original/styled framebuffer pair，并处理 frame-id 顺序。 |

控制面与数据面的关系是“控制快照先行”：descriptor/config 未完成时不放行首个
C8 像素；job 运行期间 APB shadow 修改只影响下一次 START。

## 4. `cnn/`：MicroStyle 计算和 tensor 数据面

### 4.1 最终 22-stage 路径

| 文件 | module | 功能和关系 |
|---|---|---|
| `cnn/c1_r1_microstyle_cnn_top.sv` | `c1_r1_microstyle_cnn_top` | 22-stage runtime 顶层；连接 config dispatcher、engine、descriptor validation 和 tensor sideband。 |
| `cnn/c1_r1_microstyle_engine.sv` | `c1_r1_microstyle_engine` | 真实 signed-INT8 stage engine；参数重排、Conv/DW/1×1、bias、requant、saturation、upsample/residual/final。 |
| `cnn/c1_r1_microstyle_tensor_adapter.sv` | `c1_r1_microstyle_tensor_adapter` | 将输出像素坐标映射为 SAME/stride/tap/C8 group/tensor bank 地址；默认单 outstanding 64-bit 请求。 |
| `cnn/c1_r1_c8_parameter_scheduler.sv` | `c1_r1_c8_parameter_scheduler` | 从 128-bit parameter arena word 顺序读取并重排为当前 stage 的 weight/bias/multiplier/shift。 |
| `cnn/c1_r1_parameter_bank.sv` | `c1_r1_parameter_bank` | 参数双 bank 存储和 generation 提交；失败或半批次加载不污染 active bank。 |
| `cnn/c1_r1_compute_ingress.sv` | `c1_r1_compute_ingress` | RGB8/XRGB 输入转为 engine 使用的 centered signed-8 C8 stream。 |
| `cnn/c1_r1_compute_egress.sv` | `c1_r1_compute_egress` | engine 输出 C8/signed 数据转回 RGB/XRGB stream，并处理 terminal/abort。 |
| `cnn/c1_rgb_s8_center_codec.sv` | `c1_rgb_s8_center_codec` | RGB888 与 centered signed-8 三通道之间的单项弹性编码转换。 |

### 4.2 计算叶和辅助模块

| 文件 | module | 功能和关系 |
|---|---|---|
| `cnn/c1_s8_dot8_accum.sv` | `c1_s8_dot8_accum` | 8 lane signed-INT8 乘加基础树。 |
| `cnn/c1_s8_dot8_accum_pipelined.sv` | `c1_s8_dot8_accum_pipelined` | dot accumulator 的可选一拍流水版本。 |
| `cnn/c1_s8_dot8_accum_treepipe.sv` | `c1_s8_dot8_accum_treepipe` | product→pair→quad→sum 的完整分级 dot tree，实验开关使用。 |
| `cnn/c1_dot8x8_requant_core.sv` | `c1_dot8x8_requant_core` | 8 个输出通道×8 lane dot/requant 核心；是 Ti60 DSP 资源的主要消费者。 |
| `cnn/c1_dot8x8_requant_bank.sv` | `c1_dot8x8_requant_bank` | 多个 8×8 dot core 的 lock-step bank。 |
| `cnn/c1_dot8x8_requant_pingpong.sv` | `c1_dot8x8_requant_pingpong` | inter-pixel overlap/ping-pong 实验壳，不是当前默认主路径。 |
| `cnn/c1_dwconv3x3_c8_requant_core.sv` | `c1_dwconv3x3_c8_requant_core` | 8-channel depthwise 3×3 MAC、requant 和输出。 |
| `cnn/c1_conv3x3_rgb3.sv` | `c1_conv3x3_rgb3` | 3 输入/3 输出的早期 RGB 3×3 convolution leaf。 |
| `cnn/c1_dwconv3x3_rgb3.sv` | `c1_dwconv3x3_rgb3` | 3-channel depthwise 3×3 早期 leaf。 |
| `cnn/c1_pwconv1x1_rgb3.sv` | `c1_pwconv1x1_rgb3` | 3 输入/3 输出 pointwise 1×1 早期 leaf。 |
| `cnn/c1_requant_s8.sv` | `c1_requant_s8` | 单个 signed-8 affine multiplier/shift、round 和 saturation。 |
| `cnn/c1_requant_bank8.sv` | `c1_requant_bank8` | 八通道并行 affine requant bank。 |
| `cnn/c1_residual_add_s8.sv` | `c1_residual_add_s8` | 单通道 signed-8 residual add。 |
| `cnn/c1_residual_add_c8.sv` | `c1_residual_add_c8` | C8 向量 residual add，供 stage 间 skip path 使用。 |
| `cnn/c1_s8_upsample2_c8.sv` | `c1_s8_upsample2_c8` | C8 nearest-neighbour 2× upsample。 |
| `cnn/c1_s8_window3x3_same_c8.sv` | `c1_s8_window3x3_same_c8` | C8 SAME/replicate 3×3 window 生成。 |
| `cnn/c1_window_line_cache_c8.sv` | `c1_window_line_cache_c8` | 三行、全 group C8 payload cache；属于 cache seam 的本地存储核心。 |
| `cnn/c1_window_line_cache_ctrl.sv` | `c1_window_line_cache_ctrl` | 早期 boardless line-cache 控制原型，用于 refill/row-tag 回归。 |
| `cnn/c1_style_cnn3.sv` | `c1_style_cnn3` | 功能性 streaming CNN baseline，用于较早的模型/接口验证。 |

当前最终 engine 的主要关系是：

```text
c1_r1_microstyle_cnn_top
  ├─ c1_r1_config_dispatcher
  ├─ c1_r1_microstyle_engine
  │    ├─ c1_r1_c8_parameter_scheduler
  │    ├─ c1_layer_command_decoder
  │    ├─ c1_dot8x8_requant_core
  │    └─ c1_dwconv3x3_c8_requant_core
  └─ tensor sideband → c1_r1_microstyle_tensor_adapter
```

engine 负责“算什么”，tensor adapter 负责“从哪里取窗口/中间 tensor”；二者
通过 stage config、C8 group、valid/ready 和 error/abort sideband 对齐。

## 5. `video/`：RAW10 ISP 和 resize

| 文件 | module | 功能和关系 |
|---|---|---|
| `video/c1_raw10_unpack4.sv` | `c1_raw10_unpack4` | CSI-2 RAW10 五字节解包为四个 10-bit sample。 |
| `video/c1_black_level_raw10.sv` | `c1_black_level_raw10` | RAW10 黑电平扣除，带饱和/截断。 |
| `video/c1_debayer_rggb10_valid.sv` | `c1_debayer_rggb10_valid` | 早期 RGGB10 bilinear debayer，仅在完整 3×3 数据有效时输出。 |
| `video/c1_r1_debayer_bilinear.sv` | `c1_r1_debayer_bilinear` | R1 四 Bayer phase、ROI phase-aware 的 bilinear debayer。 |
| `video/c1_color_correct.sv` | `c1_color_correct` | AWB gain、3×3 CCM、offset 和 u10/u8 颜色变换。 |
| `video/c1_gamma_lut16.sv` | `c1_gamma_lut16` | 17 点分段线性 gamma LUT。 |
| `video/c1_isp_pipeline.sv` | `c1_isp_pipeline` | 早期 RAW/ISP 组合链。 |
| `video/c1_r1_isp_pipeline.sv` | `c1_r1_isp_pipeline` | 最终 R1 RAW10→BLC→debayer→color pipeline。 |
| `video/r1_blc_bayer4_u10.sv` | `r1_blc_bayer4_u10` | 四 Bayer phase 独立黑电平修正。 |
| `video/r1_rgb10_color_pipeline.sv` | `r1_rgb10_color_pipeline` | RGB u10 post-debayer color processing。 |
| `video/r1_bilinear_interp_rgb888.sv` | `r1_bilinear_interp_rgb888` | RGB888 bilinear 插值算术，当前有四级流水优化版本。 |
| `video/r1_resize_request_q16.sv` | `r1_resize_request_q16` | 生成 Q16 resize 坐标和权重。 |
| `video/c1_r1_resize_line_sampler.sv` | `c1_r1_resize_line_sampler` | 两行 RGB sampler，提供 bilinear 所需邻域。 |
| `video/c1_r1_resize_pipeline.sv` | `c1_r1_resize_pipeline` | RGB888 输入到目标尺寸的完整 R1 streaming resize。 |
| `video/c1_r1_resize_system.sv` | `c1_r1_resize_system` | resize request、line sampler、interpolation 的系统封装。 |
| `video/c1_rgb_decimate.sv` | `c1_rgb_decimate` | 固定整数比例最近邻 decimator，用于输入尺寸预处理。 |

主路径为：

```text
RAW10 → unpack4 → BLC → R1 debayer → AWB/CCM/gamma
      → resize request/line sampler/bilinear → RGB888/XRGB
```

实际 MIPI CSI-2 packet/CRC/PHY 不在这些文件中，由 vendor adapter 和 Efinity IP
提供合法 RAW10 stream。

## 6. `dma/`：AXI、DDR client、cache 和仲裁

### 6.1 主系统使用的 AXI 模块

| 文件 | module | 功能和关系 |
|---|---|---|
| `dma/c1_axi_n_serial_arbiter_128.sv` | `c1_axi_n_serial_arbiter_128` | 七客户端 ID-less AXI128 round-robin 事务锁定仲裁器；R/B 终止后释放 owner。 |
| `dma/c1_axi_n_read_burst_arbiter_128.sv` | `c1_axi_n_read_burst_arbiter_128` | 可选读 burst 仲裁/组合，用于性能实验。 |
| `dma/c1_axi_n_write_burst_arbiter_128.sv` | `c1_axi_n_write_burst_arbiter_128` | 可选写 burst 仲裁/组合，用于性能实验。 |
| `dma/c1_axi2_serial_arbiter_128.sv` | `c1_axi2_serial_arbiter_128` | 两客户端小型 AXI 仲裁器，常用于局部 proxy/smoke。 |
| `dma/c1_axi_read_abort_fence.sv` | `c1_axi_read_abort_fence` | 将任意 abort 转换为可排空的读事务 fence，保证 R/RLAST 边界。 |
| `dma/c1_axi_write_skid_bridge.sv` | `c1_axi_write_skid_bridge` | 单项 AW/W/B skid buffer，保持 VALID 稳定和写响应顺序。 |
| `dma/c1_axi_shared_owner_epoch_arbiter_128.sv` | `c1_axi_shared_owner_epoch_arbiter_128` | 可选 owner/admit gating 壳，为维护边界和 epoch fence 提供显式 busy/quiescent。 |
| `dma/c1_axi_shared_owner_epoch_fence.sv` | `c1_axi_shared_owner_epoch_fence` | 独立维护/flush/epoch 控制 seam，当前未接入默认主顶层。 |
| `dma/c1_axi_shared_qos_monitor.sv` | `c1_axi_shared_qos_monitor` | 汇总各 client AR/AW/R/W/B busy、等待、deadline、underflow 和 owner hold 统计。 |
| `dma/c1_axi128_write_mlp.sv` | `c1_axi128_write_mlp` | 多 outstanding 写事务实验模块；当前主 tensor path 尚未采用。 |

### 6.2 Frame/parameter DMA

| 文件 | module | 功能和关系 |
|---|---|---|
| `dma/c1_axi_descriptor_reader.sv` | `c1_axi_descriptor_reader` | 从 DDR 读取 64-byte descriptor。 |
| `dma/c1_axi_parameter_loader.sv` | `c1_axi_parameter_loader` | 从 parameter arena 读取 128-bit words，送入 `c1_r1_parameter_bank`。 |
| `dma/c1_axi_frame_buffer_table_reader.sv` | `c1_axi_frame_buffer_table_reader` | 读取 16-byte framebuffer table entry。 |
| `dma/c1_axi_xrgb_frame_reader.sv` | `c1_axi_xrgb_frame_reader` | DDR XRGB8888 读回并转换为 RGB raster stream。 |
| `dma/c1_axi_xrgb_frame_writer.sv` | `c1_axi_xrgb_frame_writer` | RGB raster 转 XRGB8888 AXI 写通道。 |
| `dma/c1_table_response_elastic_fifo.sv` | `c1_table_response_elastic_fifo` | framebuffer table response 的一项注册弹性边界。 |
| `dma/c1_cache_refill_scheduler.sv` | `c1_cache_refill_scheduler` | cache miss 后安排 line refill。 |
| `dma/c1_cache_refill_scheduler_read_client.sv` | `c1_cache_refill_scheduler_read_client` | 将 refill scheduler 接到窄 read client。 |
| `dma/c1_cache_refill_scheduler_read_client_exact.sv` | `c1_cache_refill_scheduler_read_client_exact` | 严格 exact-count 的 refill/read client 组合。 |
| `dma/c1_cache_refill_completion_adapter.sv` | `c1_cache_refill_completion_adapter` | refill completion、error、flush 和 owner 路由适配。 |

### 6.3 Tensor AXI 和性能实验路径

| 文件 | module | 功能和关系 |
|---|---|---|
| `dma/c1_tensor_mem_axi128_bridge.sv` | `c1_tensor_mem_axi128_bridge` | 64-bit tensor req/rsp 映射成单拍 AXI4-128；`addr[3]` 选择上下 64 bit，写 strobe 对齐。 |
| `dma/c1_tensor_mem_path_seam.sv` | `c1_tensor_mem_path_seam` | legacy direct path 与 optional performance path 的选择边界。 |
| `dma/c1_tensor_mem_axi128_packer.sv` | `c1_tensor_mem_axi128_packer` | 相邻窄请求合并为 AXI128 beat 的 boardless 原型。 |
| `dma/c1_tensor_mem_axi128_read_burst_client.sv` | `c1_tensor_mem_axi128_read_burst_client` | tensor read burst client。 |
| `dma/c1_tensor_mem_axi128_write_burst_client.sv` | `c1_tensor_mem_axi128_write_burst_client` | tensor write burst client。 |
| `dma/c1_tensor_mem_axi128_read_fabric_2c.sv` | `c1_tensor_mem_axi128_read_fabric_2c` | 两客户端 read fabric。 |
| `dma/c1_tensor_mem_axi128_write_mlp_adapter.sv` | `c1_tensor_mem_axi128_write_mlp_adapter` | 逻辑写请求到多 outstanding 写接口的适配。 |
| `dma/c1_tensor_mem_axi128_write_mlp_fabric_2c.sv` | `c1_tensor_mem_axi128_write_mlp_fabric_2c` | 两客户端写 MLP boardless fabric。 |
| `dma/c1_tensor_mem_axi128_write_parallel_fabric.sv` | `c1_tensor_mem_axi128_write_parallel_fabric` | 多 lane 并行写路径实验。 |
| `dma/c1_tensor_window_cache_seam.sv` | `c1_tensor_window_cache_seam` | adapter 与 tensor memory 之间的三行 C8 cache；只缓存 Conv3×3/DW tap read。 |
| `dma/c1_tensor_window_cache_axi_client.sv` | `c1_tensor_window_cache_axi_client` | 将 window-cache seam 封装成 portable SoC client-6。 |
| `dma/c1_tensor_window_cache_burst_axi_client.sv` | `c1_tensor_window_cache_burst_axi_client` | 下一阶段 burst refill/client-6 实验封装。 |
| `dma/c1_window_line_cache_c8_burst_shell.sv` | `c1_window_line_cache_c8_burst_shell` | boardless line-cache burst refill 壳。 |
| `dma/c1_window_line_cache_c8_exact_burst_shell.sv` | `c1_window_line_cache_c8_exact_burst_shell` | exact-count burst/refill 壳。 |

当前默认 tensor 路径是：

```text
c1_r1_microstyle_tensor_adapter
  → c1_tensor_window_cache_seam (默认 bypass)
  → c1_tensor_mem_axi128_bridge
  → client-6
  → c1_axi_n_serial_arbiter_128
```

`packer`、burst client、MLP fabric 和 shared owner/epoch 模块均是可选性能路线，
不能因为独立仿真通过就认为已经替换默认生产路径。

## 7. `display/`：显示输出

| 文件 | module | 功能和关系 |
|---|---|---|
| `display/c1_display_prefetch_pair.sv` | `c1_display_prefetch_pair` | original/styled 两路 framebuffer prefetch 和 pair ownership。 |
| `display/c1_display_line_store_cdc.sv` | `c1_display_line_store_cdc` | core/reader 域到 pixel 域的双 bank RGB line store CDC。 |
| `display/c1_display_flush_reset.sv` | `c1_display_flush_reset` | 显示 flush、underflow、pair swap 的局部复位/清空。 |
| `display/c1_split_compositor.sv` | `c1_split_compositor` | 风格图居中、原图居中、左右分屏、fail-black 四种布局。 |
| `display/c1_hex_osd_overlay.sv` | `c1_hex_osd_overlay` | 将状态、错误和计数编码为十六进制 OSD overlay。 |
| `display/c1_video_timing_720p.sv` | `c1_video_timing_720p` | 1280×720@60Hz 的 HS/VS/DE/pixel timing。 |

显示链为：

```text
DDR original/styled reader
  → display_prefetch_pair
  → line_store_cdc
  → rgb_source_mux
  → split_compositor
  → hex_osd_overlay
  → video_timing_720p
```

HDMI/TMDS PHY、PLL 和实际 pin 不在这些文件中。

## 8. `common/`：公共基础模块

| 文件 | module/package | 功能和主要使用者 |
|---|---|---|
| `common/c1_fixed_pkg.sv` | `c1_fixed_pkg` | 定点 round、饱和、signed/unsigned 转换公共函数。 |
| `common/c1_async_stream_fifo.sv` | `c1_async_stream_fifo` | 双时钟 ready/valid FIFO；capture/display CDC。 |
| `common/c1_stream_fifo.sv` | `c1_stream_fifo` | 单时钟 ready/valid elastic FIFO。 |
| `common/c1_event_cdc.sv` | `c1_event_cdc` | toggle/ack 单事件 CDC；清错、underflow、frame event。 |
| `common/c1_reset_sync.sv` | `c1_reset_sync` | 异步 assert、同步 deassert reset synchronizer。 |
| `common/c1_ram_sdp_read_first.sv` | `c1_ram_sdp_read_first` | 可推断的同步 single-read/single-write RAM，read-first 语义。 |
| `common/c1_window3x3.sv` | `c1_window3x3` | 通用三行 3×3 streaming window generator。 |
| `common/c1_r1_unified_output_fifo.sv` | `c1_r1_unified_output_fifo` | CNN result 的可选统一输出 FIFO，默认关闭。 |
| `common/c1_r1_unified_output_skid.sv` | `c1_r1_unified_output_skid` | 一项输出 skid/abort boundary，默认关闭。 |

这些模块不携带 Ti60 专用原语，优先用于 Icarus/XSim 和 Efinity map 兼容性验证。

## 9. `vendor/`：Efinity IP 接入边界

| 文件 | module | 当前作用 |
|---|---|---|
| `vendor/c1_sapphire_apb_master_adapter.sv` | `c1_sapphire_apb_master_adapter` | 将 Sapphire APB master 接到 Case-1 APB CSR seam；需用最终 `soc.h`/地址映射复核。 |
| `vendor/c1_sapphire_irq_adapter.sv` | `c1_sapphire_irq_adapter` | Case-1 level IRQ 到 Sapphire PLIC/外部中断输入的适配。 |
| `vendor/c1_sapphire_vendor_adapter_stub.sv` | `c1_sapphire_vendor_adapter_stub` | 无 Sapphire IP 时的仿真 stub；拿到 IP Manager 输出后替换/旁路。 |
| `vendor/c1_memory_vendor_adapter_stub.sv` | `c1_memory_vendor_adapter_stub` | AXI memory vendor boundary stub；未来连接 DDR3 controller。 |
| `vendor/c1_camera_vendor_adapter_stub.sv` | `c1_camera_vendor_adapter_stub` | camera RAW10 vendor boundary stub；未来连接 MIPI CSI/传感器 IP。 |
| `vendor/c1_video_vendor_adapter_stub.sv` | `c1_video_vendor_adapter_stub` | parallel RGB/DE/HS/VS video boundary stub；未来连接 HDMI/TMDS。 |

GUI 集成时，不应把 vendor stub 内的地址、时钟或 pin 假设直接带到板级工程；
必须以 Efinity 生成的 `project.xml`、`peri.xml`、SDC 和 BSP 为准。

## 10. 文件之间的工作原理

### 10.1 控制通路

```text
Sapphire APB
  → c1_sapphire_apb_master_adapter
  → c1_apb_r1_mux
  → c1_apb_csr / c1_apb_isp_config
  → c1_r1_job_frontend
  → c1_r1_soc_control
  → c1_frame_manager + c1_r1_job_controller
```

软件配置是 shadow 写入；START 时只锁存一次，运行期间修改 shadow 不影响当前
job。DONE/ERROR/IRQ 在所有 DMA、CNN、display owner 排空后才允许软件复用内存。

### 10.2 参数和 descriptor 通路

```text
DDR parameter arena
  → c1_axi_descriptor_reader / c1_axi_parameter_loader
  → c1_r1_config_loader_subsystem
  → c1_layer_command_decoder
  → c1_r1_stage_config_bank / c1_r1_parameter_bank
  → c1_r1_config_dispatcher
  → CNN engine + tensor adapter
```

参数采用双 bank 和 generation：当前运行使用 active bank，新配置在 shadow bank
完整校验后一次性提交。descriptor 的 64-byte ABI 决定 opcode、通道、尺寸、stride
和区域边界，decoder 错误会阻止 stage launch。

### 10.3 图像捕获通路

```text
MIPI/RAW10 vendor stream
  → c1_camera_vendor_adapter_stub（未来替换为官方 IP）
  → c1_r1_capture_frontend
  → c1_async_stream_fifo / c1_event_cdc
  → c1_r1_isp_pipeline
  → c1_axi_xrgb_frame_writer
  → DDR input framebuffer
```

capture FIFO 只是 CDC/弹性缓存，不是整帧缓存。无 owner 或 abort 时，frontend
继续消费并静默丢弃到 EOF，避免半帧残留阻塞下一帧。

### 10.4 CNN/tensor 通路

```text
DDR input XRGB
  → c1_axi_xrgb_frame_reader
  → c1_r1_compute_ingress / resize system
  → c1_r1_microstyle_tensor_adapter
  → window cache（可选）
  → c1_tensor_mem_axi128_bridge
  → DDR tensor bank0/1/2

同一 stage command
  → c1_r1_microstyle_engine
  → dot/DW/requant/upsample/residual
  → c1_r1_compute_egress
  → output XRGB writer
```

三块 tensor bank 的软件约定是：

```text
bank0 = tensor_base + 0 MiB
bank1 = tensor_base + 8 MiB
bank2 = tensor_base + 16 MiB
```

默认 adapter 为 correctness-first 的单 outstanding 64-bit 事务；window cache、
AXI packing、burst 和 multi-outstanding 文件目前都是可选性能路线。

### 10.5 显示通路

```text
output framebuffer / original framebuffer
  → c1_display_prefetch_pair
  → c1_display_line_store_cdc
  → c1_r1_rgb_source_mux
  → c1_split_compositor
  → c1_hex_osd_overlay
  → c1_video_timing_720p
  → video vendor adapter
```

display 只在 frame boundary/VSYNC 提交新 pair；没有完整 pair 时保持当前 pair，
从而避免撕裂。真实 HDMI/TMDS 和 PLL 需要 Efinity IP 生成物。

## 11. 哪些文件是“主路径”，哪些是“实验/回归路径”

### GUI 集成时优先接入

```text
top/c1_r1_portable_soc.sv
top/c1_r1_soc_control.sv
top/c1_r1_capture_subsystem.sv
top/c1_r1_parameter_subsystem.sv
top/c1_r1_display_subsystem.sv
top/c1_r1_microstyle_system_bridge.sv
cnn/c1_r1_microstyle_cnn_top.sv
cnn/c1_r1_microstyle_engine.sv
cnn/c1_r1_microstyle_tensor_adapter.sv
dma/c1_axi_n_serial_arbiter_128.sv
dma/c1_tensor_mem_axi128_bridge.sv
vendor/*.sv
```

### 暂不作为默认生产路径

```text
c1_tensor_mem_axi128_packer.sv
c1_tensor_mem_axi128_*_burst_client.sv
c1_tensor_mem_axi128_*_mlp*.sv
c1_tensor_window_cache_burst_axi_client.sv
c1_r1_unified_output_fifo.sv
c1_r1_unified_output_skid.sv
c1_axi_shared_owner_epoch_*.sv
c1_dot8x8_requant_pingpong.sv
c1_s8_dot8_accum_pipelined.sv
c1_s8_dot8_accum_treepipe.sv
```

这些文件可以单独仿真或综合探针通过，但是否启用必须同时检查 AXI 事务计数、
abort/drain、缓存一致性、资源和真实帧率。

## 12. 建议的理解/集成顺序

1. 先阅读 `control/c1_descriptor_pkg.sv`、`control/c1_frame_buffer_pkg.sv` 和 `control/c1_apb_csr.sv`，理解软件 ABI。
2. 再阅读 `top/c1_r1_soc_control.sv`、`control/c1_frame_manager.sv`，理解 frame ownership。
3. 阅读 `cnn/c1_r1_microstyle_cnn_top.sv`、`cnn/c1_r1_microstyle_engine.sv` 和 `cnn/c1_r1_microstyle_tensor_adapter.sv`，理解一层计算和 tensor 地址分工。
4. 阅读 `dma/c1_axi_n_serial_arbiter_128.sv`、`dma/c1_tensor_mem_axi128_bridge.sv`，理解 AXI owner、半字选择和响应路由。
5. 阅读 `top/c1_r1_capture_subsystem.sv`、`top/c1_r1_display_subsystem.sv`，理解输入输出 framebuffer。
6. 最后再把 Efinity 生成的 Sapphire APB、DDR3 AXI、PLL、MIPI/HDMI 和 pin/peri wrapper 接到 `vendor/` 边界。

当前默认生产配置仍为：`PACKED_AFFINE_CACHE=0`、tensor window cache bypass、
单 outstanding tensor path。任何实验开关都应通过对应的 Icarus/XSim regression
后再接入 Efinity 工程。

相关验证和资源报告：

- [ARCHITECTURE.md](D:/contest/2026FPGA/yilingsi/case1/ARCHITECTURE.md)
- [IMPLEMENTATION_STATUS.md](D:/contest/2026FPGA/yilingsi/case1/IMPLEMENTATION_STATUS.md)
- [TEST_RESULTS.md](D:/contest/2026FPGA/yilingsi/case1/TEST_RESULTS.md)
- [Efinity RESOURCE_MAP_RESULTS_20260829.md](D:/contest/2026FPGA/yilingsi/case1/efinity/RESOURCE_MAP_RESULTS_20260829.md)
