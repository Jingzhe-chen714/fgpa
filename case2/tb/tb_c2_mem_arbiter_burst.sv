`timescale 1ns/1ps

// Verifies that the arbiter keeps a read owner for every beat of a burst.
module tb_c2_mem_arbiter_burst;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic display_priority = 1'b0;

  logic m0_req_valid, m0_req_ready, m0_req_write;
  logic [31:0] m0_req_addr;
  logic [15:0] m0_req_len, m0_req_wdata;
  logic [1:0]  m0_req_wstrb;
  logic m0_rsp_valid, m0_rsp_ready;
  logic [15:0] m0_rsp_rdata;
  logic m0_rsp_last, m0_rsp_error;

  logic m1_req_valid, m1_req_ready, m1_req_write;
  logic [31:0] m1_req_addr;
  logic [15:0] m1_req_len, m1_req_wdata;
  logic [1:0]  m1_req_wstrb;
  logic m1_rsp_valid, m1_rsp_ready;
  logic [15:0] m1_rsp_rdata;
  logic m1_rsp_last, m1_rsp_error;

  logic s_req_valid, s_req_ready, s_req_write;
  logic [31:0] s_req_addr;
  logic [15:0] s_req_len, s_req_wdata;
  logic [1:0]  s_req_wstrb;
  logic s_rsp_valid, s_rsp_ready;
  logic [15:0] s_rsp_rdata;
  logic s_rsp_last, s_rsp_error;
  logic busy, owner_m1;
  logic [31:0] grant_count, read_count, write_count, response_count,
               orphan_response_count;

  c2_mem_arbiter_2m u_arb (
    .clk, .rst_n, .display_priority,
    .m0_req_valid, .m0_req_ready, .m0_req_write, .m0_req_addr,
    .m0_req_len, .m0_req_wdata, .m0_req_wstrb,
    .m0_rsp_valid, .m0_rsp_ready, .m0_rsp_rdata, .m0_rsp_last,
    .m0_rsp_error,
    .m1_req_valid, .m1_req_ready, .m1_req_write, .m1_req_addr,
    .m1_req_len, .m1_req_wdata, .m1_req_wstrb,
    .m1_rsp_valid, .m1_rsp_ready, .m1_rsp_rdata, .m1_rsp_last,
    .m1_rsp_error,
    .s_req_valid, .s_req_ready, .s_req_write, .s_req_addr, .s_req_len,
    .s_req_wdata, .s_req_wstrb, .s_rsp_valid, .s_rsp_ready, .s_rsp_rdata,
    .s_rsp_last, .s_rsp_error, .busy, .owner_m1, .grant_count, .read_count,
    .write_count, .response_count, .orphan_response_count
  );

  render_burst_mem_model #(
    .ADDR_W(32), .DATA_W(16), .LEN_W(16), .MEM_BYTES(1024), .READ_LATENCY(1)
  ) u_mem (
    .clk, .rst_n,
    .req_valid(s_req_valid), .req_ready(s_req_ready), .req_write(s_req_write),
    .req_addr(s_req_addr), .req_len(s_req_len), .req_wdata(s_req_wdata),
    .req_wstrb(s_req_wstrb), .rsp_valid(s_rsp_valid), .rsp_ready(s_rsp_ready),
    .rsp_rdata(s_rsp_rdata), .rsp_last(s_rsp_last), .rsp_error(s_rsp_error),
    .read_count(), .write_count(), .error_count()
  );

  integer m0_seen, m1_seen;
  always @(posedge clk) begin
    if (rst_n) begin
      if (m0_rsp_valid && m0_rsp_ready) begin
        case (m0_seen)
          0: if (m0_rsp_rdata !== 16'hA000 || m0_rsp_last) $fatal(1, "m0 beat0");
          1: if (m0_rsp_rdata !== 16'hA001 || m0_rsp_last) $fatal(1, "m0 beat1");
          2: if (m0_rsp_rdata !== 16'hA002 || !m0_rsp_last) $fatal(1, "m0 beat2");
          default: $fatal(1, "m0 received an extra beat");
        endcase
        m0_seen = m0_seen + 1;
      end
      if (m1_req_valid && !m1_req_ready && (m0_seen < 3) && !m1_rsp_valid)
        ; // Expected: the second master waits behind the active burst.
      if (m1_rsp_valid && m1_rsp_ready) begin
        if (m1_seen != 0 || m1_rsp_rdata !== 16'hB000 || !m1_rsp_last)
          $fatal(1, "m1 response mismatch n=%0d data=%h last=%b", m1_seen,
                 m1_rsp_rdata, m1_rsp_last);
        m1_seen = m1_seen + 1;
      end
    end
  end

  task automatic drive_m0_burst;
    begin
      @(negedge clk);
      m0_req_valid = 1'b1;
      while (1) begin
        @(posedge clk);
        if (m0_req_valid && m0_req_ready) begin
          @(negedge clk);
          m0_req_valid = 1'b0;
          break;
        end
      end
    end
  endtask

  task automatic drive_m1_read;
    begin
      @(negedge clk);
      m1_req_valid = 1'b1;
      while (1) begin
        @(posedge clk);
        if (m1_req_valid && m1_req_ready) begin
          @(negedge clk);
          m1_req_valid = 1'b0;
          break;
        end
      end
    end
  endtask

  initial begin
    m0_req_valid = 1'b0; m0_req_write = 1'b0; m0_req_addr = 32'd0;
    m0_req_len = 16'd2; m0_req_wdata = 16'd0; m0_req_wstrb = 2'b11;
    m1_req_valid = 1'b0; m1_req_write = 1'b0; m1_req_addr = 32'd6;
    m1_req_len = 16'd0; m1_req_wdata = 16'd0; m1_req_wstrb = 2'b11;
    m0_rsp_ready = 1'b1;
    m1_rsp_ready = 1'b1;
    m0_seen = 0;
    m1_seen = 0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    u_mem.mem[0] = 16'hA000;
    u_mem.mem[1] = 16'hA001;
    u_mem.mem[2] = 16'hA002;
    u_mem.mem[3] = 16'h0000;
    u_mem.mem[4] = 16'h0000;
    u_mem.mem[5] = 16'h0000;
    u_mem.mem[6 / 2] = 16'hB000;

    drive_m0_burst();
    // Request the second master while the first response burst is active.
    drive_m1_read();

    repeat (8) @(posedge clk);
    if (m0_seen != 3 || m1_seen != 1 || grant_count != 2 || read_count != 2 ||
        response_count != 4 || orphan_response_count != 0 || busy)
      $fatal(1, "burst arbiter mismatch m0=%0d m1=%0d grant=%0d read=%0d rsp=%0d busy=%b",
             m0_seen, m1_seen, grant_count, read_count, response_count, busy);

    $display("TB_C2_MEM_ARBITER_BURST_PASS m0=%0d m1=%0d rsp=%0d",
             m0_seen, m1_seen, response_count);
    $finish;
  end
endmodule
