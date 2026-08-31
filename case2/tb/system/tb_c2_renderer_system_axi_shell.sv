`timescale 1ns/1ps

// End-to-end structural/functional check for the competition-facing bus
// configuration.  A NOP command is staged and submitted through AXI4-Lite
// while the external AXI4 DDR port is deliberately held before calibration;
// NOP must still traverse CSR -> FIFO -> parser -> engine and complete without
// issuing an AXI4 Full transaction.
module tb_c2_renderer_system_axi_shell;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic rst_n = 1'b0;

    logic [11:0] awaddr, araddr;
    logic [2:0] awprot, arprot;
    logic awvalid, awready, wvalid, wready, bvalid, bready;
    logic [31:0] wdata, rdata;
    logic [3:0] wstrb;
    logic [1:0] bresp, rresp;
    logic arvalid, arready, rvalid, rready;

    logic [3:0] m_awid, m_arid;
    logic [31:0] m_awaddr, m_araddr;
    logic [7:0] m_awlen, m_arlen;
    logic [2:0] m_awsize, m_arsize;
    logic [1:0] m_awburst, m_arburst;
    logic m_awlock, m_arlock;
    logic [3:0] m_awcache, m_arcache, m_awqos, m_arqos;
    logic [2:0] m_awprot, m_arprot;
    logic m_awvalid, m_wvalid, m_wlast, m_bready;
    logic [63:0] m_wdata;
    logic [7:0] m_wstrb;
    logic m_arvalid, m_rready;

    logic [31:0] direct_rdata;
    logic direct_ready;
    logic video_clk, video_valid, video_de, video_hsync, video_vsync;
    logic [15:0] video_data;
    logic video_init_done, video_init_error, clock_locked;
    logic mem_init_done, mem_init_error, system_busy, system_error;
    logic active_page, pending_page, page_flip_pending, display_underflow;
    logic [31:0] submit_count, completed_count;

    c2_renderer_system #(
        .AXI_DATA_W(64), .AXI_ID_W(4),
        .CMD_FIFO_DEPTH(4), .MAX_BURST_BEATS(2),
        .MAX_READ_BEATS(2), .MAX_WRITE_BEATS(2),
        .LINE_BUFFER_PIXELS(8), .LINE_FIFO_DEPTH(8),
        .H_ACTIVE(4), .H_FRONT(1), .H_SYNC(1), .H_BACK(1),
        .V_ACTIVE(2), .V_FRONT(1), .V_SYNC(1), .V_BACK(2),
        .FB_STRIDE_BYTES(8), .PAGE_BYTES(16),
        .PAGE0_BASE(32'h100), .PAGE1_BASE(32'h200), .MEM_BYTES(2048),
        .USE_AXI4LITE_CSR(1'b1), .USE_EXT_MEM_IP(1'b1),
        .USE_VIDEO_PHY_IP(1'b0), .USE_CLOCK_RESET_IP(1'b0)
    ) dut (
        .clk_in(clk), .rst_n_in(rst_n),
        .csr_valid(1'b0), .csr_write(1'b0), .csr_addr(12'd0),
        .csr_wdata(32'd0), .csr_rdata(direct_rdata), .csr_ready(direct_ready),
        .s_axi_csr_awaddr(awaddr), .s_axi_csr_awprot(awprot),
        .s_axi_csr_awvalid(awvalid), .s_axi_csr_awready(awready),
        .s_axi_csr_wdata(wdata), .s_axi_csr_wstrb(wstrb),
        .s_axi_csr_wvalid(wvalid), .s_axi_csr_wready(wready),
        .s_axi_csr_bresp(bresp), .s_axi_csr_bvalid(bvalid),
        .s_axi_csr_bready(bready), .s_axi_csr_araddr(araddr),
        .s_axi_csr_arprot(arprot), .s_axi_csr_arvalid(arvalid),
        .s_axi_csr_arready(arready), .s_axi_csr_rdata(rdata),
        .s_axi_csr_rresp(rresp), .s_axi_csr_rvalid(rvalid),
        .s_axi_csr_rready(rready),
        .ext_mem_init_done(1'b0), .ext_mem_init_error(1'b0),
        .m_axi_awid(m_awid), .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen),
        .m_axi_awsize(m_awsize), .m_axi_awburst(m_awburst),
        .m_axi_awlock(m_awlock), .m_axi_awcache(m_awcache),
        .m_axi_awprot(m_awprot), .m_axi_awqos(m_awqos),
        .m_axi_awvalid(m_awvalid), .m_axi_awready(1'b0),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb),
        .m_axi_wlast(m_wlast), .m_axi_wvalid(m_wvalid), .m_axi_wready(1'b0),
        .m_axi_bid(4'd0), .m_axi_bresp(2'b00), .m_axi_bvalid(1'b0),
        .m_axi_bready(m_bready), .m_axi_arid(m_arid),
        .m_axi_araddr(m_araddr), .m_axi_arlen(m_arlen),
        .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst),
        .m_axi_arlock(m_arlock), .m_axi_arcache(m_arcache),
        .m_axi_arprot(m_arprot), .m_axi_arqos(m_arqos),
        .m_axi_arvalid(m_arvalid), .m_axi_arready(1'b0),
        .m_axi_rid(4'd0), .m_axi_rdata(64'd0), .m_axi_rresp(2'b00),
        .m_axi_rlast(1'b0), .m_axi_rvalid(1'b0), .m_axi_rready(m_rready),
        .video_clk, .video_valid, .video_data, .video_de, .video_hsync,
        .video_vsync, .video_init_done, .video_init_error, .clock_locked,
        .mem_init_done, .mem_init_error, .system_busy, .system_error,
        .active_page, .pending_page, .page_flip_pending, .display_underflow,
        .command_submit_count(submit_count),
        .command_completed_count(completed_count)
    );

    task automatic axi_write(input logic [11:0] addr,
                             input logic [31:0] data);
        begin
            @(negedge clk);
            awaddr = addr; awvalid = 1'b1;
            wdata = data; wstrb = 4'hf; wvalid = 1'b1;
            while (awvalid || wvalid) begin
                @(posedge clk);
                if (awvalid && awready) awvalid = 1'b0;
                if (wvalid && wready) wvalid = 1'b0;
            end
            bready = 1'b1;
            do @(posedge clk); while (!bvalid);
            if (bresp != 2'b00)
                $fatal(1, "AXI4-Lite write failed addr=%h resp=%b", addr, bresp);
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task automatic axi_read(input logic [11:0] addr,
                            output logic [31:0] data);
        begin
            @(negedge clk);
            araddr = addr; arvalid = 1'b1;
            do @(posedge clk); while (!arready);
            @(negedge clk);
            arvalid = 1'b0; rready = 1'b1;
            do @(posedge clk); while (!rvalid);
            if (rresp != 2'b00)
                $fatal(1, "AXI4-Lite read failed addr=%h resp=%b", addr, rresp);
            data = rdata;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    integer k;
    integer guard;
    logic [31:0] completed_v;
    initial begin
        awaddr = '0; awprot = '0; awvalid = 1'b0;
        wdata = '0; wstrb = '0; wvalid = 1'b0; bready = 1'b0;
        araddr = '0; arprot = '0; arvalid = 1'b0; rready = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // Eight zero words form a legal NOP descriptor.
        for (k = 0; k < 8; k = k + 1)
            axi_write(12'(k * 4), 32'd0);
        axi_write(12'h020, 32'd1);

        guard = 0;
        while ((completed_count == 0) && (guard < 100)) begin
            @(posedge clk);
            guard = guard + 1;
        end
        if (completed_count != 1 || submit_count != 1)
            $fatal(1, "AXI shell NOP did not complete submit=%0d done=%0d",
                   submit_count, completed_count);
        axi_read(12'h034, completed_v);
        if (completed_v != 1)
            $fatal(1, "AXI CSR completed counter mismatch %0d", completed_v);
        if (m_awvalid || m_wvalid)
            $fatal(1, "NOP unexpectedly issued an AXI4 Full write");

        $display("TB_C2_RENDERER_SYSTEM_AXI_SHELL_PASS submit=%0d done=%0d",
                 submit_count, completed_v);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "tb_c2_renderer_system_axi_shell timeout");
    end
endmodule
