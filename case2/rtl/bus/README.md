# AXI4 接口层

本目录是 8.22 更正版之后新增的板卡无关总线层，已接入
`c2_renderer_system.sv`，不依赖 Efinity 原语。

## `c2_axi4lite_csr_adapter`

Sapphire 控制面使用单 outstanding AXI4-Lite slave：

- AW 与 W 可任意先后到达，各有一项缓存；
- 完整写优先于同时等待的读，CSR 访问在 `csr_ready` 前保持稳定；
- B/R 在上游背压期间保持 payload；
- 当前 CSR ABI 只接受 32-bit 全字写，非 `WSTRB=4'hf` 返回 `SLVERR`，且不修改寄存器。

系统参数 `USE_AXI4LITE_CSR=1` 时启用该接口；默认 0 保留五线 direct-CSR
仿真入口。

## `c2_mem_to_axi4_adapter`

数据面把 16-bit RGB565 抽象 beat 聚合到参数化 `AXI_DATA_W`（默认 128 bit）
的 AXI4 Full master：

- 地址向 AXI 宽拍边界对齐，首尾未使用 byte lane 由 `WSTRB=0` 保护；
- 连续 RGB565 写拍聚合为宽 W beat，宽 R beat 按请求范围拆回 16 bit；
- 采用对齐全宽 INCR burst，单 outstanding、ID 0；
- AW 与 W 独立推进，不等待 `AWREADY` 才收集/发出 W；W 可先于 AW 被接收，
  仅在 AW 和最后一个 W 均已握手后进入 B 响应等待；
- AXI B 转为抽象 `mem_wr_rsp`，RRESP/BRESP、ID 和 RLAST 异常均转为错误；
- 错误读在抽象侧终止后仍 drain 到真实 AXI RLAST；
- descriptor 若未对齐、映射后超过 256 个 AXI beat 或跨越 4 KiB，则本地拒绝，不发 AW/AR。

上游渲染/显示模块已按 4 KiB 和最大长度拆分，所以正常事务不会触发本地拒绝。
DDR3 controller 的 AXI 数据宽度、ID 宽度和时钟必须以 Efinity 生成端口为准再设置
`AXI_DATA_W/AXI_ID_W`。本模块结束于 AXI4 信号；DDR3 training、刷新、PHY 和引脚
仍属于厂商 IP/实板边界。

## 回归

- `tb/bus/tb_c2_axi4lite_csr_adapter.sv`
- `tb/bus/tb_c2_mem_to_axi4_adapter.sv`
- `tb/bus/tb_c2_mem_to_axi4_adapter_128.sv`（同一组参数化测试，128-bit AXI）
- `tb/system/tb_c2_renderer_system_axi_shell.sv`

测试分别经过 `xvlog`、`xelab`、`xsim`。最终复验使用
`case2/scripts/Start-DetachedEdaTool.ps1` 经 WMI 启动，并检查 worker 实际已脱离
Windows Job；仅仅分开命令不保证这一点。系统级测试通过 AXI4-Lite
提交 NOP，并在 DDR3 尚未初始化的条件下确认控制闭环完成且未错误发起 AXI 写。
