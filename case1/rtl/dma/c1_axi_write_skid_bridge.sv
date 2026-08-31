`timescale 1ns/1ps

// One-entry AXI4 write-channel bridge.
//
// The bridge decouples an upstream burst writer from a clocked serial
// arbiter.  AW is buffered until the downstream arbiter accepts it; W is
// admitted only after that AW handshake and is buffered one beat at a time;
// B is buffered until the upstream writer accepts the response.  This keeps
// all upstream READY/VALID edges registered at the bridge boundary and avoids
// a combinational state/grant delta-cycle dependency.
module c1_axi_write_skid_bridge (
    input  logic          clk,
    input  logic          rst,

    input  logic [31:0]   s_awaddr,
    input  logic [7:0]    s_awlen,
    input  logic [2:0]    s_awsize,
    input  logic [1:0]    s_awburst,
    input  logic          s_awvalid,
    output logic          s_awready,
    input  logic [127:0]  s_wdata,
    input  logic [15:0]   s_wstrb,
    input  logic          s_wlast,
    input  logic          s_wvalid,
    output logic          s_wready,
    output logic [1:0]    s_bresp,
    output logic          s_bvalid,
    input  logic          s_bready,

    output logic [31:0]   m_awaddr,
    output logic [7:0]    m_awlen,
    output logic [2:0]    m_awsize,
    output logic [1:0]    m_awburst,
    output logic          m_awvalid,
    input  logic          m_awready,
    output logic [127:0]  m_wdata,
    output logic [15:0]   m_wstrb,
    output logic          m_wlast,
    output logic          m_wvalid,
    input  logic          m_wready,
    input  logic [1:0]    m_bresp,
    input  logic          m_bvalid,
    output logic          m_bready
);
    logic aw_buf_valid;
    logic [31:0] aw_addr_buf;
    logic [7:0] aw_len_buf;
    logic [2:0] aw_size_buf;
    logic [1:0] aw_burst_buf;
    logic aw_committed;

    logic w_buf_valid;
    logic [127:0] w_data_buf;
    logic [15:0] w_strb_buf;
    logic w_last_buf;

    logic b_buf_valid;
    logic [1:0] b_resp_buf;


    always_comb begin
        s_awready = !aw_buf_valid && !aw_committed && !b_buf_valid;
        s_wready = aw_committed && !w_buf_valid;
        s_bvalid = b_buf_valid;
        s_bresp = b_resp_buf;

        m_awaddr = aw_addr_buf;
        m_awlen = aw_len_buf;
        m_awsize = aw_size_buf;
        m_awburst = aw_burst_buf;
        m_awvalid = aw_buf_valid;
        m_wdata = w_data_buf;
        m_wstrb = w_strb_buf;
        m_wlast = w_last_buf;
        m_wvalid = w_buf_valid;
        m_bready = !b_buf_valid;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            aw_buf_valid <= 1'b0;
            aw_addr_buf <= '0;
            aw_len_buf <= '0;
            aw_size_buf <= '0;
            aw_burst_buf <= '0;
            aw_committed <= 1'b0;
            w_buf_valid <= 1'b0;
            w_data_buf <= '0;
            w_strb_buf <= '0;
            w_last_buf <= 1'b0;
            b_buf_valid <= 1'b0;
            b_resp_buf <= 2'b00;
        end else begin
            if (aw_buf_valid) begin
                if (m_awready) begin
                    aw_buf_valid <= 1'b0;
                    aw_committed <= 1'b1;
                end
            end else if (!aw_committed && !b_buf_valid && s_awvalid) begin
                aw_buf_valid <= 1'b1;
                aw_addr_buf <= s_awaddr;
                aw_len_buf <= s_awlen;
                aw_size_buf <= s_awsize;
                aw_burst_buf <= s_awburst;
            end

            if (w_buf_valid) begin
                if (m_wready) begin
                    w_buf_valid <= 1'b0;
                    if (w_last_buf)
                        aw_committed <= 1'b0;
                end
            end else if (aw_committed && s_wvalid) begin
                w_buf_valid <= 1'b1;
                w_data_buf <= s_wdata;
                w_strb_buf <= s_wstrb;
                w_last_buf <= s_wlast;
            end

            if (b_buf_valid) begin
                if (s_bready)
                    b_buf_valid <= 1'b0;
            end else if (m_bvalid && m_bready) begin
                b_buf_valid <= 1'b1;
                b_resp_buf <= m_bresp;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if ($bits(s_wdata) != 128)
            $fatal(1, "c1_axi_write_skid_bridge requires a 128-bit data path");
    end
`endif
endmodule
