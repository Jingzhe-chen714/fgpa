`timescale 1ns/1ps

// Elaboration-only check: all board-dependent generate branches select the
// named blackboxes and therefore remain replaceable by Efinity-generated IP.
module tb_c2_renderer_system_ip_stub;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic csr_valid = 1'b0, csr_write = 1'b0;
  logic [11:0] csr_addr = '0;
  logic [31:0] csr_wdata = '0, csr_rdata;
  logic csr_ready;
  logic video_clk, video_valid, video_de, video_hsync, video_vsync;
  logic [15:0] video_data;
  logic video_init_done, video_init_error, clock_locked;
  logic mem_init_done, mem_init_error, system_busy, system_error;
  logic active_page, pending_page, page_flip_pending, display_underflow;
  logic [31:0] command_submit_count, command_completed_count;

  c2_renderer_system #(
    .H_ACTIVE(4), .H_FRONT(1), .H_SYNC(1), .H_BACK(1),
    .V_ACTIVE(2), .V_FRONT(1), .V_SYNC(1), .V_BACK(1),
    .FB_STRIDE_BYTES(8), .PAGE_BYTES(16), .MEM_BYTES(2048),
    .USE_EXT_MEM_IP(1'b1), .USE_VIDEO_PHY_IP(1'b1),
    .USE_CLOCK_RESET_IP(1'b1)
  ) dut (
    .clk_in(clk), .rst_n_in(rst_n), .csr_valid, .csr_write, .csr_addr,
    .csr_wdata, .csr_rdata, .csr_ready, .video_clk, .video_valid,
    .video_data, .video_de, .video_hsync, .video_vsync, .video_init_done,
    .video_init_error, .clock_locked, .mem_init_done, .mem_init_error,
    .system_busy, .system_error, .active_page, .pending_page,
    .page_flip_pending, .display_underflow, .command_submit_count,
    .command_completed_count
  );
endmodule
