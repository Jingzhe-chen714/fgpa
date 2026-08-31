`timescale 1ns/1ps

module tb_c2_axi4lite_csr_adapter;
    localparam int ADDR_W = 12;
    localparam int DATA_W = 32;
    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    logic clk;
    logic rst_n;

    logic [ADDR_W-1:0] s_axi_awaddr;
    logic [2:0]        s_axi_awprot;
    logic              s_axi_awvalid;
    logic              s_axi_awready;
    logic [DATA_W-1:0] s_axi_wdata;
    logic [3:0]        s_axi_wstrb;
    logic              s_axi_wvalid;
    logic              s_axi_wready;
    logic [1:0]        s_axi_bresp;
    logic              s_axi_bvalid;
    logic              s_axi_bready;
    logic [ADDR_W-1:0] s_axi_araddr;
    logic [2:0]        s_axi_arprot;
    logic              s_axi_arvalid;
    logic              s_axi_arready;
    logic [DATA_W-1:0] s_axi_rdata;
    logic [1:0]        s_axi_rresp;
    logic              s_axi_rvalid;
    logic              s_axi_rready;

    logic              csr_valid;
    logic              csr_write;
    logic [ADDR_W-1:0] csr_addr;
    logic [DATA_W-1:0] csr_wdata;
    logic [DATA_W-1:0] csr_rdata;
    logic              csr_ready;

    logic [31:0] csr_mem [0:63];
    logic csr_allow;
    integer errors;
    integer csr_fire_count;
    integer csr_write_count;
    integer csr_read_count;
    integer trace_count;
    logic trace_write [0:15];
    logic [ADDR_W-1:0] trace_addr [0:15];

    c2_axi4lite_csr_adapter #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W)
    ) dut (
        .clk,
        .rst_n,
        .s_axi_awaddr,
        .s_axi_awprot,
        .s_axi_awvalid,
        .s_axi_awready,
        .s_axi_wdata,
        .s_axi_wstrb,
        .s_axi_wvalid,
        .s_axi_wready,
        .s_axi_bresp,
        .s_axi_bvalid,
        .s_axi_bready,
        .s_axi_araddr,
        .s_axi_arprot,
        .s_axi_arvalid,
        .s_axi_arready,
        .s_axi_rdata,
        .s_axi_rresp,
        .s_axi_rvalid,
        .s_axi_rready,
        .csr_valid,
        .csr_write,
        .csr_addr,
        .csr_wdata,
        .csr_rdata,
        .csr_ready
    );

    always #5 clk = ~clk;

    assign csr_ready = csr_allow;
    always_comb csr_rdata = csr_mem[csr_addr[7:2]];

    // Plain procedural block is intentional in this testbench: counters and
    // RAM are initialized by the stimulus process before this monitor drives
    // them.  Vivado correctly rejects that pattern when written as always_ff.
    always @(posedge clk) begin
        if (rst_n && csr_valid && csr_ready) begin
            csr_fire_count <= csr_fire_count + 1;
            trace_write[trace_count] <= csr_write;
            trace_addr[trace_count]  <= csr_addr;
            trace_count <= trace_count + 1;
            if (csr_write) begin
                csr_mem[csr_addr[7:2]] <= csr_wdata;
                csr_write_count <= csr_write_count + 1;
            end else begin
                csr_read_count <= csr_read_count + 1;
            end
        end
    end

    task automatic check(input logic condition, input string message);
        begin
            if (!condition) begin
                $error("CHECK FAILED: %s", message);
                errors = errors + 1;
            end
        end
    endtask

    task automatic send_aw(input logic [ADDR_W-1:0] addr);
        begin
            @(negedge clk);
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;
            do @(posedge clk); while (!s_axi_awready);
            @(negedge clk);
            s_axi_awvalid = 1'b0;
        end
    endtask

    task automatic send_w(
        input logic [DATA_W-1:0] data,
        input logic [3:0]        strb
    );
        begin
            @(negedge clk);
            s_axi_wdata  = data;
            s_axi_wstrb  = strb;
            s_axi_wvalid = 1'b1;
            do @(posedge clk); while (!s_axi_wready);
            @(negedge clk);
            s_axi_wvalid = 1'b0;
        end
    endtask

    task automatic send_ar(input logic [ADDR_W-1:0] addr);
        begin
            @(negedge clk);
            s_axi_araddr  = addr;
            s_axi_arvalid = 1'b1;
            do @(posedge clk); while (!s_axi_arready);
            @(negedge clk);
            s_axi_arvalid = 1'b0;
        end
    endtask

    task automatic wait_csr_valid;
        begin
            while (!csr_valid)
                @(posedge clk);
            #1;
        end
    endtask

    task automatic wait_bvalid;
        begin
            while (!s_axi_bvalid)
                @(posedge clk);
            #1;
        end
    endtask

    task automatic wait_rvalid;
        begin
            while (!s_axi_rvalid)
                @(posedge clk);
            #1;
        end
    endtask

    task automatic consume_b;
        begin
            @(negedge clk);
            s_axi_bready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            s_axi_bready = 1'b0;
        end
    endtask

    task automatic consume_r;
        begin
            @(negedge clk);
            s_axi_rready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            s_axi_rready = 1'b0;
        end
    endtask

    initial begin : timeout_guard
        #20000;
        $fatal(1, "TB_C2_AXI4LITE_CSR_ADAPTER_TIMEOUT");
    end

    initial begin : stimulus
        logic [1:0] held_bresp;
        logic [1:0] held_rresp;
        logic [31:0] held_rdata;
        integer before_count;
        integer before_trace;
        integer i;

        clk = 1'b0;
        rst_n = 1'b0;
        s_axi_awaddr = '0;
        s_axi_awprot = '0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata = '0;
        s_axi_wstrb = '0;
        s_axi_wvalid = 1'b0;
        s_axi_bready = 1'b0;
        s_axi_araddr = '0;
        s_axi_arprot = '0;
        s_axi_arvalid = 1'b0;
        s_axi_rready = 1'b0;
        csr_allow = 1'b0;
        errors = 0;
        csr_fire_count = 0;
        csr_write_count = 0;
        csr_read_count = 0;
        trace_count = 0;
        for (i = 0; i < 64; i = i + 1)
            csr_mem[i] = 32'h0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // W before AW: neither channel depends on the other's VALID.  Once the
        // address arrives, the complete write is held on CSR backpressure.
        send_w(32'h1122_3344, 4'hf);
        repeat (2) begin
            @(posedge clk);
            #1;
            check(!csr_valid, "W-only request must not reach CSR");
        end
        send_aw(12'h010);
        wait_csr_valid();
        check(csr_write, "W-before-AW must become CSR write");
        check(csr_addr == 12'h010, "CSR write address mismatch");
        check(csr_wdata == 32'h1122_3344, "CSR write data mismatch");
        repeat (3) begin
            @(posedge clk);
            #1;
            check(csr_valid && csr_write, "CSR write must remain valid while stalled");
            check(csr_addr == 12'h010 && csr_wdata == 32'h1122_3344,
                  "CSR write payload changed while stalled");
        end
        @(negedge clk);
        csr_allow = 1'b1;
        @(posedge clk);
        #1;
        csr_allow = 1'b0;
        wait_bvalid();
        check(s_axi_bresp == AXI_RESP_OKAY, "full-word write must return OKAY");
        check(csr_mem[4] == 32'h1122_3344, "CSR model did not receive W-before-AW write");

        // B must be registered and stable until the AXI master accepts it.
        held_bresp = s_axi_bresp;
        repeat (3) begin
            @(posedge clk);
            #1;
            check(s_axi_bvalid, "BVALID dropped under backpressure");
            check(s_axi_bresp == held_bresp, "BRESP changed under backpressure");
        end
        consume_b();

        // AW before W exercises the opposite independent-channel ordering.
        send_aw(12'h014);
        repeat (2) begin
            @(posedge clk);
            #1;
            check(!csr_valid, "AW-only request must not reach CSR");
        end
        send_w(32'ha5a5_5a5a, 4'hf);
        @(negedge clk);
        csr_allow = 1'b1;
        wait_bvalid();
        csr_allow = 1'b0;
        check(s_axi_bresp == AXI_RESP_OKAY, "AW-before-W must return OKAY");
        check(csr_mem[5] == 32'ha5a5_5a5a, "CSR model did not receive AW-before-W write");
        consume_b();

        // Partial writes are deliberately rejected because the downstream CSR
        // interface has no byte enable.  No CSR access or memory update occurs.
        before_count = csr_fire_count;
        csr_mem[6] = 32'hfeed_cafe;
        fork
            send_aw(12'h018);
            send_w(32'hdead_beef, 4'b0011);
        join
        wait_bvalid();
        check(s_axi_bresp == AXI_RESP_SLVERR, "partial write must return SLVERR");
        check(csr_fire_count == before_count, "partial write leaked to CSR port");
        check(csr_mem[6] == 32'hfeed_cafe, "partial write modified CSR state");
        consume_b();

        // Read response and CSR request both remain stable through stalls.
        csr_mem[8] = 32'hc001_d00d;
        send_ar(12'h020);
        wait_csr_valid();
        check(!csr_write && csr_addr == 12'h020, "read CSR request mismatch");
        repeat (3) begin
            @(posedge clk);
            #1;
            check(csr_valid && !csr_write && csr_addr == 12'h020,
                  "CSR read changed while stalled");
        end
        @(negedge clk);
        csr_allow = 1'b1;
        @(posedge clk);
        #1;
        csr_allow = 1'b0;
        wait_rvalid();
        check(s_axi_rresp == AXI_RESP_OKAY, "CSR read must return OKAY");
        check(s_axi_rdata == 32'hc001_d00d, "CSR read data mismatch");
        held_rdata = s_axi_rdata;
        held_rresp = s_axi_rresp;
        repeat (3) begin
            @(posedge clk);
            #1;
            check(s_axi_rvalid, "RVALID dropped under backpressure");
            check(s_axi_rdata == held_rdata && s_axi_rresp == held_rresp,
                  "read payload changed under backpressure");
        end
        consume_r();

        // A simultaneously queued read and complete write exercise arbitration.
        // The documented policy is write first, followed by the read.
        csr_mem[9] = 32'h7654_3210;
        before_trace = trace_count;
        @(negedge clk);
        csr_allow = 1'b1;
        fork
            send_aw(12'h028);
            send_w(32'h89ab_cdef, 4'hf);
            send_ar(12'h024);
        join
        wait_bvalid();
        wait_rvalid();
        #1;
        check(trace_count == before_trace + 2, "simultaneous read/write CSR count mismatch");
        check(trace_write[before_trace] && trace_addr[before_trace] == 12'h028,
              "write did not win simultaneous CSR arbitration");
        check(!trace_write[before_trace+1] && trace_addr[before_trace+1] == 12'h024,
              "read did not execute after simultaneous write");
        check(csr_mem[10] == 32'h89ab_cdef, "arbitrated write data mismatch");
        check(s_axi_rdata == 32'h7654_3210, "arbitrated read data mismatch");
        check(s_axi_bresp == AXI_RESP_OKAY && s_axi_rresp == AXI_RESP_OKAY,
              "arbitrated responses must be OKAY");
        csr_allow = 1'b0;
        fork
            consume_b();
            consume_r();
        join

        repeat (2) @(posedge clk);
        check(csr_write_count == 3, "unexpected successful CSR write count");
        check(csr_read_count == 2, "unexpected CSR read count");

        if (errors == 0) begin
            $display("TB_C2_AXI4LITE_CSR_ADAPTER_PASS csr=%0d writes=%0d reads=%0d",
                     csr_fire_count, csr_write_count, csr_read_count);
            $finish;
        end else begin
            $fatal(1, "TB_C2_AXI4LITE_CSR_ADAPTER_FAIL errors=%0d", errors);
        end
    end

endmodule
