`timescale 1ns/1ps
module tb_c2_sync_fifo;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0;
  logic s_valid, s_ready;
  logic [7:0] s_data;
  logic m_valid, m_ready;
  logic [7:0] m_data;
  logic [2:0] count;
  logic full, empty, overflow, underflow;

  c2_sync_fifo #(.DATA_W(8), .DEPTH(4)) dut (
    .clk, .rst_n, .s_valid, .s_ready, .s_data,
    .m_valid, .m_ready, .m_data, .count, .full, .empty,
    .overflow, .underflow
  );

  task automatic push(input logic [7:0] v);
    begin
      @(negedge clk);
      while (!s_ready) @(negedge clk);
      s_data = v; s_valid = 1'b1;
      @(posedge clk);
      @(negedge clk); s_valid = 1'b0;
    end
  endtask

  task automatic pop_expect(input logic [7:0] v);
    begin
      @(negedge clk);
      while (!m_valid) @(negedge clk);
      assert (m_data == v) else $fatal(1, "FIFO expected %0h got %0h", v, m_data);
      m_ready = 1'b1;
      @(posedge clk);
      @(negedge clk); m_ready = 1'b0;
    end
  endtask

  initial begin
    s_valid = 0; s_data = 0; m_ready = 0;
    repeat (2) @(negedge clk);
    rst_n = 1;
    push(8'h11); push(8'h22); push(8'h33); push(8'h44);
    assert (full) else $fatal(1, "FIFO did not become full");
    // Full FIFO must accept a simultaneous pop/push without dropping data.
    @(negedge clk);
    s_data = 8'h55; s_valid = 1'b1; m_ready = 1'b1;
    #1;
    assert (s_ready && m_valid && m_data == 8'h11)
      else $fatal(1, "full simultaneous pop/push handshake failed");
    @(posedge clk);
    @(negedge clk); s_valid = 1'b0; m_ready = 1'b0;
    pop_expect(8'h22);
    pop_expect(8'h33);
    pop_expect(8'h44);
    pop_expect(8'h55);
    assert (empty) else $fatal(1, "FIFO did not become empty");
    $display("TB_C2_SYNC_FIFO_PASS");
    $finish;
  end
endmodule
