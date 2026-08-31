`timescale 1ns/1ps

// Portable bridge from the MicroStyle tensor adapter's one-outstanding
// 64-bit request/response seam to a one-beat AXI4 128-bit master.
//
// Local contract
// --------------
// * A request transfers on mem_req_valid && mem_req_ready.
// * The request address must be 8-byte aligned.  Misaligned requests produce
//   one local error response and issue no AXI transfer.
// * Every accepted read OR write produces exactly one later response.  The
//   bridge holds response payload stable until mem_rsp_ready.
// * There is no cancel input: once accepted, a request is completed.  This
//   matches c1_r1_microstyle_tensor_adapter, which drains its outstanding
//   response during abort.
//
// AXI contract
// ------------
// * ARLEN/AWLEN=0, ARSIZE/AWSIZE=4 (one full 16-byte bus beat), INCR.
// * AXI address is aligned down to 16 bytes.  request addr[3] selects the
//   lower or upper 64-bit half of RDATA/WDATA and the matching WSTRB half.
// * AW and W are independent.  Each VALID and payload remains stable until
//   its own READY handshake; BREADY is asserted only after both handshakes.
// * A non-OKAY RRESP/BRESP, or deasserted RLAST on the implied single read
//   beat, is reported through mem_rsp_error.  The selected read half is
//   still returned with an AXI read error for diagnostics.
module c1_tensor_mem_axi128_bridge (
    input  logic          clk,
    input  logic          rst,

    input  logic          mem_req_valid,
    output logic          mem_req_ready,
    input  logic          mem_req_write,
    input  logic [31:0]   mem_req_addr,
    input  logic [63:0]   mem_req_wdata,
    input  logic [7:0]    mem_req_wstrb,

    output logic          mem_rsp_valid,
    input  logic          mem_rsp_ready,
    output logic          mem_rsp_error,
    output logic [63:0]   mem_rsp_rdata,

    output logic [31:0]   m_axi_awaddr,
    output logic [7:0]    m_axi_awlen,
    output logic [2:0]    m_axi_awsize,
    output logic [1:0]    m_axi_awburst,
    output logic          m_axi_awvalid,
    input  logic          m_axi_awready,

    output logic [127:0]  m_axi_wdata,
    output logic [15:0]   m_axi_wstrb,
    output logic          m_axi_wlast,
    output logic          m_axi_wvalid,
    input  logic          m_axi_wready,

    input  logic [1:0]    m_axi_bresp,
    input  logic          m_axi_bvalid,
    output logic          m_axi_bready,

    output logic [31:0]   m_axi_araddr,
    output logic [7:0]    m_axi_arlen,
    output logic [2:0]    m_axi_arsize,
    output logic [1:0]    m_axi_arburst,
    output logic          m_axi_arvalid,
    input  logic          m_axi_arready,

    input  logic [127:0]  m_axi_rdata,
    input  logic [1:0]    m_axi_rresp,
    input  logic          m_axi_rlast,
    input  logic          m_axi_rvalid,
    output logic          m_axi_rready
);

    localparam logic [1:0] AXI_RESP_OKAY = 2'b00;
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_READ_AR,
        ST_READ_R,
        ST_WRITE_SEND,
        ST_WRITE_B,
        ST_RESPONSE
    } state_t;

    state_t state_q;
    logic [31:0] address_q;
    logic half_select_q;
    logic [63:0] write_data_q;
    logic [7:0] write_strobe_q;
    logic aw_sent_q;
    logic w_sent_q;
    logic response_error_q;
    logic [63:0] response_data_q;

    logic request_fire;
    logic aw_fire, w_fire, b_fire;
    logic ar_fire, r_fire;
    logic aw_complete, w_complete;

    always_comb begin
        mem_req_ready = (state_q == ST_IDLE) && !rst;
        mem_rsp_valid = (state_q == ST_RESPONSE) && !rst;
        mem_rsp_error = response_error_q;
        mem_rsp_rdata = response_data_q;

        m_axi_awaddr = {address_q[31:4], 4'b0000};
        m_axi_awlen = 8'd0;
        m_axi_awsize = 3'd4;
        m_axi_awburst = AXI_BURST_INCR;
        m_axi_awvalid = (state_q == ST_WRITE_SEND) && !aw_sent_q;

        if (half_select_q) begin
            m_axi_wdata = {write_data_q, 64'd0};
            m_axi_wstrb = {write_strobe_q, 8'd0};
        end else begin
            m_axi_wdata = {64'd0, write_data_q};
            m_axi_wstrb = {8'd0, write_strobe_q};
        end
        m_axi_wlast = 1'b1;
        m_axi_wvalid = (state_q == ST_WRITE_SEND) && !w_sent_q;
        m_axi_bready = (state_q == ST_WRITE_B);

        m_axi_araddr = {address_q[31:4], 4'b0000};
        m_axi_arlen = 8'd0;
        m_axi_arsize = 3'd4;
        m_axi_arburst = AXI_BURST_INCR;
        m_axi_arvalid = (state_q == ST_READ_AR);
        m_axi_rready = (state_q == ST_READ_R);

        request_fire = mem_req_valid && mem_req_ready;
        aw_fire = m_axi_awvalid && m_axi_awready;
        w_fire = m_axi_wvalid && m_axi_wready;
        b_fire = m_axi_bvalid && m_axi_bready;
        ar_fire = m_axi_arvalid && m_axi_arready;
        r_fire = m_axi_rvalid && m_axi_rready;
        aw_complete = aw_sent_q || aw_fire;
        w_complete = w_sent_q || w_fire;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q <= ST_IDLE;
            address_q <= 32'd0;
            half_select_q <= 1'b0;
            write_data_q <= 64'd0;
            write_strobe_q <= 8'd0;
            aw_sent_q <= 1'b0;
            w_sent_q <= 1'b0;
            response_error_q <= 1'b0;
            response_data_q <= 64'd0;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    aw_sent_q <= 1'b0;
                    w_sent_q <= 1'b0;
                    if (request_fire) begin
                        address_q <= mem_req_addr;
                        half_select_q <= mem_req_addr[3];
                        write_data_q <= mem_req_wdata;
                        write_strobe_q <= mem_req_wstrb;
                        response_error_q <= 1'b0;
                        response_data_q <= 64'd0;
                        if (mem_req_addr[2:0] != 3'b000) begin
                            response_error_q <= 1'b1;
                            state_q <= ST_RESPONSE;
                        end else if (mem_req_write) begin
                            state_q <= ST_WRITE_SEND;
                        end else begin
                            state_q <= ST_READ_AR;
                        end
                    end
                end

                ST_READ_AR: begin
                    if (ar_fire)
                        state_q <= ST_READ_R;
                end

                ST_READ_R: begin
                    if (r_fire) begin
                        response_data_q <= half_select_q ?
                                           m_axi_rdata[127:64] :
                                           m_axi_rdata[63:0];
                        response_error_q <=
                            (m_axi_rresp != AXI_RESP_OKAY) || !m_axi_rlast;
                        state_q <= ST_RESPONSE;
                    end
                end

                ST_WRITE_SEND: begin
                    if (aw_fire)
                        aw_sent_q <= 1'b1;
                    if (w_fire)
                        w_sent_q <= 1'b1;
                    if (aw_complete && w_complete)
                        state_q <= ST_WRITE_B;
                end

                ST_WRITE_B: begin
                    if (b_fire) begin
                        response_error_q <=
                            (m_axi_bresp != AXI_RESP_OKAY);
                        response_data_q <= 64'd0;
                        state_q <= ST_RESPONSE;
                    end
                end

                ST_RESPONSE: begin
                    if (mem_rsp_valid && mem_rsp_ready)
                        state_q <= ST_IDLE;
                end

                default: begin
                    state_q <= ST_IDLE;
                    response_error_q <= 1'b1;
                    response_data_q <= 64'd0;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    logic ar_stalled_q, aw_stalled_q, w_stalled_q, rsp_stalled_q;
    logic [44:0] ar_payload_q, aw_payload_q;
    logic [144:0] w_payload_q;
    logic [64:0] rsp_payload_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            ar_stalled_q <= 1'b0;
            aw_stalled_q <= 1'b0;
            w_stalled_q <= 1'b0;
            rsp_stalled_q <= 1'b0;
        end else begin
            if (ar_stalled_q &&
                (!m_axi_arvalid ||
                 ({m_axi_araddr, m_axi_arlen, m_axi_arsize,
                   m_axi_arburst} != ar_payload_q)))
                $fatal(1, "tensor AXI bridge changed stalled AR payload");
            if (aw_stalled_q &&
                (!m_axi_awvalid ||
                 ({m_axi_awaddr, m_axi_awlen, m_axi_awsize,
                   m_axi_awburst} != aw_payload_q)))
                $fatal(1, "tensor AXI bridge changed stalled AW payload");
            if (w_stalled_q &&
                (!m_axi_wvalid ||
                 ({m_axi_wdata, m_axi_wstrb, m_axi_wlast} != w_payload_q)))
                $fatal(1, "tensor AXI bridge changed stalled W payload");
            if (rsp_stalled_q &&
                (!mem_rsp_valid ||
                 ({mem_rsp_error, mem_rsp_rdata} != rsp_payload_q)))
                $fatal(1, "tensor AXI bridge changed stalled response");

            ar_stalled_q <= m_axi_arvalid && !m_axi_arready;
            aw_stalled_q <= m_axi_awvalid && !m_axi_awready;
            w_stalled_q <= m_axi_wvalid && !m_axi_wready;
            rsp_stalled_q <= mem_rsp_valid && !mem_rsp_ready;
            ar_payload_q <= {m_axi_araddr, m_axi_arlen,
                             m_axi_arsize, m_axi_arburst};
            aw_payload_q <= {m_axi_awaddr, m_axi_awlen,
                             m_axi_awsize, m_axi_awburst};
            w_payload_q <= {m_axi_wdata, m_axi_wstrb, m_axi_wlast};
            rsp_payload_q <= {mem_rsp_error, mem_rsp_rdata};

            if ((m_axi_arvalid || m_axi_rready) &&
                (m_axi_awvalid || m_axi_wvalid || m_axi_bready))
                $fatal(1, "tensor AXI bridge overlapped read and write paths");
        end
    end
`endif

endmodule
