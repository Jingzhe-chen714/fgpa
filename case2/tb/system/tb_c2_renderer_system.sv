`timescale 1ns/1ps

module tb_c2_renderer_system;
  localparam int H = 4;
  localparam int V = 2;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic csr_valid, csr_write;
  logic [11:0] csr_addr;
  logic [31:0] csr_wdata, csr_rdata;
  logic csr_ready;
  logic video_clk, video_valid, video_de, video_hsync, video_vsync;
  logic [15:0] video_data;
  logic video_init_done, video_init_error;
  logic clock_locked, mem_init_done, mem_init_error;
  logic system_busy, system_error;
  logic active_page, pending_page, page_flip_pending, display_underflow;
  logic [31:0] command_submit_count, command_completed_count;
  integer video_seen;
  integer page1_seen;
  logic verify_page1;
  integer video_x;
  integer guard;
  logic [255:0] fill_cmd;
  logic [31:0] status_word;
  logic [31:0] display_errors_word;

  c2_renderer_system #(
    .ADDR_W(32), .DATA_W(16), .LEN_W(16), .PAGE_W(1),
    .CMD_FIFO_DEPTH(4), .MAX_BURST_BEATS(2), .LINE_FIFO_DEPTH(8),
    .H_ACTIVE(H), .H_FRONT(1), .H_SYNC(1), .H_BACK(1),
    // The deterministic behavior model and MAX_BURST_BEATS=2 serialize four
    // short read descriptors.  Give the tiny raster enough vertical blanking
    // to prefetch all eight pixels before the next active frame; otherwise
    // this test would intentionally exercise underflow instead of page data.
    .V_ACTIVE(V), .V_FRONT(1), .V_SYNC(1), .V_BACK(8),
    .FB_STRIDE_BYTES(8), .PAGE_BYTES(16), .PAGE0_BASE(32'h0100),
    .PAGE1_BASE(32'h0200), .MEM_BYTES(2048),
    .USE_EXT_MEM_IP(1'b0), .USE_VIDEO_PHY_IP(1'b0),
    .USE_CLOCK_RESET_IP(1'b0)
  ) dut (
    .clk_in(clk), .rst_n_in(rst_n),
    .csr_valid, .csr_write, .csr_addr, .csr_wdata, .csr_rdata, .csr_ready,
    .video_clk, .video_valid, .video_data, .video_de, .video_hsync,
    .video_vsync, .video_init_done, .video_init_error, .clock_locked,
    .mem_init_done, .mem_init_error, .system_busy, .system_error,
    .active_page, .pending_page, .page_flip_pending, .display_underflow,
    .command_submit_count, .command_completed_count
  );

  always @(posedge clk) begin
    if (rst_n && video_de) begin
      if (verify_page1 && page1_seen < H*V) begin
        if (!video_valid)
          $fatal(1, "page-flip frame underflow at pixel %0d", page1_seen);
        if (^video_data === 1'bx)
          $fatal(1, "video data contains X");
        if (video_data !== (16'h2000 + page1_seen))
          $fatal(1, "page-flip pixel %0d stale/corrupt: got=%h expected=%h",
                 page1_seen, video_data, 16'h2000 + page1_seen);
        page1_seen = page1_seen + 1;
      end
      if (video_valid)
        video_seen = video_seen + 1;
    end
  end

  task automatic csr_write_word(input logic [11:0] addr,
                                input logic [31:0] data);
    begin
      @(negedge clk);
      csr_addr = addr; csr_wdata = data; csr_write = 1'b1; csr_valid = 1'b1;
      while (!csr_ready)
        @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      csr_valid = 1'b0; csr_write = 1'b0;
    end
  endtask

  task automatic csr_read_word(input logic [11:0] addr,
                               output logic [31:0] data);
    begin
      @(negedge clk);
      csr_addr = addr; csr_wdata = '0; csr_write = 1'b0; csr_valid = 1'b1;
      while (!csr_ready)
        @(negedge clk);
      #1 data = csr_rdata;
      @(posedge clk);
      @(negedge clk);
      csr_valid = 1'b0;
    end
  endtask

  task automatic submit_command(input logic [255:0] command);
    begin
      for (integer k = 0; k < 8; k = k + 1)
        csr_write_word(12'h000 + k*4, command[k*32 +: 32]);
      csr_write_word(12'h020, 32'd1);
    end
  endtask

  initial begin
    csr_valid = 1'b0; csr_write = 1'b0; csr_addr = '0; csr_wdata = '0;
    video_seen = 0;
    page1_seen = 0;
    verify_page1 = 1'b0;
    fill_cmd = '0;
    fill_cmd[2:0] = 3'd1;       // SOLID_FILL
    fill_cmd[12:11] = 2'd0;     // RGB565
    fill_cmd[79:48] = 32'h0100;
    fill_cmd[95:80] = 16'd2;
    fill_cmd[111:96] = 16'd1;
    fill_cmd[143:128] = 16'd8;
    fill_cmd[175:144] = 32'h0000_F800;

    // Preload page 0 for the display reader.  The generated hierarchy is the
    // documented simulation-only memory replacement point.
    for (integer k = 0; k < 8; k = k + 1)
      dut.g_mem_model.u_mem_model.mem[(32'h0100/2) + k] = 16'h1000 + k;
    for (integer k = 0; k < 8; k = k + 1)
      dut.g_mem_model.u_mem_model.mem[(32'h0200/2) + k] = 16'h2000 + k;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);
    submit_command(fill_cmd);

    guard = 0;
    while (command_completed_count == 0 && guard < 500) begin
      @(posedge clk);
      guard = guard + 1;
    end
    if (guard >= 500 || command_submit_count != 1 ||
        command_completed_count != 1)
      $fatal(1, "command path did not complete submit=%0d done=%0d",
             command_submit_count, command_completed_count);

    // Request page 1 and wait for a frame boundary commit.
    csr_write_word(12'h028, 32'd1);
    guard = 0;
    while (active_page != 1'b1 && guard < 500) begin
      @(posedge clk);
      guard = guard + 1;
    end
    if (guard >= 500 || page_flip_pending)
      $fatal(1, "page flip did not commit active=%b pending=%b",
             active_page, page_flip_pending);

    // active_page changes at vblank_start. The display captures the new base
    // one clock later. Align the checker to the following active-frame start
    // and require a valid sample at every DE position, so an underflow cannot
    // be hidden by concatenating valid pixels from two different frames.
    @(negedge clk);
    while (!dut.timing_frame_start)
      @(negedge clk);
    verify_page1 = 1'b1;

    guard = 0;
    while (page1_seen < H*V && guard < 500) begin
      @(posedge clk);
      guard = guard + 1;
    end
    if (guard >= 500)
      $fatal(1, "page 1 scanout did not produce a complete frame pixels=%0d",
             page1_seen);

    repeat (20) @(posedge clk);
    csr_read_word(12'h024, status_word);
    csr_read_word(12'h04c, display_errors_word);
    if (!clock_locked || !mem_init_done || mem_init_error ||
        !video_init_done || video_init_error || status_word[5] ||
        status_word[4] || display_underflow || system_error ||
        display_errors_word != 0)
      $fatal(1, "system status invalid lock=%b mem=%b/%b video=%b/%b status=%h display_errors=%0d",
             clock_locked, mem_init_done, mem_init_error, video_init_done,
             video_init_error, status_word, display_errors_word);
    if (video_seen == 0 || page1_seen != H*V)
      $fatal(1, "system produced no active video samples");

    $display("TB_C2_RENDERER_SYSTEM_PASS video=%0d page1=%0d done=%0d active_page=%b underflow=%b",
             video_seen, page1_seen, command_completed_count, active_page,
             display_underflow);
    $finish;
  end
endmodule
