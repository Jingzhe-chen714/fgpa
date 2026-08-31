`timescale 1ns/1ps

// Behavioral write-side model for c2_burst_write_stream.  It accepts a
// descriptor first, then consumes a separate data stream.  No read response is
// generated; a real adapter may report write errors through a completion/status
// channel instead.
module render_write_burst_mem_model #(
    parameter int ADDR_W    = 32,
    parameter int DATA_W    = 16,
    parameter int LEN_W     = 16,
    parameter int MEM_BYTES = 65536
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     req_valid,
    output logic                     req_ready,
    input  logic                     req_write,
    input  logic [ADDR_W-1:0]        req_addr,
    input  logic [LEN_W-1:0]         req_len,
    input  logic [DATA_W-1:0]        req_wdata,
    input  logic [(DATA_W/8)-1:0]    req_wstrb,
    input  logic                     wr_valid,
    output logic                     wr_ready,
    input  logic [DATA_W-1:0]        wr_data,
    input  logic [(DATA_W/8)-1:0]    wr_strb,
    input  logic                     wr_last,
    output logic [31:0]              descriptor_count,
    output logic [31:0]              write_count,
    output logic [31:0]              error_count
);
    localparam int BYTE_LANES = DATA_W / 8;
    localparam int MEM_WORDS  = (MEM_BYTES + BYTE_LANES - 1) / BYTE_LANES;

    logic [DATA_W-1:0] mem [0:MEM_WORDS-1];
    logic active_q;
    logic [ADDR_W-1:0] addr_q;
    logic [LEN_W:0] beats_left_q;
    integer req_word_index;
    integer write_word_index;
    integer lane;
    logic req_oob;
    logic write_oob;
    logic req_fire;
    logic wr_fire;
    logic expected_last;

    always_comb begin
        req_word_index   = req_addr / BYTE_LANES;
        write_word_index = addr_q / BYTE_LANES;
        req_oob          = (req_word_index < 0) || (req_word_index >= MEM_WORDS);
        write_oob         = (write_word_index < 0) ||
                            (write_word_index >= MEM_WORDS);

        req_ready = !active_q;
        req_fire  = req_valid && req_ready;
        wr_ready  = active_q && (beats_left_q != 0);
        wr_fire   = wr_valid && wr_ready;
        expected_last = (beats_left_q == {{LEN_W{1'b0}}, 1'b1});
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_q         <= 1'b0;
            addr_q           <= '0;
            beats_left_q     <= '0;
            descriptor_count <= 32'd0;
            write_count      <= 32'd0;
            error_count      <= 32'd0;
        end else begin
            if (req_fire) begin
                descriptor_count <= descriptor_count + 32'd1;
                if (!req_write) begin
                    // This model is intentionally write-only.
                    error_count <= error_count + 32'd1;
                end else begin
                    active_q     <= 1'b1;
                    addr_q       <= req_addr;
                    beats_left_q <= {1'b0, req_len} + 1'b1;
                    if (req_oob)
                        error_count <= error_count + 32'd1;
                end
            end

            if (wr_fire) begin
                write_count <= write_count + 32'd1;
                if ((wr_last != expected_last) || write_oob)
                    error_count <= error_count + 32'd1;

                if (!write_oob) begin
                    for (lane = 0; lane < BYTE_LANES; lane = lane + 1) begin
                        if (wr_strb[lane])
                            mem[write_word_index][lane*8 +: 8] <=
                                wr_data[lane*8 +: 8];
                    end
                end

                if (wr_last || expected_last) begin
                    active_q     <= 1'b0;
                    beats_left_q <= '0;
                end else begin
                    addr_q       <= addr_q + ADDR_W'(BYTE_LANES);
                    beats_left_q <= beats_left_q - 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (ADDR_W <= 0 || DATA_W <= 0 || (DATA_W % 8) != 0 || LEN_W <= 0 ||
            MEM_BYTES <= 0)
            $error("render_write_burst_mem_model: invalid parameter");
    end
`endif
endmodule
