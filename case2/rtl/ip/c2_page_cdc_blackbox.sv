`timescale 1ns/1ps

// Reserved CDC bridge for page-flip request and status.  The generated
// implementation may use pulse synchronizers plus a small handshake register;
// the status fields must be sampled coherently in the CSR clock domain.
(* black_box = "true" *)
module c2_page_cdc_blackbox #(
    parameter int PAGE_W = 1
) (
    input  logic                 src_clk,
    input  logic                 src_rst_n,
    input  logic                 src_req_valid,
    output logic                 src_req_ready,
    input  logic [PAGE_W-1:0]    src_req_page,
    output logic [PAGE_W-1:0]    src_active_page,
    output logic [PAGE_W-1:0]    src_pending_page,
    output logic                 src_flip_pending,

    input  logic                 dst_clk,
    input  logic                 dst_rst_n,
    output logic                 dst_req_valid,
    input  logic                 dst_req_ready,
    output logic [PAGE_W-1:0]    dst_req_page,
    input  logic [PAGE_W-1:0]    dst_active_page,
    input  logic [PAGE_W-1:0]    dst_pending_page,
    input  logic                 dst_flip_pending
);
endmodule
