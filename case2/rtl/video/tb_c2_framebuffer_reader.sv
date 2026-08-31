`timescale 1ns/1ps

// Self-checking scanout-reader test.  The response/request stalls are applied
// to both sides of the abstract handshake, so the memory model never accepts
// a transaction that the reader did not observe as accepted.
module tb_c2_framebuffer_reader;
  localparam int DATA_W = 16;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;

  logic start, start_ready;
  logic [31:0] base_addr;
  logic [15:0] stride_bytes, width, height;

  logic mem_req_valid, mem_req_ready, mem_req_write;
  logic [31:0] mem_req_addr;
  logic [15:0] mem_req_len, mem_req_wdata;
  logic [1:0]  mem_req_wstrb;
  logic mem_rsp_valid, mem_rsp_ready;
  logic [15:0] mem_rsp_rdata;
  logic mem_rsp_last, mem_rsp_error;

  logic pixel_valid, pixel_ready;
  logic [15:0] pixel_data;
  logic [15:0] pixel_x, pixel_y;
  logic pixel_last;
  logic busy, done, error;
  logic [2:0] error_code;
  logic [31:0] request_count, read_count, pixel_count, error_count;

  logic req_gate, rsp_gate;
  logic model_req_valid, model_req_ready;
  logic model_rsp_valid, model_rsp_ready;
  integer cycle_count;

  c2_framebuffer_reader #(.ADDR_W(32), .DATA_W(16), .COORD_W(16)) u_reader (
    .clk, .rst_n,
    .start, .start_ready, .base_addr, .stride_bytes, .width, .height,
    .mem_req_valid, .mem_req_ready, .mem_req_write, .mem_req_addr,
    .mem_req_len, .mem_req_wdata, .mem_req_wstrb,
    .mem_rsp_valid, .mem_rsp_ready, .mem_rsp_rdata, .mem_rsp_last,
    .mem_rsp_error,
    .pixel_valid, .pixel_ready, .pixel_data, .pixel_x, .pixel_y,
    .pixel_last, .busy, .done, .error, .error_code,
    .request_count, .read_count, .pixel_count, .error_count
  );

  // Apply back-pressure without violating ready/valid semantics at either
  // side of the behavioral memory.
  assign model_req_valid = mem_req_valid && req_gate;
  assign mem_req_ready   = model_req_ready && req_gate;
  assign mem_rsp_valid   = model_rsp_valid && rsp_gate;
  assign model_rsp_ready = mem_rsp_ready && rsp_gate;

  render_mem_model #(.MEM_BYTES(2048), .READ_LATENCY(2)) u_mem (
    .clk, .rst_n,
    .req_valid(model_req_valid), .req_ready(model_req_ready),
    .req_write(mem_req_write), .req_addr(mem_req_addr), .req_len(mem_req_len),
    .req_wdata(mem_req_wdata), .req_wstrb(mem_req_wstrb),
    .rsp_valid(model_rsp_valid), .rsp_ready(model_rsp_ready),
    .rsp_rdata(mem_rsp_rdata), .rsp_last(mem_rsp_last),
    .rsp_error(mem_rsp_error), .read_count(), .write_count(), .error_count()
  );

  always @(posedge clk) begin
    if (!rst_n) begin
      cycle_count <= 0;
      req_gate <= 1'b1;
      rsp_gate <= 1'b1;
    end else begin
      cycle_count <= cycle_count + 1;
      req_gate <= ((cycle_count % 4) != 1);
      rsp_gate <= ((cycle_count % 5) != 2);
    end
  end

  // The output sink stalls every fourth cycle.  It is a pure function of the
  // already-registered cycle counter, so it cannot race the DUT at a clock
  // edge.
  always_comb pixel_ready = rst_n && ((cycle_count % 4) != 1);

  integer seen;
  reg [15:0] expected_data [0:5];
  reg [15:0] expected_x    [0:5];
  reg [15:0] expected_y    [0:5];
  initial begin
    expected_data[0] = 16'h001F; expected_x[0] = 0; expected_y[0] = 0;
    expected_data[1] = 16'h07E0; expected_x[1] = 1; expected_y[1] = 0;
    expected_data[2] = 16'hF800; expected_x[2] = 2; expected_y[2] = 0;
    expected_data[3] = 16'hFFFF; expected_x[3] = 0; expected_y[3] = 1;
    expected_data[4] = 16'h8410; expected_x[4] = 1; expected_y[4] = 1;
    expected_data[5] = 16'h0000; expected_x[5] = 2; expected_y[5] = 1;
    seen = 0;
  end

  always @(negedge clk) begin
    if (rst_n && pixel_valid && pixel_ready) begin
      if (seen >= 6 || pixel_data !== expected_data[seen] ||
          pixel_x !== expected_x[seen] || pixel_y !== expected_y[seen]) begin
        $fatal(1, "reader stream mismatch n=%0d data=%h x=%0d y=%0d last=%0d",
               seen, pixel_data, pixel_x, pixel_y, pixel_last);
      end
      if (pixel_last !== (seen == 5))
        $fatal(1, "reader last flag mismatch n=%0d last=%0d", seen, pixel_last);
      seen = seen + 1;
    end
  end

  task automatic launch_scan(input [31:0] addr, input [15:0] stride,
                             input [15:0] w, input [15:0] h);
    begin
      @(negedge clk);
      base_addr = addr;
      stride_bytes = stride;
      width = w;
      height = h;
      start = 1'b1;
      while (!start_ready)
        @(negedge clk);
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task automatic wait_done(input bit expect_error);
    integer guard;
    begin
      guard = 0;
      while (!done && guard < 1000) begin
        @(negedge clk);
        guard = guard + 1;
      end
      if (guard >= 1000)
        $fatal(1, "reader timeout busy=%0d state=%0d", busy, u_reader.state);
      if (error !== expect_error)
        $fatal(1, "reader error=%0d expected=%0d code=%0d", error,
               expect_error, error_code);
    end
  endtask

  initial begin
    start = 1'b0;
    base_addr = '0;
    stride_bytes = '0;
    width = '0;
    height = '0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    // 3x2 rectangle at 0x100, two bytes of padding at each row end.
    u_mem.mem[16'h0100/2] = 16'h001F;
    u_mem.mem[16'h0102/2] = 16'h07E0;
    u_mem.mem[16'h0104/2] = 16'hF800;
    u_mem.mem[16'h0108/2] = 16'hFFFF;
    u_mem.mem[16'h010A/2] = 16'h8410;
    u_mem.mem[16'h010C/2] = 16'h0000;

    launch_scan(32'h0100, 16'd8, 16'd3, 16'd2);
    wait_done(1'b0);
    if (seen != 6 || request_count != 6 || read_count != 6 ||
        pixel_count != 6 || error_count != 0)
      $fatal(1, "reader counters seen=%0d req=%0d rd=%0d pix=%0d err=%0d",
             seen, request_count, read_count, pixel_count, error_count);

    // Invalid geometry is rejected synchronously and produces a done+error
    // pulse without issuing a memory request.
    launch_scan(32'h0200, 16'd4, 16'd0, 16'd1);
    wait_done(1'b1);
    if (request_count != 6 || error_code != 3'd1)
      $fatal(1, "invalid scan was not rejected cleanly");

    $display("TB_C2_FRAMEBUFFER_READER_PASS seen=%0d req=%0d", seen,
             request_count);
    $finish;
  end
endmodule
