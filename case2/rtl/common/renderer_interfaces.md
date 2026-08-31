# 底层模块接口契约

## Command stream

```systemverilog
input  logic         clk;
input  logic         rst_n;
input  logic [255:0] cmd_data;
input  logic         cmd_valid;
output logic         cmd_ready;
```

命令只有在 `cmd_valid && cmd_ready` 的时钟沿被接收。FIFO 满时必须拉低
`cmd_ready`，不得覆盖旧命令。

## Pixel stream

```systemverilog
valid/ready + pixel[15:0] + x/y（若模块需要坐标）
```

数据只有在 `valid && ready` 时推进；下游背压时上游必须保持 data 和 valid。

## Abstract memory transaction

```systemverilog
req_valid, req_ready, req_write, req_addr, req_len, req_wdata, req_wstrb
rsp_valid, rsp_ready, rsp_rdata, rsp_last, rsp_error       // read response
wr_rsp_valid, wr_rsp_ready, wr_rsp_error                   // write completion
```

`req_addr` 为 byte address，`req_len` 为 beat 数减一，第一版建议 16-bit/32-bit
数据宽度以简化 testbench。AXI4/DDR 适配器在后续边界层实现，不在算子内部出现。

接口没有 transaction ID：单个 master 必须在收到完整读响应 burst 或写完成响应
前保持唯一事务未完成。共享存储器使用 `c2_mem_arbiter_2m_owner` 记住响应归属。
旧的单 beat 兼容路径可在请求握手时完成；系统默认的行级 burst 路径必须等待
`wr_rsp_valid && wr_rsp_ready`，该通道对应 AXI4 `B` 响应或原生外存控制器的提交/
错误确认。

### 多 beat 读突发

- `req_len = N-1` 表示本次读请求需要 `N` 个连续数据 beat；地址是 byte address，
  后续 beat 地址按 `DATA_W/8` 字节递增。
- 响应 beat 必须按请求顺序返回。最后一个 beat 的 `rsp_last=1`，且在
  `rsp_ready=0` 时保持 `rsp_valid/rsp_rdata/rsp_last/rsp_error` 不变。
- `rsp_error` 按 beat 表示该地址是否出错；上层在完成事件中汇总为事务错误。
- 没有 ID 时禁止不同读事务的响应交错；仲裁器在 `rsp_last` 被消费前不能切换
  owner。

当前 `render_burst_mem_model` 和 `c2_burst_read_stream` 已实现并验证这套读契约。

### 带 owner 的 burst write

行级写回使用额外的数据通道：

```systemverilog
// per-master and shared write-data stream
wr_valid, wr_ready, wr_data[DATA_W-1:0], wr_strb[DATA_W/8-1:0], wr_last
```

`c2_mem_arbiter_2m_owner` 先仲裁并转发一个写 descriptor，再锁定该
descriptor 的 owner。接受 `wr_last` 或达到 `req_len+1` 的安全边界后进入写响应
阶段，只有下游的一个 `wr_rsp` 被原 owner 接受后才释放事务。在此期间另一个
master 的 descriptor 和写数据都被反压；读事务则保持到最终 `rsp_last`。
`s_wr_error` 是同拍 beat/协议错误，`s_wr_rsp_error` 是控制器稍后返回的整事务
提交错误；两者都会汇总到命令完成状态。提前/缺失 `wr_last` 会产生协议错误，
但真实 adapter 仍必须终止底层事务并返回且只返回一个 `wr_rsp`，避免 owner 永久
等待。读错误同样必须作为当前读事务的终止 beat 返回。

`render_cmd_mem_engine` 在 `WRITE_BURST_ENABLE=1` 时按行收集结果，同时按
`MAX_WRITE_BEATS` 和 `WRITE_BOUNDARY_BYTES`（系统默认 4096 byte）切分
descriptor/data 对，任何写 descriptor 都不会跨 4 KiB 边界。每段在 `wr_rsp`
返回前不得推进到下一段或报告命令完成。`COLOR_KEY` 命中像素先读回目的像素再
写整行，保持“命中不改背景”的语义。`WRITE_BURST_ENABLE=0` 保留旧单 beat
路径，便于兼容早期单元测试；`c2_renderer_system` 默认且必须启用 burst。

`render_owner_mem_model` 是 XSIM 中同时支持读响应、独立写数据流和延迟写完成
响应的行为模型。
真正的 DDR3/AXI4 burst write 不能把一个 `req_wdata` 字段误当成整段 burst
payload。

### 行/像素流

`c2_rect_burst_reader` 把 `c2_burst_planner` 和 burst read stream 串接起来，输出
`pixel_valid/ready + pixel_x/pixel_y + pixel_last/frame_last`。`c2_line_fifo` 在
像素数据旁携带 `in_last/out_last`，采用寄存首字输出和同步 RAM 读取并支持同步
`flush`，可作为显示读端的行级缓冲；其深度应按预取提前量、最坏外存抖动和
目标器件 RAM 块粒度选择。空 FIFO 收到第一个 word 后需要一个同步前取周期才
拉高 `out_valid`，不改变 ready/valid 数据保持规则。Vivado 代理已将默认深度映射
为 block RAM；最终 Efinix embedded RAM 映射仍须用 Efinity 综合报告确认。
`flush` 优先于当拍输入并丢弃 FIFO 内及同拍到达的数据，这是显示切页清除旧 reader
尾数据所需的语义；通用调用者不得把 flush 拍的表面 ready/valid 当作保留性入队。

## Completion/status

每条命令最终必须产生一个 `done` 或 `error` 事件；状态计数器至少记录 accepted、
completed、memory_error 和 dropped（应始终为 0）四类计数，方便后续 RISC-V 驱动
和 XSIM scoreboard 对齐。
