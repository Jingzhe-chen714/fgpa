`timescale 1ns/1ps
module tb_c2_burst_planner;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0, start;
  logic [31:0] base_addr, stride_bytes, row_bytes;
  logic [15:0] rows;
  logic busy, done, error, req_valid, req_ready;
  logic [31:0] req_addr;
  logic [15:0] req_beats;
  logic req_row_last, req_frame_last;
  int n_req;
  int total_beats;

  c2_burst_planner #(.BEAT_BYTES(2), .MAX_BURST_BEATS(8), .LIMIT_4KB(1'b1)) dut (
    .clk, .rst_n, .start, .base_addr, .stride_bytes, .row_bytes, .rows,
    .busy, .done, .error, .req_valid, .req_ready, .req_addr, .req_beats,
    .req_row_last, .req_frame_last
  );

  initial begin
    start = 0; req_ready = 0; base_addr = 0; stride_bytes = 0; row_bytes = 0; rows = 0;
    repeat (2) @(negedge clk);
    rst_n = 1;
    // Two rows of 40 bytes: 16+16+8 beats per row.
    @(negedge clk);
    base_addr = 32'h0000_0100; stride_bytes = 32'd64; row_bytes = 32'd40; rows = 2; start = 1;
    @(negedge clk); start = 0;
    n_req = 0; total_beats = 0;
    while (!done) begin
      @(negedge clk);
      if (req_valid) begin
        n_req++;
        total_beats += req_beats;
        if (n_req == 1) begin
          $display("first burst addr=%h beats=%0d row_last=%b frame_last=%b", req_addr, req_beats, req_row_last, req_frame_last);
          if (req_addr != 32'h100 || req_beats != 8 || req_row_last)
            $fatal(1, "unexpected first burst addr/beats/last");
        end
        if ((n_req == 3) && !req_row_last)
          $fatal(1, "row boundary not reported");
        req_ready = 1'b1;
        @(negedge clk);
        req_ready = 1'b0;
      end
    end
    assert (n_req == 6 && total_beats == 40) else
      $fatal(1, "burst count/beat total mismatch n=%0d beats=%0d", n_req, total_beats);
    assert (!error) else $fatal(1, "unexpected planner error");
    $display("TB_C2_BURST_PLANNER_PASS");
    $finish;
  end
endmodule
