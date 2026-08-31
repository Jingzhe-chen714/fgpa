`timescale 1ns/1ps

module tb_c2_mem_to_axi4_adapter #(
    parameter int AXI_DATA_W = 64
);
    localparam int ADDR_W = 32;
    localparam int DATA_W = 16;
    localparam int LEN_W = 16;
    localparam int AXI_BYTES = AXI_DATA_W / 8;
    localparam int DATA_BYTES = DATA_W / 8;
    localparam int AXI_LANES = AXI_DATA_W / DATA_W;
    localparam int AXI_SIZE = $clog2(AXI_BYTES);
    localparam int AXI_ID_W = 2;
    localparam int BASIC_BEATS = AXI_LANES + 2;
    localparam int BASIC_AXI_BEATS = (1 + BASIC_BEATS + AXI_LANES - 1) / AXI_LANES;
    localparam int FAULT_BEATS = AXI_LANES + 1;
    localparam int WAIT_LIMIT = 512;
    localparam int RLAST_NORMAL = 0;
    localparam int RLAST_EARLY = 1;
    localparam int RLAST_LATE = 2;
    localparam int WRITE_NORMAL = 0;
    localparam int WRITE_AW_WAITS_WVALID = 1;
    localparam int WRITE_AW_AFTER_FIRST_W = 2;
    localparam int WRITE_AW_AFTER_LAST_W = 3;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic mem_req_valid, mem_req_ready, mem_req_write;
    logic [ADDR_W-1:0] mem_req_addr;
    logic [LEN_W-1:0] mem_req_len;
    logic [DATA_W-1:0] mem_req_wdata;
    logic [(DATA_W/8)-1:0] mem_req_wstrb;
    logic mem_wr_valid, mem_wr_ready, mem_wr_last, mem_wr_error;
    logic [DATA_W-1:0] mem_wr_data;
    logic [(DATA_W/8)-1:0] mem_wr_strb;
    logic mem_wr_rsp_valid, mem_wr_rsp_ready, mem_wr_rsp_error;
    logic mem_rsp_valid, mem_rsp_ready, mem_rsp_last, mem_rsp_error;
    logic [DATA_W-1:0] mem_rsp_rdata;

    logic [AXI_ID_W-1:0] awid, bid, arid, rid;
    logic [ADDR_W-1:0] awaddr, araddr;
    logic [7:0] awlen, arlen;
    logic [2:0] awsize, arsize;
    logic [1:0] awburst, arburst;
    logic awlock, arlock;
    logic [3:0] awcache, awqos, arcache, arqos;
    logic [2:0] awprot, arprot;
    logic awvalid, awready;
    logic [AXI_DATA_W-1:0] wdata;
    logic [AXI_BYTES-1:0] wstrb;
    logic wlast, wvalid, wready;
    logic [1:0] bresp;
    logic bvalid, bready;
    logic arvalid, arready;
    logic [AXI_DATA_W-1:0] rdata;
    logic [1:0] rresp;
    logic rlast, rvalid, rready;
    logic busy;
    logic [31:0] protocol_error_count, axi_error_count;

    c2_mem_to_axi4_adapter #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .LEN_W(LEN_W),
        .AXI_DATA_W(AXI_DATA_W),
        .AXI_ID_W(AXI_ID_W)
    ) dut (
        .clk, .rst_n,
        .mem_req_valid, .mem_req_ready, .mem_req_write, .mem_req_addr,
        .mem_req_len, .mem_req_wdata, .mem_req_wstrb,
        .mem_wr_valid, .mem_wr_ready, .mem_wr_data, .mem_wr_strb,
        .mem_wr_last, .mem_wr_error,
        .mem_wr_rsp_valid, .mem_wr_rsp_ready, .mem_wr_rsp_error,
        .mem_rsp_valid, .mem_rsp_ready, .mem_rsp_rdata, .mem_rsp_last,
        .mem_rsp_error,
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen),
        .m_axi_awsize(awsize), .m_axi_awburst(awburst),
        .m_axi_awlock(awlock), .m_axi_awcache(awcache),
        .m_axi_awprot(awprot), .m_axi_awqos(awqos),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid),
        .m_axi_bready(bready),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen),
        .m_axi_arsize(arsize), .m_axi_arburst(arburst),
        .m_axi_arlock(arlock), .m_axi_arcache(arcache),
        .m_axi_arprot(arprot), .m_axi_arqos(arqos),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp),
        .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .busy, .protocol_error_count, .axi_error_count
    );

    // ---------------------------------------------------------------------
    // Small byte-addressed AXI memory model.  Ready and valid intentionally
    // contain gaps; all payloads are held until handshake.
    // ---------------------------------------------------------------------
    logic [7:0] ddr_mem [0:8191];
    integer cycle_q;
    logic wr_active_q;
    logic [ADDR_W-1:0] wr_addr_q;
    integer wr_beats_q, wr_index_q;
    integer slave_write_mode;
    logic wr_last_seen_q;
    integer aw_wait_cycles_q;
    logic [AXI_DATA_W-1:0] captured_wdata [0:255];
    logic [AXI_BYTES-1:0] captured_wstrb [0:255];
    logic captured_wlast [0:255];
    integer b_delay_q;
    logic active_b_error_q, next_b_error_q;
    logic rd_active_q;
    logic [ADDR_W-1:0] rd_addr_q;
    integer rd_beats_q, rd_index_q;
    integer active_r_error_beat_q, next_r_error_beat_q;
    integer active_rid_error_beat_q, next_rid_error_beat_q;
    integer active_rlast_mode_q, next_rlast_mode_q;
    integer rd_terminal_index_q;
    integer aw_count_q, ar_count_q;
    integer axi_r_count_q;
    integer rid_error_injected_count_q;
    integer early_rlast_injected_count_q;
    integer late_rlast_missing_count_q, late_rlast_terminal_count_q;
    integer abstract_read_error_count_q, abstract_write_error_count_q;
    integer aw_waits_wvalid_count_q, aw_after_first_w_count_q;
    integer aw_after_last_w_count_q, w_before_aw_count_q;
    logic [ADDR_W-1:0] last_awaddr_q, last_araddr_q;
    logic [7:0] last_awlen_q, last_arlen_q;

    integer lane, write_beat, write_lane;
    always_comb begin
        awready = 1'b0;
        if (!wr_active_q && !bvalid && (b_delay_q == 0)) begin
            case (slave_write_mode)
                WRITE_AW_WAITS_WVALID:
                    awready = wvalid && (cycle_q[1:0] != 2'b00);
                WRITE_AW_AFTER_FIRST_W:
                    awready = (wr_index_q != 0);
                WRITE_AW_AFTER_LAST_W:
                    awready = wr_last_seen_q && (aw_wait_cycles_q >= 3);
                default:
                    awready = (cycle_q[1:0] != 2'b00);
            endcase
        end
        wready = !wr_last_seen_q && !bvalid && (b_delay_q == 0) &&
                 (cycle_q[1:0] != 2'b10) &&
                 (wr_active_q ||
                  (slave_write_mode == WRITE_AW_AFTER_FIRST_W) ||
                  (slave_write_mode == WRITE_AW_AFTER_LAST_W));
        arready = !rd_active_q && (cycle_q[2:0] != 3'b001);
        bid     = '0;
        bresp   = active_b_error_q ? 2'b10 : 2'b00;
    end

    // Plain procedural block is intentional in the testbench: fault-injection
    // knobs are also assigned by the stimulus process.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_q <= 0;
            wr_active_q <= 1'b0;
            wr_addr_q <= '0;
            wr_beats_q <= 0;
            wr_index_q <= 0;
            wr_last_seen_q <= 1'b0;
            aw_wait_cycles_q <= 0;
            b_delay_q <= 0;
            bvalid <= 1'b0;
            active_b_error_q <= 1'b0;
            rd_active_q <= 1'b0;
            rd_addr_q <= '0;
            rd_beats_q <= 0;
            rd_index_q <= 0;
            rdata <= '0;
            rid <= '0;
            rresp <= 2'b00;
            rlast <= 1'b0;
            rvalid <= 1'b0;
            active_r_error_beat_q <= -1;
            active_rid_error_beat_q <= -1;
            active_rlast_mode_q <= RLAST_NORMAL;
            rd_terminal_index_q <= 0;
            aw_count_q <= 0;
            ar_count_q <= 0;
            axi_r_count_q <= 0;
            rid_error_injected_count_q <= 0;
            early_rlast_injected_count_q <= 0;
            late_rlast_missing_count_q <= 0;
            late_rlast_terminal_count_q <= 0;
            abstract_read_error_count_q <= 0;
            abstract_write_error_count_q <= 0;
            aw_waits_wvalid_count_q <= 0;
            aw_after_first_w_count_q <= 0;
            aw_after_last_w_count_q <= 0;
            w_before_aw_count_q <= 0;
            last_awaddr_q <= '0;
            last_araddr_q <= '0;
            last_awlen_q <= '0;
            last_arlen_q <= '0;
        end else begin
            cycle_q <= cycle_q + 1;
            if (!wr_active_q && wr_last_seen_q &&
                (slave_write_mode == WRITE_AW_AFTER_LAST_W) &&
                (aw_wait_cycles_q < 3))
                aw_wait_cycles_q <= aw_wait_cycles_q + 1;

            if (awvalid && awready) begin
                if (awsize != AXI_SIZE || awburst != 2'b01 || awid != 0)
                    $fatal(1, "bad AXI AW attributes");
                if ((awaddr % AXI_BYTES) != 0 ||
                    ((awaddr % 4096) + (awlen + 1)*AXI_BYTES) > 4096)
                    $fatal(1, "unaligned or 4KiB-crossing AXI AW");
                wr_active_q <= 1'b1;
                wr_addr_q <= awaddr;
                wr_beats_q <= awlen + 1;
                // W may already be buffered; AW must not reset its count.
                if (slave_write_mode == WRITE_AW_WAITS_WVALID) begin
                    if (!wvalid)
                        $fatal(1, "AWREADY dependency mode did not see WVALID");
                    aw_waits_wvalid_count_q <= aw_waits_wvalid_count_q + 1;
                end
                if (slave_write_mode == WRITE_AW_AFTER_FIRST_W) begin
                    if (wr_index_q == 0 || wr_last_seen_q)
                        $fatal(1, "expected first W before AW, but not final W");
                    aw_after_first_w_count_q <= aw_after_first_w_count_q + 1;
                end
                if (slave_write_mode == WRITE_AW_AFTER_LAST_W) begin
                    if (!wr_last_seen_q || aw_wait_cycles_q < 3)
                        $fatal(1, "AW was not delayed beyond WLAST");
                    aw_after_last_w_count_q <= aw_after_last_w_count_q + 1;
                end
                active_b_error_q <= next_b_error_q;
                next_b_error_q <= 1'b0;
                aw_count_q <= aw_count_q + 1;
                last_awaddr_q <= awaddr;
                last_awlen_q <= awlen;
            end

            if (wvalid && wready) begin
                if (wr_index_q >= 256)
                    $fatal(1, "write capture exceeded AXI maximum burst");
                captured_wdata[wr_index_q] <= wdata;
                captured_wstrb[wr_index_q] <= wstrb;
                captured_wlast[wr_index_q] <= wlast;
                wr_index_q <= wr_index_q + 1;
                if (wlast)
                    wr_last_seen_q <= 1'b1;
                if (!wr_active_q && !(awvalid && awready))
                    w_before_aw_count_q <= w_before_aw_count_q + 1;
            end

            // The AXI slave can buffer W before AW.  Apply byte strobes and
            // issue B only once both the address and complete data are known.
            if (wr_active_q && wr_last_seen_q && !bvalid && (b_delay_q == 0)) begin
                if (wr_index_q != wr_beats_q)
                    $fatal(1, "AXI write beat count mismatch got=%0d expected=%0d",
                           wr_index_q, wr_beats_q);
                for (write_beat = 0; write_beat < wr_index_q; write_beat = write_beat + 1) begin
                    if (captured_wlast[write_beat] !== (write_beat == wr_beats_q-1))
                        $fatal(1, "AXI WLAST mismatch beat=%0d beats=%0d",
                               write_beat, wr_beats_q);
                    for (write_lane = 0; write_lane < AXI_BYTES; write_lane = write_lane + 1)
                        if (captured_wstrb[write_beat][write_lane])
                            ddr_mem[wr_addr_q + write_beat*AXI_BYTES + write_lane] <=
                                captured_wdata[write_beat][write_lane*8 +: 8];
                end
                wr_active_q <= 1'b0;
                wr_last_seen_q <= 1'b0;
                wr_index_q <= 0;
                aw_wait_cycles_q <= 0;
                b_delay_q <= 2;
            end

            if (!bvalid && (b_delay_q != 0)) begin
                if (b_delay_q == 1)
                    bvalid <= 1'b1;
                b_delay_q <= b_delay_q - 1;
            end
            if (bvalid && bready)
                bvalid <= 1'b0;

            if (arvalid && arready) begin
                if (arsize != AXI_SIZE || arburst != 2'b01 || arid != 0)
                    $fatal(1, "bad AXI AR attributes");
                if ((araddr % AXI_BYTES) != 0 ||
                    ((araddr % 4096) + (arlen + 1)*AXI_BYTES) > 4096)
                    $fatal(1, "unaligned or 4KiB-crossing AXI AR");
                rd_active_q <= 1'b1;
                rd_addr_q <= araddr;
                rd_beats_q <= arlen + 1;
                rd_index_q <= 0;
                active_r_error_beat_q <= next_r_error_beat_q;
                next_r_error_beat_q <= -1;
                active_rid_error_beat_q <= next_rid_error_beat_q;
                next_rid_error_beat_q <= -1;
                active_rlast_mode_q <= next_rlast_mode_q;
                next_rlast_mode_q <= RLAST_NORMAL;
                if (next_rlast_mode_q == RLAST_EARLY) begin
                    if (arlen == 0)
                        $fatal(1, "early RLAST injection needs a multi-beat AR");
                    rd_terminal_index_q <= 0;
                end else if (next_rlast_mode_q == RLAST_LATE) begin
                    // Suppress the advertised terminal marker and send one
                    // extra physical beat carrying the real RLAST.
                    rd_terminal_index_q <= arlen + 1;
                end else begin
                    rd_terminal_index_q <= arlen;
                end
                ar_count_q <= ar_count_q + 1;
                last_araddr_q <= araddr;
                last_arlen_q <= arlen;
            end

            if (rd_active_q && !rvalid && (cycle_q[1:0] != 2'b01)) begin
                for (lane = 0; lane < AXI_BYTES; lane = lane + 1)
                    rdata[lane*8 +: 8] <=
                        ddr_mem[rd_addr_q + rd_index_q*AXI_BYTES + lane];
                rresp <= (rd_index_q == active_r_error_beat_q) ?
                         2'b10 : 2'b00;
                rid <= (rd_index_q == active_rid_error_beat_q) ?
                       AXI_ID_W'(1) : '0;
                rlast <= (rd_index_q == rd_terminal_index_q);
                rvalid <= 1'b1;
            end

            if (rvalid && rready) begin
                axi_r_count_q <= axi_r_count_q + 1;
                if (rid != 0)
                    rid_error_injected_count_q <= rid_error_injected_count_q + 1;
                if ((active_rlast_mode_q == RLAST_EARLY) && rlast &&
                    (rd_index_q != (rd_beats_q - 1)))
                    early_rlast_injected_count_q <= early_rlast_injected_count_q + 1;
                if ((active_rlast_mode_q == RLAST_LATE) && !rlast &&
                    (rd_index_q == (rd_beats_q - 1)))
                    late_rlast_missing_count_q <= late_rlast_missing_count_q + 1;
                if ((active_rlast_mode_q == RLAST_LATE) && rlast &&
                    (rd_index_q == rd_beats_q))
                    late_rlast_terminal_count_q <= late_rlast_terminal_count_q + 1;
                rvalid <= 1'b0;
                if (rlast) begin
                    rd_active_q <= 1'b0;
                end else begin
                    rd_index_q <= rd_index_q + 1;
                end
            end

            if (mem_rsp_valid && mem_rsp_ready && mem_rsp_error)
                abstract_read_error_count_q <= abstract_read_error_count_q + 1;
            if (mem_wr_rsp_valid && mem_wr_rsp_ready && mem_wr_rsp_error)
                abstract_write_error_count_q <= abstract_write_error_count_q + 1;
        end
    end

    // AXI and abstract response payloads must remain stable under pressure.
    logic aw_hold_q, ar_hold_q, w_hold_q, rsp_hold_q, wr_rsp_hold_q;
    logic [ADDR_W-1:0] held_awaddr_q;
    logic [ADDR_W-1:0] held_araddr_q;
    logic [7:0] held_awlen_q;
    logic [7:0] held_arlen_q;
    logic [AXI_DATA_W-1:0] held_wdata_q;
    logic [AXI_BYTES-1:0] held_wstrb_q;
    logic held_wlast_q;
    logic [DATA_W-1:0] held_rsp_data_q;
    logic held_rsp_last_q, held_rsp_error_q;
    logic held_wr_rsp_error_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_hold_q <= 1'b0;
            ar_hold_q <= 1'b0;
            w_hold_q <= 1'b0;
            rsp_hold_q <= 1'b0;
            wr_rsp_hold_q <= 1'b0;
        end else begin
            if (aw_hold_q &&
                (!awvalid ||
                 ({awaddr, awlen} !== {held_awaddr_q, held_awlen_q})))
                $fatal(1, "AW payload changed under backpressure");
            aw_hold_q <= awvalid && !awready;
            if (awvalid && !awready) begin
                held_awaddr_q <= awaddr;
                held_awlen_q <= awlen;
            end

            if (ar_hold_q &&
                (!arvalid ||
                 ({araddr, arlen} !== {held_araddr_q, held_arlen_q})))
                $fatal(1, "AR payload changed under backpressure");
            ar_hold_q <= arvalid && !arready;
            if (arvalid && !arready) begin
                held_araddr_q <= araddr;
                held_arlen_q <= arlen;
            end

            if (w_hold_q &&
                (!wvalid ||
                 ({wdata, wstrb, wlast} !==
                  {held_wdata_q, held_wstrb_q, held_wlast_q})))
                $fatal(1, "W payload changed under backpressure");
            w_hold_q <= wvalid && !wready;
            if (wvalid && !wready) begin
                held_wdata_q <= wdata;
                held_wstrb_q <= wstrb;
                held_wlast_q <= wlast;
            end

            if (rsp_hold_q &&
                (!mem_rsp_valid ||
                 ({mem_rsp_rdata, mem_rsp_last, mem_rsp_error} !==
                  {held_rsp_data_q, held_rsp_last_q, held_rsp_error_q})))
                $fatal(1, "abstract R payload changed under backpressure");
            rsp_hold_q <= mem_rsp_valid && !mem_rsp_ready;
            if (mem_rsp_valid && !mem_rsp_ready) begin
                held_rsp_data_q <= mem_rsp_rdata;
                held_rsp_last_q <= mem_rsp_last;
                held_rsp_error_q <= mem_rsp_error;
            end

            if (wr_rsp_hold_q &&
                (!mem_wr_rsp_valid ||
                 (mem_wr_rsp_error !== held_wr_rsp_error_q)))
                $fatal(1, "abstract write response changed under backpressure");
            wr_rsp_hold_q <= mem_wr_rsp_valid && !mem_wr_rsp_ready;
            if (mem_wr_rsp_valid && !mem_wr_rsp_ready)
                held_wr_rsp_error_q <= mem_wr_rsp_error;
        end
    end

    task automatic send_req(
        input logic is_write,
        input logic [ADDR_W-1:0] addr,
        input integer beats
    );
        integer wait_cycles;
        begin
            @(negedge clk);
            mem_req_write = is_write;
            mem_req_addr = addr;
            mem_req_len = beats - 1;
            mem_req_valid = 1'b1;
            wait_cycles = 0;
            do begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > WAIT_LIMIT)
                    $fatal(1, "descriptor handshake timeout addr=%h", addr);
            end while (!mem_req_ready);
            @(negedge clk);
            mem_req_valid = 1'b0;
        end
    endtask

    task automatic send_wr(
        input logic [15:0] data_i,
        input logic [1:0] strb_i,
        input logic last_i,
        input logic expect_error_i
    );
        integer wait_cycles;
        begin
            @(negedge clk);
            mem_wr_data = data_i;
            mem_wr_strb = strb_i;
            mem_wr_last = last_i;
            mem_wr_valid = 1'b1;
            wait_cycles = 0;
            do begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > WAIT_LIMIT)
                    $fatal(1, "write-data handshake timeout");
            end while (!mem_wr_ready);
            if (mem_wr_error !== expect_error_i)
                $fatal(1, "abstract write error mismatch got=%b expected=%b",
                       mem_wr_error, expect_error_i);
            @(negedge clk);
            mem_wr_valid = 1'b0;
        end
    endtask

    task automatic wait_wr_rsp(input logic expect_error_i);
        integer wait_cycles;
        begin
            mem_wr_rsp_ready = 1'b0;
            wait_cycles = 0;
            do begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > WAIT_LIMIT)
                    $fatal(1, "write-response timeout");
            end while (!mem_wr_rsp_valid);
            if (mem_wr_rsp_error !== expect_error_i)
                $fatal(1, "write response error mismatch got=%b expected=%b",
                       mem_wr_rsp_error, expect_error_i);
            // Stall an already-valid response, rather than merely delaying
            // ready before B has arrived.
            repeat (3) @(posedge clk);
            @(negedge clk);
            mem_wr_rsp_ready = 1'b1;
            @(posedge clk);
            if (!mem_wr_rsp_valid || mem_wr_rsp_error !== expect_error_i)
                $fatal(1, "write response lost while stalled");
            @(negedge clk);
            mem_wr_rsp_ready = 1'b0;
        end
    endtask

    logic [15:0] expected_read [0:63];
    task automatic collect_read(input integer beats);
        integer k, wait_cycles;
        begin
            mem_rsp_ready = 1'b0;
            for (k = 0; k < beats; k = k + 1) begin
                repeat ((k % 3) + 1) @(posedge clk);
                @(negedge clk);
                mem_rsp_ready = 1'b1;
                wait_cycles = 0;
                do begin
                    @(posedge clk);
                    wait_cycles = wait_cycles + 1;
                    if (wait_cycles > WAIT_LIMIT)
                        $fatal(1, "read response timeout beat=%0d", k);
                end while (!mem_rsp_valid);
                if (mem_rsp_error)
                    $fatal(1, "unexpected abstract read error beat=%0d", k);
                if (mem_rsp_rdata !== expected_read[k])
                    $fatal(1, "read mismatch beat=%0d got=%h expected=%h",
                           k, mem_rsp_rdata, expected_read[k]);
                if (mem_rsp_last !== (k == beats-1))
                    $fatal(1, "abstract rsp_last mismatch beat=%0d", k);
                @(negedge clk);
                mem_rsp_ready = 1'b0;
            end
        end
    endtask

    task automatic expect_terminal_read_error(
        input string label_i,
        input integer first_axi_count_i,
        input integer expected_axi_beats_i
    );
        integer wait_cycles;
        begin
            mem_rsp_ready = 1'b0;
            wait_cycles = 0;
            do begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > WAIT_LIMIT)
                    $fatal(1, "%s: terminal read error timeout", label_i);
            end while (!mem_rsp_valid);
            if (mem_rsp_error !== 1'b1 || mem_rsp_last !== 1'b1)
                $fatal(1, "%s: error was not terminal on abstract port", label_i);
            repeat (2) @(posedge clk);
            @(negedge clk);
            mem_rsp_ready = 1'b1;
            @(posedge clk);
            if (!mem_rsp_valid || !mem_rsp_error || !mem_rsp_last)
                $fatal(1, "%s: terminal error lost during backpressure", label_i);
            @(negedge clk);

            // Leave ready asserted while the physical burst drains: any
            // leaked second abstract response would be detected immediately.
            wait_cycles = 0;
            while (busy || rd_active_q || rvalid) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > WAIT_LIMIT)
                    $fatal(1, "%s: AXI drain/recovery timeout", label_i);
                if (mem_rsp_valid)
                    $fatal(1, "%s: extra abstract response after terminal error", label_i);
            end
            repeat (2) begin
                @(posedge clk);
                if (mem_rsp_valid)
                    $fatal(1, "%s: stale abstract response after recovery", label_i);
            end
            @(negedge clk);
            mem_rsp_ready = 1'b0;
            if ((axi_r_count_q - first_axi_count_i) != expected_axi_beats_i)
                $fatal(1, "%s: physical read count got=%0d expected=%0d", label_i,
                       axi_r_count_q-first_axi_count_i, expected_axi_beats_i);
        end
    endtask

    task automatic recovery_read;
        integer k;
        begin
            for (k = 0; k < BASIC_BEATS; k = k + 1)
                expected_read[k] = (k == 2) ? 16'hA502 : (16'h1000 + k);
            send_req(1'b0, 32'h0000_0102, BASIC_BEATS);
            collect_read(BASIC_BEATS);
        end
    endtask

    task automatic independent_aw_w_write(
        input integer mode_i,
        input logic [ADDR_W-1:0] addr_i,
        input logic [15:0] seed_i
    );
        integer k;
        begin
            @(negedge clk);
            slave_write_mode = mode_i;
            send_req(1'b1, addr_i, BASIC_BEATS);
            for (k = 0; k < BASIC_BEATS; k = k + 1)
                send_wr(seed_i + k, 2'b11, k == BASIC_BEATS-1, 1'b0);
            wait_wr_rsp(1'b0);
            slave_write_mode = WRITE_NORMAL;

            for (k = 0; k < BASIC_BEATS; k = k + 1)
                expected_read[k] = seed_i + k;
            send_req(1'b0, addr_i, BASIC_BEATS);
            collect_read(BASIC_BEATS);
        end
    endtask

    integer i;
    integer aw_before, ar_before, r_before;
    initial begin
        if (AXI_DATA_W != 64 && AXI_DATA_W != 128)
            $fatal(1, "this regression is defined for AXI_DATA_W=64 or 128");
        mem_req_valid = 1'b0;
        mem_req_write = 1'b0;
        mem_req_addr = '0;
        mem_req_len = '0;
        mem_req_wdata = '0;
        mem_req_wstrb = '0;
        mem_wr_valid = 1'b0;
        mem_wr_data = '0;
        mem_wr_strb = '0;
        mem_wr_last = 1'b0;
        mem_wr_rsp_ready = 1'b0;
        mem_rsp_ready = 1'b0;
        next_b_error_q = 1'b0;
        next_r_error_beat_q = -1;
        next_rid_error_beat_q = -1;
        next_rlast_mode_q = RLAST_NORMAL;
        slave_write_mode = WRITE_NORMAL;
        for (i = 0; i < 8192; i = i + 1)
            ddr_mem[i] = 8'hA5;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Start at lane one and span two AXI words for both supported widths:
        // 6 RGB565 beats on AXI64, 10 on AXI128.  Guard every unused lane.
        send_req(1'b1, 32'h0000_0102, BASIC_BEATS);
        for (i = 0; i < BASIC_BEATS; i = i + 1)
            send_wr(16'h1000 + i, (i == 2) ? 2'b01 : 2'b11,
                    i == BASIC_BEATS-1, 1'b0);
        wait_wr_rsp(1'b0);
        if (last_awaddr_q != 32'h0000_0100 ||
            last_awlen_q != BASIC_AXI_BEATS-1)
            $fatal(1, "write packing geometry is wrong addr=%h len=%0d",
                   last_awaddr_q, last_awlen_q);
        for (i = 'h100; i < 'h100 + BASIC_AXI_BEATS*AXI_BYTES; i = i + 1)
            if ((i < 'h102 || i >= 'h102 + BASIC_BEATS*DATA_BYTES) &&
                ddr_mem[i] != 8'hA5)
                $fatal(1, "write touched unused AXI byte lane addr=%h", i);
        for (i = 0; i < BASIC_BEATS; i = i + 1) begin
            if (ddr_mem['h102 + i*2] !== i[7:0])
                $fatal(1, "low byte write mismatch beat=%0d", i);
            if (ddr_mem['h103 + i*2] !== ((i == 2) ? 8'hA5 : 8'h10))
                $fatal(1, "high byte write mismatch beat=%0d", i);
        end

        // Read unpacking returns exactly the requested 16-bit beats while
        // the abstract consumer repeatedly applies backpressure.
        for (i = 0; i < BASIC_BEATS; i = i + 1)
            expected_read[i] = (i == 2) ? 16'hA502 : (16'h1000 + i);
        send_req(1'b0, 32'h0000_0102, BASIC_BEATS);
        collect_read(BASIC_BEATS);
        if (last_araddr_q != 32'h0000_0100 ||
            last_arlen_q != BASIC_AXI_BEATS-1)
            $fatal(1, "read unpacking geometry is wrong addr=%h len=%0d",
                   last_araddr_q, last_arlen_q);

        // A legal slave may depend on WVALID before it raises AWREADY.  W
        // collection/VALID must not depend on AW acceptance or this deadlocks.
        independent_aw_w_write(WRITE_AW_WAITS_WVALID, 32'h0000_1202, 16'h2100);

        // Accept one W beat strictly before AW, then accept AW before WLAST.
        independent_aw_w_write(WRITE_AW_AFTER_FIRST_W, 32'h0000_1402, 16'h3100);

        // Accept the complete W burst, hold AW for three further clocks, then
        // accept AW.  Completion must still wait for both AW and the real B.
        independent_aw_w_write(WRITE_AW_AFTER_LAST_W, 32'h0000_1602, 16'h4100);

        // AXI B failures are delayed completion failures, not data-beat
        // failures, and must be preserved until the abstract response accepts.
        next_b_error_q = 1'b1;
        send_req(1'b1, 32'h0000_0200, 1);
        send_wr(16'hCAFE, 2'b11, 1'b1, 1'b0);
        wait_wr_rsp(1'b1);

        // An RRESP fault terminates the abstract response immediately, then
        // the adapter silently drains the remaining AXI burst through RLAST.
        for (i = 0; i < 3*AXI_BYTES; i = i + 1)
            ddr_mem['h300+i] = i[7:0];
        r_before = axi_r_count_q;
        next_r_error_beat_q = 0;
        send_req(1'b0, 32'h0000_0302, FAULT_BEATS);
        expect_terminal_read_error("RRESP", r_before, 2);
        recovery_read();

        // Early abstract last is reported on that beat.  Because AW is
        // already issued, the adapter pads the rest with zero WSTRB, waits B,
        // and reports the local protocol failure in wr_rsp_error.
        send_req(1'b1, 32'h0000_0402, BASIC_BEATS);
        send_wr(16'h55AA, 2'b11, 1'b1, 1'b1);
        wait_wr_rsp(1'b1);
        if (ddr_mem['h402] != 8'hAA || ddr_mem['h403] != 8'h55)
            $fatal(1, "early-last accepted payload was not committed");
        for (i = 'h404; i < 'h400 + BASIC_AXI_BEATS*AXI_BYTES; i = i + 1)
            if (ddr_mem[i] != 8'hA5)
                $fatal(1, "early-last AXI padding modified byte %h", i);

        // Invalid (odd RGB565) addresses are rejected locally and issue no
        // AXI address transaction.
        aw_before = aw_count_q;
        // Use three beats to prove the reject path drains through the real
        // terminal beat before returning wr_rsp; this preserves the upstream
        // owner contract even though no AXI AW is emitted.
        send_req(1'b1, 32'h0000_0501, 3);
        send_wr(16'h1234, 2'b11, 1'b0, 1'b0);
        send_wr(16'h5678, 2'b11, 1'b0, 1'b0);
        send_wr(16'h9ABC, 2'b11, 1'b1, 1'b1);
        wait_wr_rsp(1'b1);
        if (aw_count_q != aw_before)
            $fatal(1, "invalid write descriptor reached AXI AW");

        ar_before = ar_count_q;
        r_before = axi_r_count_q;
        send_req(1'b0, 32'h0000_0503, 1);
        expect_terminal_read_error("odd-address reject", r_before, 0);
        if (ar_count_q != ar_before)
            $fatal(1, "invalid read descriptor reached AXI AR");

        // A wrong RID on a non-terminal physical beat is rejected just like
        // RRESP: exactly one abstract error, then two physical beats consumed.
        r_before = axi_r_count_q;
        next_rid_error_beat_q = 0;
        send_req(1'b0, 32'h0000_0602, FAULT_BEATS);
        expect_terminal_read_error("RID mismatch", r_before, 2);
        recovery_read();

        // The slave ends a two-beat AR early.  The adapter must flag the
        // mismatch, not wait forever for the advertised-but-never-sent beat.
        r_before = axi_r_count_q;
        next_rlast_mode_q = RLAST_EARLY;
        send_req(1'b0, 32'h0000_0702, FAULT_BEATS);
        expect_terminal_read_error("early RLAST", r_before, 1);
        recovery_read();

        // A one-beat AR omits RLAST and supplies it one physical beat late.
        // The first abstract response is terminal error; the extra physical
        // beat is drained before the subsequent valid read is accepted.
        r_before = axi_r_count_q;
        next_rlast_mode_q = RLAST_LATE;
        send_req(1'b0, 32'h0000_0802, 1);
        expect_terminal_read_error("late RLAST", r_before, 2);
        recovery_read();

        // Two aligned RGB565 pixels starting at 0xFFE cross a 4KiB boundary.
        // Reject locally on both directions without issuing AW/AR.  The
        // rejected write still drains its two abstract data beats.
        aw_before = aw_count_q;
        send_req(1'b1, 32'h0000_0FFE, 2);
        send_wr(16'hF00D, 2'b11, 1'b0, 1'b0);
        send_wr(16'hBEEF, 2'b11, 1'b1, 1'b1);
        wait_wr_rsp(1'b1);
        if (aw_count_q != aw_before)
            $fatal(1, "4KiB-crossing write reached AXI AW");
        for (i = 'hFFE; i <= 'h1001; i = i + 1)
            if (ddr_mem[i] != 8'hA5)
                $fatal(1, "rejected 4KiB write modified addr=%h", i);

        ar_before = ar_count_q;
        r_before = axi_r_count_q;
        send_req(1'b0, 32'h0000_0FFE, 2);
        expect_terminal_read_error("4KiB-crossing reject", r_before, 0);
        if (ar_count_q != ar_before)
            $fatal(1, "4KiB-crossing read reached AXI AR");

        // Ending exactly at the boundary is legal, as is a following request
        // on the next page.  These also prove post-rejection recovery.
        expected_read[0] = 16'hA5A5;
        send_req(1'b0, 32'h0000_0FFE, 1);
        collect_read(1);
        send_req(1'b0, 32'h0000_1000, 1);
        collect_read(1);

        if (protocol_error_count != 5 || axi_error_count != 5)
            $fatal(1, "diagnostic counter mismatch protocol=%0d axi=%0d",
                   protocol_error_count, axi_error_count);
        if (aw_count_q != 6 || ar_count_q != 14 || axi_r_count_q != 25)
            $fatal(1, "transaction count mismatch aw=%0d ar=%0d r=%0d",
                   aw_count_q, ar_count_q, axi_r_count_q);
        if (aw_waits_wvalid_count_q != 1 || aw_after_first_w_count_q != 1 ||
            aw_after_last_w_count_q != 1 || w_before_aw_count_q != 3)
            $fatal(1, "independent AW/W coverage mismatch wait_wvalid=%0d after_first=%0d after_last=%0d w_before_aw=%0d",
                   aw_waits_wvalid_count_q, aw_after_first_w_count_q,
                   aw_after_last_w_count_q, w_before_aw_count_q);
        if (rid_error_injected_count_q != 1 || early_rlast_injected_count_q != 1 ||
            late_rlast_missing_count_q != 1 || late_rlast_terminal_count_q != 1)
            $fatal(1, "RID/RLAST injection coverage incomplete");
        if (abstract_read_error_count_q != 6 || abstract_write_error_count_q != 4)
            $fatal(1, "abstract error count mismatch read=%0d write=%0d",
                   abstract_read_error_count_q, abstract_write_error_count_q);

        $display("TB_C2_MEM_TO_AXI4_ADAPTER_PASS width=%0d aw=%0d ar=%0d r=%0d protocol=%0d axi=%0d rid=%0d early_rlast=%0d late_rlast=%0d cross4k=2 read_errors=%0d write_errors=%0d aw_waits_wvalid=%0d aw_after_first_w=%0d aw_after_last_w=%0d w_before_aw=%0d",
                 AXI_DATA_W, aw_count_q, ar_count_q, axi_r_count_q,
                 protocol_error_count, axi_error_count,
                 rid_error_injected_count_q, early_rlast_injected_count_q,
                 late_rlast_terminal_count_q,
                 abstract_read_error_count_q, abstract_write_error_count_q,
                 aw_waits_wvalid_count_q, aw_after_first_w_count_q,
                 aw_after_last_w_count_q, w_before_aw_count_q);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "tb_c2_mem_to_axi4_adapter timeout");
    end

endmodule
