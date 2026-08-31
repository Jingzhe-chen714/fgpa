`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_csr_cmd_bridge
// -----------------------------------------------------------------------------
// Board-independent register boundary for the renderer.  An eventual
// AXI-Lite/APB slave (or Sapphire CSR block) only needs to translate its bus
// handshake into csr_valid/write/addr/wdata/rdata/ready.  The bridge stores
// eight 32-bit command words, queues a submit event behind one elastic slot,
// and exposes status/counters without embedding any vendor bus primitive.
//
// Register map (byte addresses):
//   0x00..0x1c  CMD_WORD0..CMD_WORD7
//   0x20        CMD_SUBMIT (write any value)
//   0x24        STATUS (read-only)
//   0x28        PAGE_REQUEST (write page index)
//   0x2c        PAGE_STATUS (read-only)
//   0x30..      counters / last parser error
//
// A submit write is accepted into the one-entry pending slot even when the
// command FIFO is full; csr_ready deasserts only while that slot is occupied.
// This keeps a slow CSR bus from needing to understand the downstream FIFO.
// -----------------------------------------------------------------------------
module c2_csr_cmd_bridge #(
    parameter int CMD_W  = 256,
    parameter int ADDR_W = 12,
    parameter int PAGE_W = 1
) (
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     csr_valid,
    input  logic                     csr_write,
    input  logic [ADDR_W-1:0]        csr_addr,
    input  logic [31:0]              csr_wdata,
    output logic [31:0]              csr_rdata,
    output logic                     csr_ready,

    output logic                     cmd_valid,
    input  logic                     cmd_ready,
    output logic [CMD_W-1:0]        cmd_data,

    output logic                     page_req_valid,
    input  logic                     page_req_ready,
    output logic [PAGE_W-1:0]       page_req_page,

    input  logic                     cmd_fifo_full,
    input  logic [15:0]              cmd_fifo_level,
    input  logic                     parser_busy,
    input  logic                     engine_busy,
    input  logic                     display_busy,
    input  logic                     display_underflow,
    input  logic                     mem_error,
    input  logic                     page_flip_pending,
    input  logic [PAGE_W-1:0]        active_page,
    input  logic [PAGE_W-1:0]        pending_page,

    input  logic [31:0]              accepted_count,
    input  logic [31:0]              completed_count,
    input  logic [31:0]              parser_memory_error_count,
    input  logic [31:0]              dropped_count,
    input  logic [31:0]              engine_request_count,
    input  logic [31:0]              engine_pixel_count,
    input  logic [31:0]              display_pixel_count,
    input  logic [31:0]              display_error_count,
    input  logic [31:0]              mem_read_count,
    input  logic [31:0]              mem_write_count,
    input  logic [31:0]              mem_response_count,
    input  logic                     parser_error_valid,
    input  logic [3:0]               parser_error_code,
    input  logic [31:0]              parser_error_seq,

    output logic [31:0]              submit_count,
    output logic [31:0]              page_submit_count
);

    localparam logic [ADDR_W-1:0] A_CMD0        = 12'h000;
    localparam logic [ADDR_W-1:0] A_CMD1        = 12'h004;
    localparam logic [ADDR_W-1:0] A_CMD2        = 12'h008;
    localparam logic [ADDR_W-1:0] A_CMD3        = 12'h00c;
    localparam logic [ADDR_W-1:0] A_CMD4        = 12'h010;
    localparam logic [ADDR_W-1:0] A_CMD5        = 12'h014;
    localparam logic [ADDR_W-1:0] A_CMD6        = 12'h018;
    localparam logic [ADDR_W-1:0] A_CMD7        = 12'h01c;
    localparam logic [ADDR_W-1:0] A_SUBMIT      = 12'h020;
    localparam logic [ADDR_W-1:0] A_STATUS      = 12'h024;
    localparam logic [ADDR_W-1:0] A_PAGE_REQ    = 12'h028;
    localparam logic [ADDR_W-1:0] A_PAGE_STATUS = 12'h02c;
    localparam logic [ADDR_W-1:0] A_ACCEPTED    = 12'h030;
    localparam logic [ADDR_W-1:0] A_COMPLETED   = 12'h034;
    localparam logic [ADDR_W-1:0] A_MEM_ERR     = 12'h038;
    localparam logic [ADDR_W-1:0] A_DROPPED     = 12'h03c;
    localparam logic [ADDR_W-1:0] A_REQ_COUNT   = 12'h040;
    localparam logic [ADDR_W-1:0] A_PIXEL_COUNT = 12'h044;
    localparam logic [ADDR_W-1:0] A_DISP_PIXELS = 12'h048;
    localparam logic [ADDR_W-1:0] A_DISP_ERRORS = 12'h04c;
    localparam logic [ADDR_W-1:0] A_MEM_READS   = 12'h050;
    localparam logic [ADDR_W-1:0] A_MEM_WRITES  = 12'h054;
    localparam logic [ADDR_W-1:0] A_MEM_RSP     = 12'h058;
    localparam logic [ADDR_W-1:0] A_LAST_ERROR  = 12'h05c;

    logic [31:0] cmd_words [0:7];
    logic [CMD_W-1:0] submit_data_q;
    logic submit_pending_q;
    logic page_pending_q;
    logic [PAGE_W-1:0] page_q;
    logic csr_fire;
    logic cmd_fire;
    logic page_fire;
    logic submit_addr;
    logic page_addr;

    assign submit_addr = (csr_addr == A_SUBMIT);
    assign page_addr   = (csr_addr == A_PAGE_REQ);

    always_comb begin
        // Normal registers are always accepted.  The two event registers have
        // one-entry elastic slots so a bus master can retry cleanly.
        csr_ready = rst_n &&
                    !(csr_valid && csr_write && submit_addr && submit_pending_q) &&
                    !(csr_valid && csr_write && page_addr && page_pending_q);
        csr_fire  = csr_valid && csr_ready;

        cmd_valid = submit_pending_q;
        cmd_data  = submit_data_q;
        cmd_fire  = cmd_valid && cmd_ready;

        page_req_valid = page_pending_q;
        page_req_page  = page_q;
        page_fire      = page_req_valid && page_req_ready;
    end

    always_comb begin
        csr_rdata = 32'd0;
        if (csr_addr == A_CMD0) csr_rdata = cmd_words[0];
        else if (csr_addr == A_CMD1) csr_rdata = cmd_words[1];
        else if (csr_addr == A_CMD2) csr_rdata = cmd_words[2];
        else if (csr_addr == A_CMD3) csr_rdata = cmd_words[3];
        else if (csr_addr == A_CMD4) csr_rdata = cmd_words[4];
        else if (csr_addr == A_CMD5) csr_rdata = cmd_words[5];
        else if (csr_addr == A_CMD6) csr_rdata = cmd_words[6];
        else if (csr_addr == A_CMD7) csr_rdata = cmd_words[7];
        else if (csr_addr == A_STATUS) begin
            csr_rdata[0] = cmd_fifo_full;
            csr_rdata[1] = parser_busy;
            csr_rdata[2] = engine_busy;
            csr_rdata[3] = display_busy;
            csr_rdata[4] = display_underflow;
            csr_rdata[5] = mem_error;
            csr_rdata[6] = page_flip_pending;
            csr_rdata[7] = submit_pending_q;
            csr_rdata[8] = page_pending_q;
            csr_rdata[15:9] = cmd_fifo_level[6:0];
        end else if (csr_addr == A_PAGE_STATUS) begin
            csr_rdata[PAGE_W-1:0] = active_page;
            csr_rdata[8 +: PAGE_W] = pending_page;
            csr_rdata[16] = page_flip_pending;
        end else if (csr_addr == A_ACCEPTED) begin
            csr_rdata = accepted_count;
        end else if (csr_addr == A_COMPLETED) begin
            csr_rdata = completed_count;
        end else if (csr_addr == A_MEM_ERR) begin
            csr_rdata = parser_memory_error_count;
        end else if (csr_addr == A_DROPPED) begin
            csr_rdata = dropped_count;
        end else if (csr_addr == A_REQ_COUNT) begin
            csr_rdata = engine_request_count;
        end else if (csr_addr == A_PIXEL_COUNT) begin
            csr_rdata = engine_pixel_count;
        end else if (csr_addr == A_DISP_PIXELS) begin
            csr_rdata = display_pixel_count;
        end else if (csr_addr == A_DISP_ERRORS) begin
            csr_rdata = display_error_count;
        end else if (csr_addr == A_MEM_READS) begin
            csr_rdata = mem_read_count;
        end else if (csr_addr == A_MEM_WRITES) begin
            csr_rdata = mem_write_count;
        end else if (csr_addr == A_MEM_RSP) begin
            csr_rdata = mem_response_count;
        end else if (csr_addr == A_LAST_ERROR) begin
            csr_rdata[0] = parser_error_valid;
            csr_rdata[7:4] = parser_error_code;
            csr_rdata[31:8] = parser_error_seq[23:0];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (integer i = 0; i < 8; i = i + 1)
                cmd_words[i] <= 32'd0;
            submit_data_q   <= '0;
            submit_pending_q <= 1'b0;
            page_pending_q  <= 1'b0;
            page_q          <= '0;
            submit_count    <= 32'd0;
            page_submit_count <= 32'd0;
        end else begin
            if (cmd_fire)
                submit_pending_q <= 1'b0;
            if (page_fire)
                page_pending_q <= 1'b0;

            if (csr_fire && csr_write) begin
                case (csr_addr)
                    A_CMD0: cmd_words[0] <= csr_wdata;
                    A_CMD1: cmd_words[1] <= csr_wdata;
                    A_CMD2: cmd_words[2] <= csr_wdata;
                    A_CMD3: cmd_words[3] <= csr_wdata;
                    A_CMD4: cmd_words[4] <= csr_wdata;
                    A_CMD5: cmd_words[5] <= csr_wdata;
                    A_CMD6: cmd_words[6] <= csr_wdata;
                    A_CMD7: cmd_words[7] <= csr_wdata;
                    A_SUBMIT: begin
                        submit_data_q <= {
                            cmd_words[7], cmd_words[6], cmd_words[5], cmd_words[4],
                            cmd_words[3], cmd_words[2], cmd_words[1], cmd_words[0]
                        };
                        submit_pending_q <= 1'b1;
                        submit_count <= submit_count + 32'd1;
                    end
                    A_PAGE_REQ: begin
                        page_q <= csr_wdata[PAGE_W-1:0];
                        page_pending_q <= 1'b1;
                        page_submit_count <= page_submit_count + 32'd1;
                    end
                    default: begin end
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (CMD_W != 256 || ADDR_W < 8 || PAGE_W <= 0)
            $error("c2_csr_cmd_bridge: unsupported parameterization");
    end
`endif
endmodule
