`timescale 1ns/1ps

module tb_c2_mem_arbiter_2m;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic display_priority;

  logic m0_req_valid, m0_req_ready, m0_req_write;
  logic [31:0] m0_req_addr;
  logic [15:0] m0_req_len, m0_req_wdata;
  logic [1:0] m0_req_wstrb;
  logic m0_rsp_valid, m0_rsp_ready;
  logic [15:0] m0_rsp_rdata;
  logic m0_rsp_last, m0_rsp_error;

  logic m1_req_valid, m1_req_ready, m1_req_write;
  logic [31:0] m1_req_addr;
  logic [15:0] m1_req_len, m1_req_wdata;
  logic [1:0] m1_req_wstrb;
  logic m1_rsp_valid, m1_rsp_ready;
  logic [15:0] m1_rsp_rdata;
  logic m1_rsp_last, m1_rsp_error;

  logic s_req_valid, s_req_ready, s_req_write;
  logic [31:0] s_req_addr;
  logic [15:0] s_req_len, s_req_wdata;
  logic [1:0] s_req_wstrb;
  logic s_rsp_valid, s_rsp_ready;
  logic [15:0] s_rsp_rdata;
  logic s_rsp_last, s_rsp_error;
  logic busy, owner_m1;
  logic [31:0] grant_count, read_count, write_count, response_count,
               orphan_response_count;

  c2_mem_arbiter_2m u_dut (
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

  logic [15:0] mem [0:31];
  logic slave_pending;
  logic [1:0] slave_delay;
  logic [15:0] slave_data;

  assign s_req_ready = !slave_pending;
  assign s_rsp_valid = slave_pending && (slave_delay == 0);
  assign s_rsp_rdata = slave_data;
  assign s_rsp_last  = s_rsp_valid;
  assign s_rsp_error = 1'b0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      slave_pending <= 1'b0;
      slave_delay   <= '0;
      slave_data    <= '0;
    end else begin
      if (s_rsp_valid && s_rsp_ready)
        slave_pending <= 1'b0;
      if (slave_pending && (slave_delay != 0))
        slave_delay <= slave_delay - 1'b1;

      if (s_req_valid && s_req_ready) begin
        if (s_req_write) begin
          mem[s_req_addr / 2] <= s_req_wdata;
        end else begin
          slave_data    <= mem[s_req_addr / 2];
          slave_delay   <= 2;
          slave_pending <= 1'b1;
        end
      end
    end
  end

  task automatic clear_m0;
    begin
      m0_req_valid = 1'b0; m0_req_write = 1'b0; m0_req_addr = '0;
      m0_req_len = '0; m0_req_wdata = '0; m0_req_wstrb = 2'b11;
    end
  endtask
  task automatic clear_m1;
    begin
      m1_req_valid = 1'b0; m1_req_write = 1'b0; m1_req_addr = '0;
      m1_req_len = '0; m1_req_wdata = '0; m1_req_wstrb = 2'b11;
    end
  endtask

  task automatic wait_m0_accept;
    begin
      #1;
      while (!m0_req_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      m0_req_valid = 1'b0;
    end
  endtask
  task automatic wait_m1_accept;
    begin
      #1;
      while (!m1_req_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      m1_req_valid = 1'b0;
    end
  endtask

  integer m0_seen, m1_seen;
  always @(negedge clk) begin
    if (rst_n && m0_rsp_valid && m0_rsp_ready) begin
      if (m0_rsp_rdata !== 16'h1111 && m0_seen == 0)
        $fatal(1, "m0 first response mismatch %h", m0_rsp_rdata);
      m0_seen = m0_seen + 1;
    end
    if (rst_n && m1_rsp_valid && m1_rsp_ready) begin
      if (m1_seen == 0 && m1_rsp_rdata !== 16'h2222)
        $fatal(1, "m1 first response mismatch %h", m1_rsp_rdata);
      if (m1_seen == 1 && m1_rsp_rdata !== 16'hABCD)
        $fatal(1, "m1 second response mismatch %h", m1_rsp_rdata);
      m1_seen = m1_seen + 1;
    end
  end

  initial begin
    clear_m0(); clear_m1();
    m0_rsp_ready = 1'b1;
    m1_rsp_ready = 1'b1;
    display_priority = 1'b1;
    m0_seen = 0; m1_seen = 0;
    mem[0] = 16'h1111;
    mem[1] = 16'h2222;
    mem[2] = 16'h0000;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // Both clients request a read. Display priority must grant client 1
    // first, then the round-robin pointer grants client 0.
    @(negedge clk);
    m0_req_valid = 1'b1; m0_req_write = 1'b0; m0_req_addr = 32'd0;
    m0_req_len = 0; m0_req_wdata = 0; m0_req_wstrb = 2'b11;
    m1_req_valid = 1'b1; m1_req_write = 1'b0; m1_req_addr = 32'd2;
    m1_req_len = 0; m1_req_wdata = 0; m1_req_wstrb = 2'b11;
    wait_m1_accept();
    wait_m0_accept();

    // A write from client 0 followed by a read from client 1 must observe the
    // written value, and writes must not create a phantom response.
    @(negedge clk);
    m0_req_valid = 1'b1; m0_req_write = 1'b1; m0_req_addr = 32'd4;
    m0_req_wdata = 16'hABCD; m0_req_len = 0; m0_req_wstrb = 2'b11;
    wait_m0_accept();
    @(negedge clk);
    m1_req_valid = 1'b1; m1_req_write = 1'b0; m1_req_addr = 32'd4;
    m1_req_len = 0; m1_req_wdata = 0; m1_req_wstrb = 2'b11;
    wait_m1_accept();

    repeat (8) @(posedge clk);
    if (m0_seen != 1 || m1_seen != 2 || grant_count != 4 ||
        read_count != 3 || write_count != 1 || response_count != 3 ||
        orphan_response_count != 0)
      $fatal(1, "arbiter counters m0=%0d m1=%0d grant=%0d rd=%0d wr=%0d rsp=%0d orphan=%0d",
             m0_seen, m1_seen, grant_count, read_count, write_count,
             response_count, orphan_response_count);

    // Hold a response at the client boundary and verify the arbiter keeps it
    // stable until ready is restored.
    @(negedge clk);
    m0_rsp_ready = 1'b0;
    m0_req_valid = 1'b1; m0_req_write = 1'b0; m0_req_addr = 32'd0;
    m0_req_len = 0; m0_req_wdata = 0; m0_req_wstrb = 2'b11;
    wait_m0_accept();
    repeat (3) @(posedge clk);
    if (!m0_rsp_valid || m0_rsp_rdata !== 16'h1111)
      $fatal(1, "arbiter did not hold stalled response");
    @(negedge clk);
    m0_rsp_ready = 1'b1;
    repeat (4) @(posedge clk);
    if (response_count != 4)
      $fatal(1, "stalled response was not eventually consumed");

    $display("TB_C2_MEM_ARBITER_PASS grants=%0d responses=%0d", grant_count,
             response_count);
    $finish;
  end
endmodule
