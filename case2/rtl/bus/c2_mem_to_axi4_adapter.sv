`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_mem_to_axi4_adapter
// -----------------------------------------------------------------------------
// Converts the renderer's small, vendor-neutral memory contract into a
// single-outstanding AXI4 master port.
//
// The abstract address is byte based and req_len is DATA_W beats minus one.
// Write data follows on the independent mem_wr_* stream and completion is
// reported only after AXI B.  Read data is returned in descriptor order and
// rsp_last marks the final DATA_W beat.
// AXI AW and W progress independently: WVALID never waits for AWREADY, and all
// W beats may be accepted before AW.  B is consumed only after both AW and the
// final W handshake have completed.
//
// AXI_DATA_W may be wider than DATA_W.  Contiguous abstract beats are packed
// into aligned full-width AXI beats; unused first/last byte lanes have WSTRB=0.
// Reads use aligned full-width AXI bursts and unpack only the requested lanes.
// This is important for RGB565: a 16-bit renderer port can still use a 64- or
// 128-bit DDR controller efficiently without changing the renderer ABI.
//
// Deliberate limits:
//   * one outstanding abstract/AXI transaction;
//   * one abstract descriptor must map to at most 256 AXI beats;
//   * a descriptor must not make the aligned AXI burst cross 4 KiB;
//   * DATA_W and AXI_DATA_W are byte/power-of-two widths and AXI_DATA_W is an
//     integer multiple of DATA_W.
// Upstream line-burst planners already enforce the latter two run-time limits.
// Invalid descriptors fail locally instead of issuing malformed AXI traffic.
// -----------------------------------------------------------------------------
module c2_mem_to_axi4_adapter #(
    parameter int ADDR_W     = 32,
    parameter int DATA_W     = 16,
    parameter int LEN_W      = 16,
    parameter int AXI_DATA_W = 128,
    parameter int AXI_ID_W   = 4
) (
    input  logic                      clk,
    input  logic                      rst_n,

    // Abstract descriptor channel.
    input  logic                      mem_req_valid,
    output logic                      mem_req_ready,
    input  logic                      mem_req_write,
    input  logic [ADDR_W-1:0]         mem_req_addr,
    input  logic [LEN_W-1:0]          mem_req_len,
    input  logic [DATA_W-1:0]         mem_req_wdata,
    input  logic [(DATA_W/8)-1:0]     mem_req_wstrb,

    // Abstract write-data and completion channels.
    input  logic                      mem_wr_valid,
    output logic                      mem_wr_ready,
    input  logic [DATA_W-1:0]         mem_wr_data,
    input  logic [(DATA_W/8)-1:0]     mem_wr_strb,
    input  logic                      mem_wr_last,
    output logic                      mem_wr_error,

    output logic                      mem_wr_rsp_valid,
    input  logic                      mem_wr_rsp_ready,
    output logic                      mem_wr_rsp_error,

    // Abstract ordered read response channel.
    output logic                      mem_rsp_valid,
    input  logic                      mem_rsp_ready,
    output logic [DATA_W-1:0]         mem_rsp_rdata,
    output logic                      mem_rsp_last,
    output logic                      mem_rsp_error,

    // AXI4 write address channel.
    output logic [AXI_ID_W-1:0]       m_axi_awid,
    output logic [ADDR_W-1:0]         m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,
    output logic                      m_axi_awlock,
    output logic [3:0]                m_axi_awcache,
    output logic [2:0]                m_axi_awprot,
    output logic [3:0]                m_axi_awqos,
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,

    // AXI4 write data/response channels.
    output logic [AXI_DATA_W-1:0]     m_axi_wdata,
    output logic [(AXI_DATA_W/8)-1:0] m_axi_wstrb,
    output logic                      m_axi_wlast,
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,

    input  logic [AXI_ID_W-1:0]       m_axi_bid,
    input  logic [1:0]                m_axi_bresp,
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready,

    // AXI4 read address/data channels.
    output logic [AXI_ID_W-1:0]       m_axi_arid,
    output logic [ADDR_W-1:0]         m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,
    output logic                      m_axi_arlock,
    output logic [3:0]                m_axi_arcache,
    output logic [2:0]                m_axi_arprot,
    output logic [3:0]                m_axi_arqos,
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,

    input  logic [AXI_ID_W-1:0]       m_axi_rid,
    input  logic [AXI_DATA_W-1:0]     m_axi_rdata,
    input  logic [1:0]                m_axi_rresp,
    input  logic                      m_axi_rlast,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready,

    output logic                      busy,
    output logic [31:0]               protocol_error_count,
    output logic [31:0]               axi_error_count
);

    localparam int DATA_BYTES = DATA_W / 8;
    localparam int AXI_BYTES  = AXI_DATA_W / 8;
    localparam int LANES      = AXI_DATA_W / DATA_W;
    localparam int LANE_W     = (LANES <= 1) ? 1 : $clog2(LANES);
    localparam int AXI_SIZE_I = $clog2(AXI_BYTES);
    localparam logic [ADDR_W-1:0] AXI_ADDR_MASK =
        ({ADDR_W{1'b1}} << AXI_SIZE_I);

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_WR_DATA,
        ST_WR_B,
        ST_WR_RESP,
        ST_WR_REJECT,
        ST_RD_AR,
        ST_RD_DATA,
        ST_RD_DRAIN,
        ST_RD_REJECT
    } state_e;

    state_e state_q;

    logic [ADDR_W-1:0] axi_addr_q;
    logic [7:0]        axi_len_q;
    logic [8:0]        axi_write_beats_left_q;
    logic [8:0]        axi_read_beats_left_q;

    logic [LEN_W:0]    wr_internal_beats_left_q;
    logic [LEN_W:0]    rd_internal_beats_left_q;
    logic [LANE_W-1:0] start_lane_q;
    logic [LANE_W-1:0] wr_lane_q;
    logic [LANE_W-1:0] rd_lane_q;

    logic [AXI_DATA_W-1:0] w_buf_data_q;
    logic [AXI_BYTES-1:0]  w_buf_strb_q;
    logic                   w_buf_valid_q;
    logic                   aw_pending_q;
    logic                   write_data_done_q;
    logic                   write_pad_q;
    logic                   write_error_q;
    logic                   wr_rsp_error_q;

    logic [AXI_DATA_W-1:0] r_buf_data_q;
    logic                   r_buf_valid_q;
    logic                   r_buf_error_q;
    logic                   r_buf_seen_last_q;
    logic                   read_first_axi_q;

    logic [ADDR_W-1:0] desc_aligned_addr;
    integer unsigned   desc_start_lane;
    integer unsigned   desc_internal_beats;
    integer unsigned   desc_axi_beats;
    integer unsigned   desc_page_span;
    logic              desc_invalid;

    logic req_fire;
    logic wr_input_fire;
    logic axi_aw_fire;
    logic axi_w_fire;
    logic axi_b_fire;
    logic axi_ar_fire;
    logic axi_r_fire;
    logic rsp_fire;
    logic wr_rsp_fire;
    logic wr_expected_last;
    logic wr_last_mismatch;
    logic rd_expected_axi_last;
    logic captured_r_error;

    // Descriptor geometry.  Full-width AXI transfers are aligned down; the
    // first requested DATA_W lane and total lane count determine AW/ARLEN.
    always_comb begin
        desc_aligned_addr = mem_req_addr & AXI_ADDR_MASK;
        desc_start_lane = (mem_req_addr / DATA_BYTES) % LANES;
        desc_internal_beats = $unsigned(mem_req_len) + 1;
        desc_axi_beats =
            (desc_start_lane + desc_internal_beats + LANES - 1) / LANES;
        desc_page_span = $unsigned(desc_aligned_addr[11:0]) +
                         (desc_axi_beats * AXI_BYTES);

        desc_invalid = ((mem_req_addr % DATA_BYTES) != 0) ||
                       (desc_axi_beats == 0) ||
                       (desc_axi_beats > 256) ||
                       (desc_page_span > 4096);
    end

    always_comb begin
        mem_req_ready = (state_q == ST_IDLE);
        req_fire      = mem_req_valid && mem_req_ready;

        mem_wr_ready = ((state_q == ST_WR_DATA) && !w_buf_valid_q &&
                        !write_pad_q && !write_data_done_q) ||
                       (state_q == ST_WR_REJECT);
        wr_input_fire = mem_wr_valid && mem_wr_ready;
        wr_expected_last = (wr_internal_beats_left_q ==
                            {{LEN_W{1'b0}}, 1'b1});
        wr_last_mismatch = (mem_wr_last != wr_expected_last);
        mem_wr_error = wr_input_fire &&
                       (wr_last_mismatch ||
                        ((state_q == ST_WR_REJECT) &&
                         (mem_wr_last || wr_expected_last)));

        mem_wr_rsp_valid = (state_q == ST_WR_RESP);
        mem_wr_rsp_error = wr_rsp_error_q;
        wr_rsp_fire = mem_wr_rsp_valid && mem_wr_rsp_ready;

        mem_rsp_valid = r_buf_valid_q || (state_q == ST_RD_REJECT);
        mem_rsp_rdata = '0;
        if (r_buf_valid_q)
            mem_rsp_rdata = r_buf_data_q[(rd_lane_q * DATA_W) +: DATA_W];
        mem_rsp_error = (state_q == ST_RD_REJECT) ||
                        (r_buf_valid_q && r_buf_error_q);
        mem_rsp_last = (state_q == ST_RD_REJECT) ||
                       (r_buf_valid_q &&
                        (r_buf_error_q ||
                         (rd_internal_beats_left_q ==
                          {{LEN_W{1'b0}}, 1'b1})));
        rsp_fire = mem_rsp_valid && mem_rsp_ready;

        // Constant AXI attributes.  Both channels issue aligned, full-width,
        // incrementing bursts with ID zero.
        m_axi_awid    = '0;
        m_axi_awaddr  = axi_addr_q;
        m_axi_awlen   = axi_len_q;
        m_axi_awsize  = 3'(AXI_SIZE_I);
        m_axi_awburst = 2'b01;
        m_axi_awlock  = 1'b0;
        m_axi_awcache = 4'b0011;
        m_axi_awprot  = 3'b000;
        m_axi_awqos   = 4'b0000;
        m_axi_awvalid = (state_q == ST_WR_DATA) && aw_pending_q;
        axi_aw_fire   = m_axi_awvalid && m_axi_awready;

        m_axi_wdata  = w_buf_data_q;
        m_axi_wstrb  = w_buf_strb_q;
        m_axi_wlast  = w_buf_valid_q && (axi_write_beats_left_q == 9'd1);
        m_axi_wvalid = (state_q == ST_WR_DATA) && w_buf_valid_q;
        axi_w_fire   = m_axi_wvalid && m_axi_wready;

        m_axi_bready = (state_q == ST_WR_B);
        axi_b_fire   = m_axi_bvalid && m_axi_bready;

        m_axi_arid    = '0;
        m_axi_araddr  = axi_addr_q;
        m_axi_arlen   = axi_len_q;
        m_axi_arsize  = 3'(AXI_SIZE_I);
        m_axi_arburst = 2'b01;
        m_axi_arlock  = 1'b0;
        m_axi_arcache = 4'b0011;
        m_axi_arprot  = 3'b000;
        m_axi_arqos   = 4'b0000;
        m_axi_arvalid = (state_q == ST_RD_AR);
        axi_ar_fire   = m_axi_arvalid && m_axi_arready;

        m_axi_rready = ((state_q == ST_RD_DATA) && !r_buf_valid_q) ||
                       (state_q == ST_RD_DRAIN);
        axi_r_fire = m_axi_rvalid && m_axi_rready;
        rd_expected_axi_last = (axi_read_beats_left_q == 9'd1);
        captured_r_error = m_axi_rresp[1] || (m_axi_rid != {AXI_ID_W{1'b0}}) ||
                           (m_axi_rlast != rd_expected_axi_last);

        busy = (state_q != ST_IDLE);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q                  <= ST_IDLE;
            axi_addr_q               <= '0;
            axi_len_q                <= '0;
            axi_write_beats_left_q   <= '0;
            axi_read_beats_left_q    <= '0;
            wr_internal_beats_left_q <= '0;
            rd_internal_beats_left_q <= '0;
            start_lane_q             <= '0;
            wr_lane_q                <= '0;
            rd_lane_q                <= '0;
            w_buf_data_q             <= '0;
            w_buf_strb_q             <= '0;
            w_buf_valid_q            <= 1'b0;
            aw_pending_q             <= 1'b0;
            write_data_done_q        <= 1'b0;
            write_pad_q              <= 1'b0;
            write_error_q            <= 1'b0;
            wr_rsp_error_q           <= 1'b0;
            r_buf_data_q             <= '0;
            r_buf_valid_q            <= 1'b0;
            r_buf_error_q            <= 1'b0;
            r_buf_seen_last_q        <= 1'b0;
            read_first_axi_q         <= 1'b0;
            protocol_error_count     <= 32'd0;
            axi_error_count          <= 32'd0;
        end else begin
            if (req_fire) begin
                axi_addr_q   <= desc_aligned_addr;
                axi_len_q    <= desc_axi_beats[7:0] - 8'd1;
                start_lane_q <= LANE_W'(desc_start_lane);
                wr_rsp_error_q <= 1'b0;
                write_error_q  <= 1'b0;
                aw_pending_q   <= 1'b0;
                write_data_done_q <= 1'b0;

                if (desc_invalid) begin
                    protocol_error_count <= protocol_error_count + 32'd1;
                    if (mem_req_write) begin
                        // Even a locally rejected write descriptor owns the
                        // upstream write-data channel until its real last
                        // beat.  Drain that stream before returning wr_rsp so
                        // the owner-aware arbiter cannot be stranded midway
                        // through a malformed/unsupported descriptor.
                        wr_internal_beats_left_q <=
                            {1'b0, mem_req_len} +
                            {{LEN_W{1'b0}}, 1'b1};
                        state_q <= ST_WR_REJECT;
                    end else begin
                        state_q <= ST_RD_REJECT;
                    end
                end else if (mem_req_write) begin
                    axi_write_beats_left_q <= 9'(desc_axi_beats);
                    wr_internal_beats_left_q <=
                        {1'b0, mem_req_len} + {{LEN_W{1'b0}}, 1'b1};
                    wr_lane_q     <= LANE_W'(desc_start_lane);
                    w_buf_data_q  <= '0;
                    w_buf_strb_q  <= '0;
                    w_buf_valid_q <= 1'b0;
                    write_pad_q   <= 1'b0;
                    aw_pending_q  <= 1'b1;
                    state_q       <= ST_WR_DATA;
                end else begin
                    axi_read_beats_left_q <= 9'(desc_axi_beats);
                    rd_internal_beats_left_q <=
                        {1'b0, mem_req_len} + {{LEN_W{1'b0}}, 1'b1};
                    r_buf_valid_q    <= 1'b0;
                    r_buf_error_q    <= 1'b0;
                    read_first_axi_q <= 1'b1;
                    state_q          <= ST_RD_AR;
                end
            end else begin
                case (state_q)
                    ST_WR_DATA: begin
                        // Address and data handshakes are independent.  A
                        // legal slave may wait for WVALID before AWREADY or
                        // even accept the whole W burst before its AW.
                        if (axi_aw_fire)
                            aw_pending_q <= 1'b0;

                        if (wr_input_fire) begin
                            w_buf_data_q[(wr_lane_q * DATA_W) +: DATA_W] <=
                                mem_wr_data;
                            w_buf_strb_q[(wr_lane_q * DATA_BYTES) +: DATA_BYTES] <=
                                mem_wr_strb;

                            if (wr_last_mismatch) begin
                                write_error_q <= 1'b1;
                                protocol_error_count <=
                                    protocol_error_count + 32'd1;
                            end

                            if (wr_expected_last || mem_wr_last) begin
                                // The current partial/full AXI word is ready.
                                // An early abstract last is followed by zero-
                                // strobe padding so the advertised AW burst
                                // can still terminate legally at AXI WLAST.
                                w_buf_valid_q <= 1'b1;
                                wr_internal_beats_left_q <= '0;
                                if (mem_wr_last && !wr_expected_last)
                                    write_pad_q <= 1'b1;
                            end else begin
                                wr_internal_beats_left_q <=
                                    wr_internal_beats_left_q -
                                    {{LEN_W{1'b0}}, 1'b1};
                                if (wr_lane_q == LANE_W'(LANES-1)) begin
                                    w_buf_valid_q <= 1'b1;
                                end else begin
                                    wr_lane_q <= wr_lane_q +
                                                 {{(LANE_W-1){1'b0}}, 1'b1};
                                end
                            end
                        end

                        if (axi_w_fire) begin
                            if (axi_write_beats_left_q == 9'd1) begin
                                axi_write_beats_left_q <= '0;
                                w_buf_valid_q <= 1'b0;
                                write_data_done_q <= 1'b1;
                            end else begin
                                axi_write_beats_left_q <=
                                    axi_write_beats_left_q - 9'd1;
                                w_buf_data_q <= '0;
                                w_buf_strb_q <= '0;
                                wr_lane_q <= '0;
                                if (write_pad_q)
                                    w_buf_valid_q <= 1'b1;
                                else
                                    w_buf_valid_q <= 1'b0;
                            end
                        end

                        // Enter B wait only when BOTH channels have finished,
                        // including simultaneous AW/final-W acceptance.  If W
                        // finishes first, keep AWVALID asserted and reject any
                        // additional abstract write data until AW catches up.
                        if ((!aw_pending_q || axi_aw_fire) &&
                            (write_data_done_q ||
                             (axi_w_fire && (axi_write_beats_left_q == 9'd1))))
                            state_q <= ST_WR_B;
                    end

                    ST_WR_B: begin
                        if (axi_b_fire) begin
                            wr_rsp_error_q <= write_error_q ||
                                              m_axi_bresp[1] ||
                                              (m_axi_bid != {AXI_ID_W{1'b0}});
                            if (m_axi_bresp[1] ||
                                (m_axi_bid != {AXI_ID_W{1'b0}}))
                                axi_error_count <= axi_error_count + 32'd1;
                            state_q <= ST_WR_RESP;
                        end
                    end

                    ST_WR_REJECT: begin
                        if (wr_input_fire) begin
                            wr_rsp_error_q <= 1'b1;
                            if (wr_internal_beats_left_q != 0)
                                wr_internal_beats_left_q <=
                                    wr_internal_beats_left_q -
                                    {{LEN_W{1'b0}}, 1'b1};
                            if (mem_wr_last || wr_expected_last)
                                state_q <= ST_WR_RESP;
                        end
                    end

                    ST_WR_RESP: begin
                        if (wr_rsp_fire)
                            state_q <= ST_IDLE;
                    end

                    ST_RD_AR: begin
                        if (axi_ar_fire)
                            state_q <= ST_RD_DATA;
                    end

                    ST_RD_DATA: begin
                        if (axi_r_fire) begin
                            r_buf_data_q      <= m_axi_rdata;
                            r_buf_valid_q     <= 1'b1;
                            r_buf_error_q     <= captured_r_error;
                            r_buf_seen_last_q <= m_axi_rlast;
                            if (read_first_axi_q)
                                rd_lane_q <= start_lane_q;
                            else
                                rd_lane_q <= '0;
                            read_first_axi_q <= 1'b0;
                            if (axi_read_beats_left_q != 0)
                                axi_read_beats_left_q <=
                                    axi_read_beats_left_q - 9'd1;
                            if (captured_r_error)
                                axi_error_count <= axi_error_count + 32'd1;
                        end

                        if (rsp_fire) begin
                            if (r_buf_error_q ||
                                (rd_internal_beats_left_q ==
                                 {{LEN_W{1'b0}}, 1'b1})) begin
                                rd_internal_beats_left_q <= '0;
                                r_buf_valid_q <= 1'b0;
                                if (r_buf_error_q && !r_buf_seen_last_q)
                                    state_q <= ST_RD_DRAIN;
                                else
                                    state_q <= ST_IDLE;
                            end else begin
                                rd_internal_beats_left_q <=
                                    rd_internal_beats_left_q -
                                    {{LEN_W{1'b0}}, 1'b1};
                                if (rd_lane_q == LANE_W'(LANES-1)) begin
                                    r_buf_valid_q <= 1'b0;
                                end else begin
                                    rd_lane_q <= rd_lane_q +
                                                 {{(LANE_W-1){1'b0}}, 1'b1};
                                end
                            end
                        end
                    end

                    ST_RD_DRAIN: begin
                        // An AXI error is terminal on the abstract interface,
                        // but the AXI channel must still be consumed through
                        // its real last beat before another request is issued.
                        if (axi_r_fire && m_axi_rlast)
                            state_q <= ST_IDLE;
                    end

                    ST_RD_REJECT: begin
                        if (rsp_fire)
                            state_q <= ST_IDLE;
                    end

                    default: state_q <= ST_IDLE;
                endcase
            end
        end
    end

    // req_wdata/req_wstrb are retained for ABI compatibility with the generic
    // arbiter.  AXI bursts take payload from mem_wr_* after the descriptor
    // accepts, independently of the AXI AW handshake.
    logic unused_req_payload;
    always_comb
        unused_req_payload = ^{mem_req_wdata, mem_req_wstrb};

`ifndef SYNTHESIS
    initial begin
        if (ADDR_W < 12 || DATA_W <= 0 || AXI_DATA_W <= 0 || LEN_W <= 0 ||
            AXI_ID_W <= 0)
            $error("c2_mem_to_axi4_adapter: invalid parameter width");
        if ((DATA_W % 8) != 0 || (AXI_DATA_W % 8) != 0 ||
            (AXI_DATA_W % DATA_W) != 0)
            $error("c2_mem_to_axi4_adapter: AXI_DATA_W must be a byte-wide multiple of DATA_W");
        if ((DATA_BYTES & (DATA_BYTES-1)) != 0 ||
            (AXI_BYTES & (AXI_BYTES-1)) != 0 || AXI_BYTES > 128)
            $error("c2_mem_to_axi4_adapter: data byte widths must be powers of two supported by AXI SIZE");
    end
`endif

endmodule
