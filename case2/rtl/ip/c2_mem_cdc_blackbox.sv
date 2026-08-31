`timescale 1ns/1ps

// Reserved CDC/async-FIFO bridge for the read-only display memory master. Use
// this when the generated PLL gives the display reader a different clock from
// the system/DDR clock. The bridge must preserve request ordering and hold
// every response beat (including rsp_last) across the clock boundary. The
// legacy req_write/wdata fields remain in the generic descriptor shape, but
// this port list has no burst write-data or write-response channel and is not
// a general renderer-write CDC replacement point.
(* black_box = "true" *)
module c2_mem_cdc_blackbox #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 16,
    parameter int LEN_W  = 16
) (
    input  logic                     src_clk,
    input  logic                     src_rst_n,
    input  logic                     src_req_valid,
    output logic                     src_req_ready,
    input  logic                     src_req_write,
    input  logic [ADDR_W-1:0]        src_req_addr,
    input  logic [LEN_W-1:0]         src_req_len,
    input  logic [DATA_W-1:0]        src_req_wdata,
    input  logic [(DATA_W/8)-1:0]    src_req_wstrb,
    output logic                     src_rsp_valid,
    input  logic                     src_rsp_ready,
    output logic [DATA_W-1:0]        src_rsp_rdata,
    output logic                     src_rsp_last,
    output logic                     src_rsp_error,

    input  logic                     dst_clk,
    input  logic                     dst_rst_n,
    output logic                     dst_req_valid,
    input  logic                     dst_req_ready,
    output logic                     dst_req_write,
    output logic [ADDR_W-1:0]        dst_req_addr,
    output logic [LEN_W-1:0]         dst_req_len,
    output logic [DATA_W-1:0]        dst_req_wdata,
    output logic [(DATA_W/8)-1:0]    dst_req_wstrb,
    input  logic                     dst_rsp_valid,
    output logic                     dst_rsp_ready,
    input  logic [DATA_W-1:0]        dst_rsp_rdata,
    input  logic                     dst_rsp_last,
    input  logic                     dst_rsp_error
);
endmodule
