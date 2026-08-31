`timescale 1ns/1ps

// Structural smoke test for the complete board-independent R1 composition.
// It deliberately keeps all data-plane producers idle: the purpose is to
// prove that every portable RTL block compiles/elaborates together, all three
// reset domains release, and the APB control path remains reachable.
module tb_c1_r1_portable_soc_smoke;
`ifdef C1_PACKED_AFFINE_CACHE
    localparam integer PACKED_AFFINE_CACHE = 1;
`else
    localparam integer PACKED_AFFINE_CACHE = 0;
`endif
    logic core_clk = 1'b0;
    logic pixel_clk = 1'b0;
    logic camera_clk = 1'b0;
    logic arst_n = 1'b0;

    logic psel = 1'b0;
    logic penable = 1'b0;
    logic pwrite = 1'b0;
    logic [11:0] paddr = 12'd0;
    logic [31:0] pwdata = 32'd0;
    logic [3:0] pstrb = 4'd0;
    logic [31:0] prdata;
    logic pready;
    logic pslverr;

    logic camera_ready;
    logic camera_overflow;
    logic [23:0] video_rgb;
    logic video_de;
    logic video_hsync;
    logic video_vsync;
    logic [31:0] observed_id;
    logic m_axi_awvalid, m_axi_wvalid, m_axi_arvalid;

    always #5 core_clk = ~core_clk;
    always #7 pixel_clk = ~pixel_clk;
    always #6 camera_clk = ~camera_clk;

    c1_r1_portable_soc #(
        .PACKED_AFFINE_CACHE(PACKED_AFFINE_CACHE)
    ) dut (
        .core_clk(core_clk),
        .pixel_clk(pixel_clk),
        .camera_clk(camera_clk),
        .arst_n(arst_n),

        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .paddr(paddr),
        .pwdata(pwdata),
        .pstrb(pstrb),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),

        .camera_valid(1'b0),
        .camera_ready(camera_ready),
        .camera_raw10(10'd0),
        .camera_x('0),
        .camera_y('0),
        .camera_sof(1'b0),
        .camera_eol(1'b0),
        .camera_eof(1'b0),
        .camera_overflow(camera_overflow),

        .video_rgb(video_rgb),
        .video_de(video_de),
        .video_hsync(video_hsync),
        .video_vsync(video_vsync),

        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_arvalid(m_axi_arvalid),

        .m_axi_awready(1'b1),
        .m_axi_wready(1'b1),
        .m_axi_bresp(2'b00),
        .m_axi_bvalid(1'b0),
        .m_axi_arready(1'b1),
        .m_axi_rdata('0),
        .m_axi_rresp(2'b00),
        .m_axi_rlast(1'b0),
        .m_axi_rvalid(1'b0)
    );

    task automatic apb_read(
        input logic [11:0] address,
        output logic [31:0] data
    );
        begin
            @(negedge core_clk);
            psel <= 1'b1;
            penable <= 1'b0;
            pwrite <= 1'b0;
            paddr <= address;
            @(negedge core_clk);
            penable <= 1'b1;
            do @(negedge core_clk); while (!pready);
            data = prdata;
            if (pslverr) begin
                $fatal(1, "APB read at 0x%03x returned PSLVERR", address);
            end
            psel <= 1'b0;
            penable <= 1'b0;
            paddr <= 12'd0;
        end
    endtask

    task automatic apb_write(
        input logic [11:0] address,
        input logic [31:0] data
    );
        begin
            @(negedge core_clk);
            psel <= 1'b1;
            penable <= 1'b0;
            pwrite <= 1'b1;
            paddr <= address;
            pwdata <= data;
            pstrb <= 4'hf;
            @(negedge core_clk);
            penable <= 1'b1;
            do @(negedge core_clk); while (!pready);
            if (pslverr)
                $fatal(1, "APB write at 0x%03x returned PSLVERR", address);
            psel <= 1'b0;
            penable <= 1'b0;
            pwrite <= 1'b0;
            paddr <= 12'd0;
            pwdata <= 32'd0;
            pstrb <= 4'd0;
        end
    endtask

    initial begin
        repeat (6) @(posedge core_clk);
        arst_n <= 1'b1;
        repeat (8) @(posedge core_clk);

        apb_read(12'h000, observed_id);
        if (observed_id !== 32'h4331_5254) begin
            $fatal(1, "CSR ID mismatch: got 0x%08x", observed_id);
        end
        apb_read(12'h004, observed_id);
        if (observed_id !== 32'h0001_0100)
            $fatal(1, "CSR version mismatch: got 0x%08x", observed_id);
        apb_write(12'h098, 32'h0200_0000);
        apb_read(12'h098, observed_id);
        if (observed_id !== 32'h0200_0000)
            $fatal(1, "tensor arena CSR mismatch: got 0x%08x", observed_id);

        repeat (20) @(posedge core_clk);
        if (camera_overflow !== 1'b0) begin
            $fatal(1, "idle camera path unexpectedly overflowed");
        end
        if (m_axi_awvalid || m_axi_wvalid || m_axi_arvalid)
            $fatal(1, "idle integrated SoC issued a spurious AXI request");
        $display("C1_R1_PORTABLE_SOC_SMOKE_PASS tensor=%08x", observed_id);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "portable SoC smoke timeout");
    end
endmodule
