`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_ext_mem_adapter_blackbox
// -----------------------------------------------------------------------------
// Legacy reserved replacement point for a native Efinix DDR3 wrapper.
// The generated IP must translate byte-addressed req_len=beats-1 transactions
// into its native command/data interface and return ordered read beats with
// rsp_last.  Burst writes use the explicit wr_* stream and produce one later
// wr_rsp_* completion (AXI B equivalent); req_wdata is retained only for
// legacy single-beat adapters.  This module is intentionally empty;
// it is never selected by the current system top: USE_EXT_MEM_IP now selects
// c2_mem_to_axi4_adapter and exposes a real AXI4 Full master.  Keep this anchor
// only if a future DDR3 IP exposes a non-AXI native interface.
// -----------------------------------------------------------------------------
(* black_box = "true" *)
module c2_ext_mem_adapter_blackbox #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 16,
    parameter int LEN_W  = 16
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     req_valid,
    output logic                     req_ready,
    input  logic                     req_write,
    input  logic [ADDR_W-1:0]        req_addr,
    input  logic [LEN_W-1:0]         req_len,
    input  logic [DATA_W-1:0]        req_wdata,
    input  logic [(DATA_W/8)-1:0]    req_wstrb,
    input  logic                     wr_valid,
    output logic                     wr_ready,
    input  logic [DATA_W-1:0]        wr_data,
    input  logic [(DATA_W/8)-1:0]    wr_strb,
    input  logic                     wr_last,
    output logic                     wr_error,
    output logic                     wr_rsp_valid,
    input  logic                     wr_rsp_ready,
    output logic                     wr_rsp_error,
    output logic                     rsp_valid,
    input  logic                     rsp_ready,
    output logic [DATA_W-1:0]        rsp_rdata,
    output logic                     rsp_last,
    output logic                     rsp_error,
    output logic [31:0]              read_count,
    output logic [31:0]              write_count,
    output logic [31:0]              write_response_count,
    output logic [31:0]              response_count,
    output logic                     init_done,
    output logic                     init_error
);
endmodule
