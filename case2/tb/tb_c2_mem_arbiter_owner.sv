`timescale 1ns/1ps

// Owner-hold regression: a write descriptor must retain the shared owner for
// every write-data beat while a competing read waits; after wr_last the read
// is granted and its complete response burst is routed to master 1.
module tb_c2_mem_arbiter_owner;
  localparam int DATA_W = 16;
  localparam int BYTE_LANES = 2;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic display_priority = 1'b1;

  logic m0_req_valid, m0_req_ready, m0_req_write;
  logic [31:0] m0_req_addr;
  logic [15:0] m0_req_len, m0_req_wdata;
  logic [1:0] m0_req_wstrb;
  logic m0_wr_valid, m0_wr_ready;
  logic [15:0] m0_wr_data;
  logic [1:0] m0_wr_strb;
  logic m0_wr_last, m0_wr_error;
  logic m0_wr_rsp_valid, m0_wr_rsp_ready, m0_wr_rsp_error;
  logic m0_rsp_valid, m0_rsp_ready;
  logic [15:0] m0_rsp_rdata;
  logic m0_rsp_last, m0_rsp_error;

  logic m1_req_valid, m1_req_ready, m1_req_write;
  logic [31:0] m1_req_addr;
  logic [15:0] m1_req_len, m1_req_wdata;
  logic [1:0] m1_req_wstrb;
  logic m1_wr_valid, m1_wr_ready;
  logic [15:0] m1_wr_data;
  logic [1:0] m1_wr_strb;
  logic m1_wr_last, m1_wr_error;
  logic m1_wr_rsp_valid, m1_wr_rsp_ready, m1_wr_rsp_error;
  logic m1_rsp_valid, m1_rsp_ready;
  logic [15:0] m1_rsp_rdata;
  logic m1_rsp_last, m1_rsp_error;

  logic s_req_valid, s_req_ready, s_req_write;
  logic [31:0] s_req_addr;
  logic [15:0] s_req_len, s_req_wdata;
  logic [1:0] s_req_wstrb;
  logic s_wr_valid, s_wr_ready;
  logic [15:0] s_wr_data;
  logic [1:0] s_wr_strb;
  logic s_wr_last, s_wr_error;
  logic s_wr_rsp_valid, s_wr_rsp_ready, s_wr_rsp_error;
  logic s_rsp_valid, s_rsp_ready;
  logic [15:0] s_rsp_rdata;
  logic s_rsp_last, s_rsp_error;
  logic wr_error;
  logic busy, owner_valid, owner_m1, owner_write;
  logic [31:0] grant_count, read_count, write_count, write_beat_count;
  logic [31:0] wr_error_count;
  logic [31:0] write_response_count, write_response_error_count;
  logic [31:0] response_count, response_protocol_error_count,
               orphan_response_count;
  logic [31:0] orphan_write_response_count;

  c2_mem_arbiter_2m_owner u_arb (
    .clk, .rst_n, .display_priority,
    .m0_req_valid, .m0_req_ready, .m0_req_write, .m0_req_addr,
    .m0_req_len, .m0_req_wdata, .m0_req_wstrb,
    .m0_wr_valid, .m0_wr_ready, .m0_wr_data, .m0_wr_strb, .m0_wr_last,
    .m0_wr_error,
    .m0_wr_rsp_valid, .m0_wr_rsp_ready, .m0_wr_rsp_error,
    .m0_rsp_valid, .m0_rsp_ready, .m0_rsp_rdata, .m0_rsp_last,
    .m0_rsp_error,
    .m1_req_valid, .m1_req_ready, .m1_req_write, .m1_req_addr,
    .m1_req_len, .m1_req_wdata, .m1_req_wstrb,
    .m1_wr_valid, .m1_wr_ready, .m1_wr_data, .m1_wr_strb, .m1_wr_last,
    .m1_wr_error,
    .m1_wr_rsp_valid, .m1_wr_rsp_ready, .m1_wr_rsp_error,
    .m1_rsp_valid, .m1_rsp_ready, .m1_rsp_rdata, .m1_rsp_last,
    .m1_rsp_error,
    .s_req_valid, .s_req_ready, .s_req_write, .s_req_addr, .s_req_len,
    .s_req_wdata, .s_req_wstrb,
    .s_wr_valid, .s_wr_ready, .s_wr_data, .s_wr_strb, .s_wr_last,
    .s_wr_error,
    .s_wr_rsp_valid, .s_wr_rsp_ready, .s_wr_rsp_error,
    .s_rsp_valid, .s_rsp_ready, .s_rsp_rdata, .s_rsp_last, .s_rsp_error,
    .busy, .owner_valid, .owner_m1, .owner_write, .write_protocol_error(wr_error),
    .write_protocol_error_count(wr_error_count),
    .grant_count, .read_count, .write_count, .write_beat_count,
    .write_response_count, .write_response_error_count,
    .response_count, .response_protocol_error_count, .orphan_response_count,
    .orphan_write_response_count
  );

  render_owner_mem_model #(.MEM_BYTES(1024), .READ_LATENCY(1)) u_mem (
    .clk, .rst_n,
    .req_valid(s_req_valid), .req_ready(s_req_ready), .req_write(s_req_write),
    .req_addr(s_req_addr), .req_len(s_req_len), .req_wdata(s_req_wdata),
    .req_wstrb(s_req_wstrb),
    .wr_valid(s_wr_valid), .wr_ready(s_wr_ready), .wr_data(s_wr_data),
    .wr_strb(s_wr_strb), .wr_last(s_wr_last), .wr_error(s_wr_error),
    .wr_rsp_valid(s_wr_rsp_valid), .wr_rsp_ready(s_wr_rsp_ready),
    .wr_rsp_error(s_wr_rsp_error),
    .rsp_valid(s_rsp_valid), .rsp_ready(s_rsp_ready), .rsp_rdata(s_rsp_rdata),
    .rsp_last(s_rsp_last), .rsp_error(s_rsp_error), .descriptor_count(),
    .read_count(), .write_count(), .write_beat_count(),
    .write_response_count(), .response_count(),
    .error_count()
  );

  integer m1_seen;
  integer m0_write_seen;
  integer m0_error_seen;
  always @(posedge clk) begin
    if (rst_n) begin
      if (m0_wr_valid && m0_wr_ready) begin
        m0_write_seen = m0_write_seen + 1;
        if (m0_write_seen == 4 && !m0_wr_last)
          $fatal(1, "m0 final write beat missing last");
      end
      if (m0_wr_error)
        m0_error_seen = m0_error_seen + 1;
      if (m1_rsp_valid && m1_rsp_ready) begin
        case (m1_seen)
          0: if (m1_rsp_rdata !== 16'hA100 || m1_rsp_last) $fatal(1, "m1 beat0");
          1: if (m1_rsp_rdata !== 16'hA101 || m1_rsp_last) $fatal(1, "m1 beat1");
          2: if (m1_rsp_rdata !== 16'hA102 || !m1_rsp_last) $fatal(1, "m1 beat2");
          default: $fatal(1, "m1 extra response");
        endcase
        m1_seen = m1_seen + 1;
      end
    end
  end

  task automatic issue_m0_write;
    integer i;
    begin
      @(negedge clk);
      m0_req_valid = 1'b1;
      while (!(m0_req_valid && m0_req_ready)) @(posedge clk);
      @(negedge clk);
      m0_req_valid = 1'b0;
      m0_wr_valid = 1'b1;
      for (i = 0; i < 4; i = i + 1) begin
        m0_wr_data = 16'hB000 + i;
        m0_wr_last = (i == 3);
        while (!(m0_wr_valid && m0_wr_ready)) @(posedge clk);
        @(negedge clk);
      end
      m0_wr_valid = 1'b0;
      m0_wr_last = 1'b0;
    end
  endtask

  task automatic issue_m1_read;
    begin
      // Assert the competing request only after master 0 owns the write-data
      // channel.  This is the condition the regression is intended to prove:
      // descriptor arbitration must stay closed until all four write beats
      // have completed.
      wait (owner_valid && owner_write && !owner_m1);
      @(negedge clk);
      m1_req_valid = 1'b1;
      while (!(m1_req_valid && m1_req_ready)) @(posedge clk);
      @(negedge clk);
      m1_req_valid = 1'b0;
    end
  endtask

  task automatic issue_m0_one_beat(
    input logic [31:0] addr,
    input logic [15:0] advertised_len,
    input logic [15:0] data,
    input logic        last
  );
    begin
      @(negedge clk);
      m0_req_addr = addr;
      m0_req_len = advertised_len;
      m0_req_valid = 1'b1;
      while (!(m0_req_valid && m0_req_ready)) @(posedge clk);
      @(negedge clk);
      m0_req_valid = 1'b0;
      m0_wr_data = data;
      m0_wr_last = last;
      m0_wr_valid = 1'b1;
      while (!(m0_wr_valid && m0_wr_ready)) @(posedge clk);
      @(negedge clk);
      m0_wr_valid = 1'b0;
      m0_wr_last = 1'b0;
    end
  endtask

  initial begin
    m0_req_valid = 1'b0; m0_req_write = 1'b1; m0_req_addr = 32'h20;
    m0_req_len = 16'd3; m0_req_wdata = '0; m0_req_wstrb = 2'b11;
    m0_wr_valid = 1'b0; m0_wr_data = '0; m0_wr_strb = 2'b11; m0_wr_last = 1'b0;
    m1_req_valid = 1'b0; m1_req_write = 1'b0; m1_req_addr = 32'h100;
    m1_req_len = 16'd2; m1_req_wdata = '0; m1_req_wstrb = 2'b11;
    m1_wr_valid = 1'b0; m1_wr_data = '0; m1_wr_strb = 2'b11; m1_wr_last = 1'b0;
    m0_rsp_ready = 1'b1; m1_rsp_ready = 1'b1;
    m0_wr_rsp_ready = 1'b1; m1_wr_rsp_ready = 1'b1;
    m1_seen = 0; m0_write_seen = 0; m0_error_seen = 0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    u_mem.mem[16'h100/2] = 16'hA100;
    u_mem.mem[16'h102/2] = 16'hA101;
    u_mem.mem[16'h104/2] = 16'hA102;

    // Master 0 acquires the write owner first.  issue_m1_read then raises a
    // display-priority request while the four-beat data stream is active.
    fork
      issue_m0_write();
      issue_m1_read();
    join

    repeat (10) @(posedge clk);
    if (m0_write_seen != 4 || m1_seen != 3 || grant_count != 2 ||
        write_count != 1 || read_count != 1 || write_beat_count != 4 ||
        write_response_count != 1 || response_count != 3 || busy ||
        wr_error || wr_error_count != 0 || write_response_error_count != 0)
      $fatal(1, "owner arbiter mismatch w=%0d r=%0d grants=%0d writes=%0d reads=%0d beats=%0d rsp=%0d busy=%b err=%b",
             m0_write_seen, m1_seen, grant_count, write_count, read_count,
             write_beat_count, response_count, busy, wr_error);

    if (u_mem.mem[16'h20/2] !== 16'hB000 ||
        u_mem.mem[16'h22/2] !== 16'hB001 ||
        u_mem.mem[16'h24/2] !== 16'hB002 ||
        u_mem.mem[16'h26/2] !== 16'hB003)
      $fatal(1, "owner write data did not reach memory");

    // An out-of-range access on the first beat of an advertised three-beat
    // write is terminal.  Both the model and the arbiter must release their
    // owner, report one write error, and accept a later valid descriptor.
    issue_m0_one_beat(32'h0000_0400, 16'd2, 16'hE001, 1'b0);
    repeat (2) @(posedge clk);
    if (busy || owner_valid || m0_error_seen != 1 || wr_error_count != 1 ||
        write_response_error_count != 1)
      $fatal(1, "write error did not terminate owner busy=%b owner=%b seen=%0d count=%0d",
             busy, owner_valid, m0_error_seen, wr_error_count);

    issue_m0_one_beat(32'h0000_0030, 16'd0, 16'hD00D, 1'b1);
    repeat (2) @(posedge clk);
    if (busy || u_mem.mem[16'h30/2] !== 16'hD00D ||
        grant_count != 4 || write_count != 3 || write_beat_count != 6 ||
        write_response_count != 3)
      $fatal(1, "owner failed to recover after write error grants=%0d writes=%0d beats=%0d",
             grant_count, write_count, write_beat_count);

    $display("TB_C2_MEM_ARBITER_OWNER_PASS writes=%0d reads=%0d rsp=%0d recovered=1",
             write_beat_count, read_count, response_count);
    $finish;
  end
endmodule
