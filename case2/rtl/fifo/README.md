# FIFO/elastic buffer

`c2_sync_fifo` 是同一时钟域的 ready/valid FIFO，支持满状态下同周期 pop+push；
`c2_skid_buffer` 是一项深度的弹性缓冲。两者只使用标准 SystemVerilog，不依赖
Xilinx/ Efinix RAM 原语。

注意：这两个模块只解决同域握手。RISC-V/DDR/HDMI 之间的异步时钟域需要后续
明确时钟方案后使用真正的异步 FIFO 或 CDC 握手，不能直接把本模块跨时钟连接。

