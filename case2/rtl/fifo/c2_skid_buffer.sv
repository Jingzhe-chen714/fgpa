`timescale 1ns/1ps

// One-entry elastic buffer. Useful at an abstract memory or pixel boundary to
// isolate a producer from a one-cycle ready deassertion.
module c2_skid_buffer #(
  parameter int DATA_W = 32
) (
  input  logic              clk,
  input  logic              rst_n,
  input  logic              s_valid,
  output logic              s_ready,
  input  logic [DATA_W-1:0] s_data,
  output logic              m_valid,
  input  logic              m_ready,
  output logic [DATA_W-1:0] m_data
);
  logic full_i;
  logic [DATA_W-1:0] data_i;

  assign s_ready = !full_i || m_ready;
  assign m_valid = full_i;
  assign m_data  = data_i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      full_i <= 1'b0;
      data_i <= '0;
    end else if (s_ready) begin
      full_i <= s_valid;
      if (s_valid)
        data_i <= s_data;
    end
  end
endmodule
