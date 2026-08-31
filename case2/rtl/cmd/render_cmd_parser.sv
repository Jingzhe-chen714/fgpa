`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// render_cmd_parser
// -----------------------------------------------------------------------------
// Decodes the canonical 256-bit command packet described in
// rtl/common/renderer_pkg.sv and presents a one-entry elastic descriptor
// stream.  The parser intentionally has no knowledge of DDR/AXI or of a
// renderer top-level.  It is therefore useful both directly after a command
// FIFO and as the boundary of a software/CSR adapter.
//
// Input and output obey the normal ready/valid rule.  A malformed packet is
// consumed, produces a one-cycle `error_valid` event, and is not emitted on the
// descriptor stream.  A valid packet remains stable until `desc_ready` is
// asserted.  `cmd_ready` also permits replacement in the same cycle in which a
// pending descriptor is consumed.
//
// Validation performed here (first matching error wins):
//   1. op is one of NOP, SOLID_FILL, BLOCK_COPY, ALPHA_BLEND, COLOR_KEY;
//   2. pixel format is RGB565 (2'b00);
//   3. non-NOP dimensions are non-zero;
//   4. destination stride is even and at least width*2; source stride obeys
//      the same rule for operations which read a source surface;
//   5. addresses are 16-bit pixel aligned for operations that use them.
//
// The parser does not silently resolve overlapping BLOCK_COPY rectangles.  A
// caller that needs overlap-safe movement must stage a safe command sequence.
// -----------------------------------------------------------------------------
module render_cmd_parser #(
    parameter int CMD_W = 256,
    parameter int SEQ_W = 32
) (
    input  logic                 clk,
    input  logic                 rst_n,

    input  logic                 cmd_valid,
    output logic                 cmd_ready,
    input  logic [CMD_W-1:0]     cmd_data,

    output logic                 desc_valid,
    input  logic                 desc_ready,
    output logic [CMD_W-1:0]     desc_raw,
    output logic [SEQ_W-1:0]     desc_seq,
    output logic [2:0]           desc_op,
    output logic [7:0]           desc_flags,
    output logic [1:0]           desc_pixel_fmt,
    output logic [31:0]          desc_src_addr,
    output logic [31:0]          desc_dst_addr,
    output logic [15:0]          desc_width,
    output logic [15:0]          desc_height,
    output logic [15:0]          desc_src_stride_bytes,
    output logic [15:0]          desc_dst_stride_bytes,
    output logic [31:0]          desc_color,
    output logic [7:0]           desc_alpha,
    output logic [15:0]          desc_color_key,

    output logic                 accept_event,
    output logic                 error_valid,
    output logic [3:0]           error_code,
    output logic [SEQ_W-1:0]     error_seq,

    // Completion events are supplied by the operation/memory engine.  They
    // are deliberately event inputs rather than a hidden dependency on a
    // particular operation implementation.
    input  logic                 done_valid,
    input  logic                 done_error,

    output logic [31:0]          accepted_count,
    output logic [31:0]          completed_count,
    output logic [31:0]          memory_error_count,
    output logic [31:0]          dropped_count,
    output logic                 busy
);

    // Canonical packet slices.  Keeping explicit slices here makes this
    // module usable with plain Verilog testbenches without requiring a packed
    // struct cast in the testbench.
    logic [2:0]   in_op;
    logic [7:0]   in_flags;
    logic [1:0]   in_pixel_fmt;
    logic [31:0]  in_src_addr;
    logic [31:0]  in_dst_addr;
    logic [15:0]  in_width;
    logic [15:0]  in_height;
    logic [15:0]  in_src_stride;
    logic [15:0]  in_dst_stride;
    logic [31:0]  in_color;
    logic [7:0]   in_alpha;
    logic [15:0]  in_color_key;

    always_comb begin
        in_op         = cmd_data[2:0];
        in_flags      = cmd_data[10:3];
        in_pixel_fmt  = cmd_data[12:11];
        in_src_addr   = cmd_data[47:16];
        in_dst_addr   = cmd_data[79:48];
        in_width      = cmd_data[95:80];
        in_height     = cmd_data[111:96];
        in_src_stride  = cmd_data[127:112];
        in_dst_stride  = cmd_data[143:128];
        in_color      = cmd_data[175:144];
        in_alpha      = cmd_data[183:176];
        in_color_key  = cmd_data[199:184];
    end

    localparam logic [2:0] OP_NOP_C         = 3'd0;
    localparam logic [2:0] OP_SOLID_FILL_C  = 3'd1;
    localparam logic [2:0] OP_BLOCK_COPY_C  = 3'd2;
    localparam logic [2:0] OP_ALPHA_BLEND_C = 3'd3;
    localparam logic [2:0] OP_COLOR_KEY_C   = 3'd4;
    localparam logic [1:0] PIXEL_FMT_RGB565_C = 2'd0;

    localparam logic [3:0] ERR_NONE       = 4'd0;
    localparam logic [3:0] ERR_BAD_OP     = 4'd1;
    localparam logic [3:0] ERR_BAD_FORMAT = 4'd2;
    localparam logic [3:0] ERR_BAD_SIZE   = 4'd3;
    localparam logic [3:0] ERR_BAD_STRIDE = 4'd4;
    localparam logic [3:0] ERR_BAD_ALIGN = 4'd5;

    logic                 packet_ok;
    logic [3:0]           packet_error;
    logic [16:0]          min_stride;
    logic                 needs_source;
    logic                 cmd_fire;
    logic                 desc_fire;
    logic                 pending;
    logic [SEQ_W-1:0]     seq_counter;

    always_comb begin
        min_stride  = {1'b0, in_width} << 1;
        needs_source = (in_op == OP_BLOCK_COPY_C) ||
                       (in_op == OP_ALPHA_BLEND_C) ||
                       (in_op == OP_COLOR_KEY_C);

        packet_ok    = 1'b1;
        packet_error = ERR_NONE;

        if (in_op > OP_COLOR_KEY_C) begin
            packet_ok    = 1'b0;
            packet_error = ERR_BAD_OP;
        end else if (in_pixel_fmt != PIXEL_FMT_RGB565_C) begin
            packet_ok    = 1'b0;
            packet_error = ERR_BAD_FORMAT;
        end else if ((in_op != OP_NOP_C) &&
                     ((in_width == 16'd0) || (in_height == 16'd0))) begin
            packet_ok    = 1'b0;
            packet_error = ERR_BAD_SIZE;
        end else if ((in_op != OP_NOP_C) &&
                     (in_dst_stride[0] ||
                      ({1'b0, in_dst_stride} < min_stride) ||
                      (needs_source &&
                       (in_src_stride[0] ||
                        ({1'b0, in_src_stride} < min_stride))))) begin
            // An aligned base is insufficient when an odd byte stride makes
            // the next RGB565 row unaligned. Reject before any row is issued.
            packet_ok    = 1'b0;
            packet_error = ERR_BAD_STRIDE;
        end else if ((in_op != OP_NOP_C) &&
                     (in_dst_addr[0] || (needs_source && in_src_addr[0]))) begin
            packet_ok    = 1'b0;
            packet_error = ERR_BAD_ALIGN;
        end
    end

    logic [CMD_W-1:0] raw_reg;
    logic [SEQ_W-1:0] seq_reg;
    logic [2:0]       op_reg;
    logic [7:0]       flags_reg;
    logic [1:0]       pixel_fmt_reg;
    logic [31:0]      src_addr_reg;
    logic [31:0]      dst_addr_reg;
    logic [15:0]      width_reg;
    logic [15:0]      height_reg;
    logic [15:0]      src_stride_reg;
    logic [15:0]      dst_stride_reg;
    logic [31:0]      color_reg;
    logic [7:0]       alpha_reg;
    logic [15:0]      color_key_reg;

    always_comb begin
        desc_valid = pending;
        busy       = pending;
        // Elastic one-entry output.  If the current descriptor is consumed in
        // this cycle, a new input may be accepted without a bubble.
        cmd_ready  = !pending || desc_ready;
        cmd_fire   = cmd_valid && cmd_ready;
        desc_fire  = desc_valid && desc_ready;

        desc_raw   = raw_reg;
        desc_seq   = seq_reg;
        desc_op    = op_reg;
        desc_flags = flags_reg;
        desc_pixel_fmt = pixel_fmt_reg;
        desc_src_addr = src_addr_reg;
        desc_dst_addr = dst_addr_reg;
        desc_width = width_reg;
        desc_height = height_reg;
        desc_src_stride_bytes = src_stride_reg;
        desc_dst_stride_bytes = dst_stride_reg;
        desc_color = color_reg;
        desc_alpha = alpha_reg;
        desc_color_key = color_key_reg;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending            <= 1'b0;
            seq_counter       <= '0;
            raw_reg            <= '0;
            seq_reg            <= '0;
            op_reg             <= OP_NOP_C;
            flags_reg          <= '0;
            pixel_fmt_reg      <= PIXEL_FMT_RGB565_C;
            src_addr_reg       <= '0;
            dst_addr_reg       <= '0;
            width_reg          <= '0;
            height_reg         <= '0;
            src_stride_reg     <= '0;
            dst_stride_reg     <= '0;
            color_reg          <= '0;
            alpha_reg          <= '0;
            color_key_reg      <= '0;
            accept_event       <= 1'b0;
            error_valid        <= 1'b0;
            error_code         <= ERR_NONE;
            error_seq          <= '0;
            accepted_count     <= 32'd0;
            completed_count    <= 32'd0;
            memory_error_count <= 32'd0;
            dropped_count      <= 32'd0;
        end else begin
            accept_event <= 1'b0;
            error_valid  <= 1'b0;

            if (done_valid) begin
                completed_count <= completed_count + 32'd1;
                if (done_error)
                    memory_error_count <= memory_error_count + 32'd1;
            end

            if (cmd_fire) begin
                accept_event   <= 1'b1;
                accepted_count <= accepted_count + 32'd1;
                seq_reg        <= seq_counter;
                seq_counter    <= seq_counter + 1'b1;

                if (packet_ok) begin
                    pending       <= 1'b1;
                    raw_reg       <= cmd_data;
                    op_reg        <= in_op;
                    flags_reg     <= in_flags;
                    pixel_fmt_reg <= in_pixel_fmt;
                    src_addr_reg  <= in_src_addr;
                    dst_addr_reg  <= in_dst_addr;
                    width_reg     <= in_width;
                    height_reg    <= in_height;
                    src_stride_reg <= in_src_stride;
                    dst_stride_reg <= in_dst_stride;
                    color_reg     <= in_color;
                    alpha_reg     <= in_alpha;
                    color_key_reg <= in_color_key;
                end else begin
                    // Invalid commands are intentionally not queued.  The
                    // event is synchronous and can be captured by a status
                    // register or a scoreboard in the same clock domain.
                    pending     <= 1'b0;
                    error_valid <= 1'b1;
                    error_code  <= packet_error;
                    error_seq   <= seq_counter;
                    dropped_count <= dropped_count + 32'd1;
                end
            end else if (desc_fire) begin
                pending <= 1'b0;
            end
        end
    end

endmodule
