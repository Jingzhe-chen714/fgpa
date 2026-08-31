`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_framebuffer_reader
// -----------------------------------------------------------------------------
// Board-independent, one-outstanding-read scanout primitive.  It walks a
// linear RGB565 (or generally DATA_W-bit) rectangle row by row and presents
// the returned pixels on a ready/valid stream with x/y tags.  The module does
// not know about DDR, AXI, VGA or HDMI; an adapter only has to implement the
// abstract request/response contract used by the render engine.
//
// This is intentionally the correctness-first baseline: one memory beat is
// outstanding at a time and a response is held until the display-side sink
// accepts it.  A later line-buffer/burst version can preserve this interface
// while increasing the number of in-flight reads.  `done` is asserted after
// the final pixel has actually been consumed, so it is safe for a caller to
// reuse or flip the source page after the event.
//
// Addresses are byte addresses.  `stride_bytes` is the distance between row
// starts and `width`/`height` are in pixels.  For DATA_W=16 the alignment is
// two bytes and the normal RGB565 byte order is supplied by the memory
// adapter, not by this address generator.
// -----------------------------------------------------------------------------
module c2_framebuffer_reader #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 16,
    parameter int LEN_W  = 16,
    parameter int COORD_W = 16,
    parameter bit REQUIRE_LAST = 1'b1
) (
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     start,
    output logic                     start_ready,
    input  logic [ADDR_W-1:0]        base_addr,
    input  logic [15:0]              stride_bytes,
    input  logic [15:0]              width,
    input  logic [15:0]              height,

    output logic                     mem_req_valid,
    input  logic                     mem_req_ready,
    output logic                     mem_req_write,
    output logic [ADDR_W-1:0]        mem_req_addr,
    output logic [LEN_W-1:0]         mem_req_len,
    output logic [DATA_W-1:0]        mem_req_wdata,
    output logic [(DATA_W/8)-1:0]    mem_req_wstrb,

    input  logic                     mem_rsp_valid,
    output logic                     mem_rsp_ready,
    input  logic [DATA_W-1:0]        mem_rsp_rdata,
    input  logic                     mem_rsp_last,
    input  logic                     mem_rsp_error,

    output logic                     pixel_valid,
    input  logic                     pixel_ready,
    output logic [DATA_W-1:0]        pixel_data,
    output logic [COORD_W-1:0]       pixel_x,
    output logic [COORD_W-1:0]       pixel_y,
    output logic                     pixel_last,

    output logic                     busy,
    output logic                     done,
    output logic                     error,
    output logic [2:0]               error_code,
    output logic [31:0]              request_count,
    output logic [31:0]              read_count,
    output logic [31:0]              pixel_count,
    output logic [31:0]              error_count
);

    localparam int BYTE_LANES = DATA_W / 8;
    localparam logic [ADDR_W-1:0] BYTE_MASK = BYTE_LANES - 1;

    localparam logic [2:0] ERR_NONE       = 3'd0;
    localparam logic [2:0] ERR_BAD_PARAM  = 3'd1;
    localparam logic [2:0] ERR_MEM        = 3'd2;
    localparam logic [2:0] ERR_NO_LAST    = 3'd3;

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_REQ,
        ST_WAIT,
        ST_OUT
    } state_e;

    state_e state;

    logic [ADDR_W-1:0] cur_addr;
    logic [ADDR_W-1:0] stride_reg;
    logic [ADDR_W-1:0] row_step;
    logic [15:0]       width_reg;
    logic [15:0]       height_reg;
    logic [15:0]       x_reg;
    logic [15:0]       y_reg;

    logic [DATA_W-1:0]  pixel_data_q;
    logic [COORD_W-1:0] pixel_x_q;
    logic [COORD_W-1:0] pixel_y_q;
    logic               pixel_last_q;

    logic start_fire;
    logic req_fire;
    logic rsp_fire;
    logic pixel_fire;
    logic bad_start;
    logic last_pixel;

    always_comb begin
        // The row step is from the current row's final pixel to the first
        // pixel of the next row.  Sized casts avoid width-dependent
        // concatenation errors when ADDR_W is changed for a small test model.
        row_step = ADDR_W'(stride_reg) -
                   (ADDR_W'(width_reg) * BYTE_LANES) +
                   ADDR_W'(BYTE_LANES);
        last_pixel = (x_reg == (width_reg - 16'd1)) &&
                     (y_reg == (height_reg - 16'd1));

        busy       = (state != ST_IDLE);
        start_ready = (state == ST_IDLE);
        start_fire  = start && start_ready;

        mem_req_valid = (state == ST_REQ);
        mem_req_write = 1'b0;
        mem_req_addr  = cur_addr;
        mem_req_len   = '0;
        mem_req_wdata = '0;
        mem_req_wstrb = {(DATA_W/8){1'b1}};
        req_fire      = mem_req_valid && mem_req_ready;

        mem_rsp_ready = (state == ST_WAIT);
        rsp_fire      = mem_rsp_valid && mem_rsp_ready;

        pixel_valid = (state == ST_OUT);
        pixel_data  = pixel_data_q;
        pixel_x     = pixel_x_q;
        pixel_y     = pixel_y_q;
        pixel_last  = pixel_last_q;
        pixel_fire  = pixel_valid && pixel_ready;

        bad_start = (width == 16'd0) || (height == 16'd0) ||
                    ((base_addr & BYTE_MASK) != 0) ||
                    ((stride_bytes & BYTE_MASK) != 0) ||
                    ({1'b0, stride_bytes} <
                     ({1'b0, width} * BYTE_LANES));
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            cur_addr     <= '0;
            stride_reg   <= '0;
            width_reg    <= '0;
            height_reg   <= '0;
            x_reg        <= '0;
            y_reg        <= '0;
            pixel_data_q <= '0;
            pixel_x_q    <= '0;
            pixel_y_q    <= '0;
            pixel_last_q <= 1'b0;
            done         <= 1'b0;
            error        <= 1'b0;
            error_code   <= ERR_NONE;
            request_count <= 32'd0;
            read_count    <= 32'd0;
            pixel_count   <= 32'd0;
            error_count   <= 32'd0;
        end else begin
            done  <= 1'b0;
            error <= 1'b0;

            if (start_fire) begin
                if (bad_start) begin
                    // A rejected scan is still a completed transaction from
                    // the caller's point of view; `error` disambiguates it.
                    done       <= 1'b1;
                    error      <= 1'b1;
                    error_code <= ERR_BAD_PARAM;
                    error_count <= error_count + 32'd1;
                    state      <= ST_IDLE;
                end else begin
                    cur_addr   <= base_addr;
                    stride_reg <= stride_bytes;
                    width_reg  <= width;
                    height_reg <= height;
                    x_reg      <= 16'd0;
                    y_reg      <= 16'd0;
                    state      <= ST_REQ;
                end
            end else if (req_fire) begin
                request_count <= request_count + 32'd1;
                state <= ST_WAIT;
            end else if (rsp_fire) begin
                read_count <= read_count + 32'd1;
                if (mem_rsp_error || (REQUIRE_LAST && !mem_rsp_last)) begin
                    done       <= 1'b1;
                    error      <= 1'b1;
                    error_code <= mem_rsp_error ? ERR_MEM : ERR_NO_LAST;
                    error_count <= error_count + 32'd1;
                    state      <= ST_IDLE;
                end else begin
                    pixel_data_q <= mem_rsp_rdata;
                    pixel_x_q    <= COORD_W'(x_reg);
                    pixel_y_q    <= COORD_W'(y_reg);
                    pixel_last_q <= last_pixel;
                    state        <= ST_OUT;
                end
            end else if (pixel_fire) begin
                pixel_count <= pixel_count + 32'd1;
                if (pixel_last_q) begin
                    done  <= 1'b1;
                    error <= 1'b0;
                    state <= ST_IDLE;
                end else begin
                    if (x_reg == (width_reg - 16'd1)) begin
                        x_reg     <= 16'd0;
                        y_reg     <= y_reg + 16'd1;
                        cur_addr  <= cur_addr + row_step;
                    end else begin
                        x_reg     <= x_reg + 16'd1;
                        cur_addr  <= cur_addr + ADDR_W'(BYTE_LANES);
                    end
                    state <= ST_REQ;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (ADDR_W <= 0 || DATA_W <= 0 || (DATA_W % 8) != 0)
            $error("c2_framebuffer_reader: invalid address/data width");
        if (COORD_W < 16)
            $error("c2_framebuffer_reader: COORD_W must represent 16-bit coordinates");
        if (BYTE_LANES <= 0 || (BYTE_LANES & (BYTE_LANES - 1)) != 0)
            $error("c2_framebuffer_reader: DATA_W/8 must be a power of two");
    end
`endif

endmodule
