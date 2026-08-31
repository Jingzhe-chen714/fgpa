`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_axi4lite_csr_adapter
// -----------------------------------------------------------------------------
// AXI4-Lite slave front end for the renderer's board-independent CSR port.
//
// Design rules:
//   * AW and W are captured independently, in either order.
//   * There is one outstanding read and one outstanding write at most.
//   * The shared CSR port executes one request at a time; a complete write has
//     priority over a pending read.
//   * AXI B/R payloads remain registered and stable while back-pressured.
//   * The present renderer CSR contract is word-write only.  A write with a
//     partial WSTRB returns SLVERR and is not forwarded to the CSR port.
//
// The adapter intentionally contains no Efinix primitive.  It can be connected
// directly to a Sapphire AXI4-Lite master and to c2_csr_cmd_bridge.
// -----------------------------------------------------------------------------
module c2_axi4lite_csr_adapter #(
    parameter int ADDR_W = 12,
    parameter int DATA_W = 32
) (
    input  logic                      clk,
    input  logic                      rst_n,

    input  logic [ADDR_W-1:0]         s_axi_awaddr,
    input  logic [2:0]                s_axi_awprot,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,

    input  logic [DATA_W-1:0]         s_axi_wdata,
    input  logic [(DATA_W/8)-1:0]     s_axi_wstrb,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,

    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,

    input  logic [ADDR_W-1:0]         s_axi_araddr,
    input  logic [2:0]                s_axi_arprot,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,

    output logic [DATA_W-1:0]         s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    output logic                      csr_valid,
    output logic                      csr_write,
    output logic [ADDR_W-1:0]         csr_addr,
    output logic [DATA_W-1:0]         csr_wdata,
    input  logic [DATA_W-1:0]         csr_rdata,
    input  logic                      csr_ready
);

    localparam int STRB_W = DATA_W / 8;
    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    logic                 aw_pending_q;
    logic [ADDR_W-1:0]    awaddr_q;
    logic                 w_pending_q;
    logic [DATA_W-1:0]    wdata_q;
    logic [STRB_W-1:0]    wstrb_q;

    logic                 ar_pending_q;
    logic [ADDR_W-1:0]    araddr_q;

    logic                 csr_busy_q;
    logic                 csr_write_q;

    logic                 bvalid_q;
    logic [1:0]           bresp_q;
    logic                 rvalid_q;
    logic [DATA_W-1:0]    rdata_q;
    logic [1:0]           rresp_q;

    logic aw_fire;
    logic w_fire;
    logic ar_fire;
    logic b_fire;
    logic r_fire;
    logic csr_fire;

    // Keep each AXI request buffer occupied until the associated CSR access or
    // local error response is generated.  Consequently another request cannot
    // overwrite an in-flight transaction before B/R is accepted.
    always_comb begin
        s_axi_awready = rst_n && !aw_pending_q && !bvalid_q;
        s_axi_wready  = rst_n && !w_pending_q  && !bvalid_q;
        s_axi_arready = rst_n && !ar_pending_q && !rvalid_q;

        aw_fire = s_axi_awvalid && s_axi_awready;
        w_fire  = s_axi_wvalid  && s_axi_wready;
        ar_fire = s_axi_arvalid && s_axi_arready;
        b_fire  = bvalid_q && s_axi_bready;
        r_fire  = rvalid_q && s_axi_rready;

        s_axi_bvalid = bvalid_q;
        s_axi_bresp  = bresp_q;
        s_axi_rvalid = rvalid_q;
        s_axi_rdata  = rdata_q;
        s_axi_rresp  = rresp_q;

        csr_valid = csr_busy_q;
        csr_write = csr_write_q;
        csr_addr  = csr_write_q ? awaddr_q : araddr_q;
        csr_wdata = wdata_q;
        csr_fire  = csr_valid && csr_ready;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_pending_q <= 1'b0;
            awaddr_q     <= '0;
            w_pending_q  <= 1'b0;
            wdata_q      <= '0;
            wstrb_q      <= '0;
            ar_pending_q <= 1'b0;
            araddr_q     <= '0;
            csr_busy_q   <= 1'b0;
            csr_write_q  <= 1'b0;
            bvalid_q     <= 1'b0;
            bresp_q      <= AXI_RESP_OKAY;
            rvalid_q     <= 1'b0;
            rdata_q      <= '0;
            rresp_q      <= AXI_RESP_OKAY;
        end else begin
            if (aw_fire) begin
                aw_pending_q <= 1'b1;
                awaddr_q     <= s_axi_awaddr;
            end

            if (w_fire) begin
                w_pending_q <= 1'b1;
                wdata_q     <= s_axi_wdata;
                wstrb_q     <= s_axi_wstrb;
            end

            if (ar_fire) begin
                ar_pending_q <= 1'b1;
                araddr_q     <= s_axi_araddr;
            end

            if (b_fire)
                bvalid_q <= 1'b0;
            if (r_fire)
                rvalid_q <= 1'b0;

            if (csr_fire) begin
                csr_busy_q <= 1'b0;
                if (csr_write_q) begin
                    aw_pending_q <= 1'b0;
                    w_pending_q  <= 1'b0;
                    bvalid_q     <= 1'b1;
                    bresp_q      <= AXI_RESP_OKAY;
                end else begin
                    ar_pending_q <= 1'b0;
                    rvalid_q     <= 1'b1;
                    rdata_q      <= csr_rdata;
                    rresp_q      <= AXI_RESP_OKAY;
                end
            end

            // Start at most one CSR transfer.  A complete write wins when a
            // read and write become pending together.  The partial-write error
            // is generated locally and never asserts csr_valid.
            if (!csr_busy_q) begin
                if (aw_pending_q && w_pending_q && !bvalid_q) begin
                    if (&wstrb_q) begin
                        csr_busy_q  <= 1'b1;
                        csr_write_q <= 1'b1;
                    end else begin
                        aw_pending_q <= 1'b0;
                        w_pending_q  <= 1'b0;
                        bvalid_q     <= 1'b1;
                        bresp_q      <= AXI_RESP_SLVERR;
                    end
                end else if (ar_pending_q && !rvalid_q) begin
                    csr_busy_q  <= 1'b1;
                    csr_write_q <= 1'b0;
                end
            end
        end
    end

    // AXI protection attributes are accepted for interface completeness.  The
    // renderer register bank has no privilege/security distinction.
    logic unused_prot;
    assign unused_prot = ^{s_axi_awprot, s_axi_arprot};

`ifndef SYNTHESIS
    initial begin
        if (DATA_W != 32 || (DATA_W % 8) != 0 || ADDR_W < 3)
            $error("c2_axi4lite_csr_adapter: unsupported parameterization");
    end
`endif

endmodule
