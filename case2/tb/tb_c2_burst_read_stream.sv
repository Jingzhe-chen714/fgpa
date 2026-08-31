`timescale 1ns/1ps

module tb_c2_burst_read_stream;
  localparam int DATA_W = 16;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic start;
  logic [31:0] start_addr;
  logic [15:0] start_beats;
  logic busy, done, error;

  logic req_valid, req_ready, req_write;
  logic [31:0] req_addr;
  logic [15:0] req_len;
  logic [15:0] req_wdata;
  logic [1:0]  req_wstrb;
  logic rsp_valid, rsp_ready;
  logic [15:0] rsp_rdata;
  logic rsp_last, rsp_error;

  logic out_valid, out_ready, out_last;
  logic [15:0] out_data, out_index;
  logic [31:0] request_count, response_count, error_count;
  logic rsp_gate;
  integer cycle_count;
  integer seen;
  integer accepted_requests;
  reg [15:0] expected [0:7];

  c2_burst_read_stream #(.ADDR_W(32), .DATA_W(DATA_W), .LEN_W(16)) u_stream (
    .clk, .rst_n, .start, .start_addr, .start_beats, .busy, .done, .error,
    .req_valid, .req_ready, .req_write, .req_addr, .req_len,
    .req_wdata, .req_wstrb,
    .rsp_valid, .rsp_ready, .rsp_rdata, .rsp_last, .rsp_error,
    .out_valid, .out_ready, .out_data, .out_last, .out_index,
    .request_count, .response_count, .error_count
  );

  logic model_req_valid, model_req_ready;
  logic model_rsp_valid, model_rsp_ready;
  assign model_req_valid = req_valid;
  assign req_ready       = model_req_ready;
  // Gate both sides of the response handshake.  The model must not advance
  // while the stream believes the response is stalled.
  assign rsp_valid       = model_rsp_valid && rsp_gate;
  assign model_rsp_ready = rsp_ready && rsp_gate;

  render_burst_mem_model #(
    .ADDR_W(32), .DATA_W(DATA_W), .LEN_W(16),
    .MEM_BYTES(4096), .READ_LATENCY(2)
  ) u_mem (
    .clk, .rst_n,
    .req_valid(model_req_valid), .req_ready(model_req_ready),
    .req_write(req_write), .req_addr(req_addr), .req_len(req_len),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(model_rsp_valid), .rsp_ready(model_rsp_ready),
    .rsp_rdata(rsp_rdata), .rsp_last(rsp_last), .rsp_error(rsp_error),
    .read_count(), .write_count(), .error_count()
  );

  always @(posedge clk) begin
    if (!rst_n) begin
      cycle_count <= 0;
      rsp_gate <= 1'b1;
    end else begin
      cycle_count <= cycle_count + 1;
      rsp_gate <= ((cycle_count % 4) != 2);
    end
  end

  always_comb begin
    out_ready = rst_n && ((cycle_count % 3) != 1);
  end

  always @(negedge clk) begin
    if (rst_n && req_valid && req_ready) begin
      accepted_requests = accepted_requests + 1;
      if (accepted_requests != 1 || req_addr !== 32'h0100 || req_len !== 16'd7 ||
          req_write !== 1'b0)
        $fatal(1, "burst request mismatch n=%0d addr=%h len=%0d write=%b",
               accepted_requests, req_addr, req_len, req_write);
    end
    if (rst_n && out_valid && out_ready) begin
      if (seen >= 8 || out_data !== expected[seen] || out_index !== seen[15:0])
        $fatal(1, "burst stream mismatch n=%0d data=%h index=%0d last=%b",
               seen, out_data, out_index, out_last);
      if (out_last !== (seen == 7))
        $fatal(1, "burst last mismatch n=%0d last=%b", seen, out_last);
      seen = seen + 1;
    end
  end

  task automatic launch(input logic [31:0] addr, input logic [15:0] beats);
    begin
      @(negedge clk);
      start_addr = addr;
      start_beats = beats;
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task automatic wait_done(input logic expect_error);
    integer guard;
    begin
      guard = 0;
      while (!done && guard < 1000) begin
        @(negedge clk);
        guard = guard + 1;
      end
      if (guard >= 1000)
        $fatal(1, "burst stream timeout busy=%b seen=%0d", busy, seen);
      if (error !== expect_error)
        $fatal(1, "burst stream error=%b expected=%b", error, expect_error);
    end
  endtask

  initial begin
    start = 1'b0;
    start_addr = '0;
    start_beats = '0;
    seen = 0;
    accepted_requests = 0;
    expected[0] = 16'h1000;
    expected[1] = 16'h1001;
    expected[2] = 16'h1002;
    expected[3] = 16'h1003;
    expected[4] = 16'h1004;
    expected[5] = 16'h1005;
    expected[6] = 16'h1006;
    expected[7] = 16'h1007;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    for (integer k = 0; k < 8; k = k + 1)
      u_mem.mem[(32'h0100 / 2) + k] = expected[k];

    launch(32'h0100, 16'd8);
    wait_done(1'b0);
    if (seen != 8 || request_count != 1 || response_count != 8 ||
        error_count != 0 || busy)
      $fatal(1, "burst counters seen=%0d req=%0d rsp=%0d err=%0d busy=%b",
             seen, request_count, response_count, error_count, busy);

    // Zero beats is rejected without emitting a memory request.
    launch(32'h0100, 16'd0);
    wait_done(1'b1);
    if (request_count != 1)
      $fatal(1, "invalid burst emitted a request");

    $display("TB_C2_BURST_READ_STREAM_PASS seen=%0d req=%0d rsp=%0d",
             seen, request_count, response_count);
    $finish;
  end
endmodule
