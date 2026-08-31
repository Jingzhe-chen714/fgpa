`timescale 1ns/1ps

// Legacy named anchor for a non-AXI Sapphire integration.  The current system
// top already instantiates c2_axi4lite_csr_adapter when USE_AXI4LITE_CSR=1, so
// this blackbox is not needed for the competition AXI4 configuration.
(* black_box = "true" *)
module c2_sapphire_csr_blackbox #(
    parameter int ADDR_W = 12
) (
    input  logic                 clk,
    input  logic                 rst_n,
    output logic                 csr_valid,
    output logic                 csr_write,
    output logic [ADDR_W-1:0]    csr_addr,
    output logic [31:0]          csr_wdata,
    input  logic [31:0]          csr_rdata,
    input  logic                 csr_ready,
    // AXI-Lite/APB pins are intentionally left as an integration-specific
    // port list in the generated IP; this declaration is a named anchor only.
    input  logic                 ip_bus_clk,
    input  logic                 ip_bus_reset_n
);
endmodule
