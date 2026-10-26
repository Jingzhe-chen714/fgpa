`timescale 1ns/1ps
// V10: streaming exposure-based gamma, with no frame or line memory.
//
// Three registered pixel stages. HS, VS and DE travel through the same stages
// as RGB. frame_start is an explicit ONE-CLOCK pulse (normally in vertical
// blank); the first active pixel may coincide with it. source_id/source_fresh
// must identify the ORIGINAL source image, not the repeated HDMI refresh.
// source_fresh=0 excludes a frame from exposure statistics but never gates
// its pixels. Consecutive repeats of a previously sampled source_id are also
// excluded. An empty frame does not consume its source_id.
//
// Mean is sampled from UNCORRECTED RGB using Y=(R+2G+B+2)/4. One out of every
// 2**SAMPLE_LOG2 active pixels is sampled; the first pixel is always sampled.
// A 32-clock restoring divider computes a real measured mean, not a division
// by a presumed frame size. Q4 IIR smoothing and +/-8-level hysteresis select
// one adjacent gamma step per accepted unique source frame. The pending step
// is applied only at frame_start. Enable is also frame-latched.
//
// V12 gamma levels: 0=0.65, 1=0.80, 2=1.00 (exact bypass), 3=1.25, 4=1.50.
// Neutral-band hysteresis is narrowed for visibly under/overexposed scenes.
// Curves remain monotonic with exact black/white endpoints; raw source mean
// and frame-only updates prevent feedback and within-frame brightness jumps.
// Formula: output=255*(input/255)**gamma. Dense dark-value knots preserve
// detail; max 8-bit approximation error is one level versus this formula.
// No RAM, DSP, general multiply or combinational divide is required: constant
// coefficient case tables and 5 shift/add terms implement each channel.
// Stats must have >=33 clocks between completed sampled frames. An overrun
// skips that mean and asserts stats_overrun for one clock, without corrupting
// video. A 24-bit sample count supports up to 16,777,215 samples per frame;
// extra samples are ignored and stats_overflow is sticky until reset.
module case4_v10_gamma #(
    parameter integer SAMPLE_LOG2 = 4
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        frame_start,
    input  wire        source_fresh,
    input  wire [31:0] source_id,
    input  wire        in_hs, in_vs, in_de,
    input  wire [23:0] in_rgb,
    output wire        out_hs, out_vs, out_de,
    output wire [23:0] out_rgb,
    output reg         enable_active,
    output reg  [2:0]  gamma_level,
    output reg  [7:0]  mean_gray,
    output reg  [7:0]  smoothed_gray,
    output reg         mean_valid,
    output reg  [31:0] mean_source_id,
    output reg         stats_overrun,
    output reg         stats_overflow
);
    localparam integer SAMPLE_BITS = SAMPLE_LOG2 < 1 ? 1 : SAMPLE_LOG2;
    reg [SAMPLE_BITS-1:0] sample_phase;
    reg frame_open, collect_frame, last_source_valid;
    reg [31:0] frame_source_id, last_source_id;
    reg [31:0] frame_sum;
    reg [23:0] frame_count;
    wire [9:0] raw_y_sum = {2'b0,in_rgb[23:16]} +
                            {1'b0,in_rgb[15:8],1'b0} +
                            {2'b0,in_rgb[7:0]} + 10'd2;
    wire [7:0] raw_y = raw_y_sum[9:2];
    wire accept_new_source = source_fresh &&
                             (!last_source_valid || source_id != last_source_id);

    reg div_busy;
    reg [5:0] div_bit;
    reg [31:0] div_numerator, div_quotient, div_source_id;
    reg [23:0] div_denominator;
    reg [24:0] div_remainder;
    wire [24:0] trial_remainder = {div_remainder[23:0],div_numerator[31]};
    wire quotient_bit = trial_remainder >= {1'b0,div_denominator};
    wire [31:0] quotient_next = {div_quotient[30:0],quotient_bit};
    reg mean_seen;
    reg [11:0] filtered_q4;
    reg [2:0] level_request;
    wire [13:0] filter_total = {2'b0,filtered_q4} +
                               {1'b0,filtered_q4,1'b0} +
                               {2'b0,quotient_next[7:0],4'b0} + 14'd2;
    wire [11:0] filter_next = mean_seen ? filter_total[13:2] :
                                                    {quotient_next[7:0],4'b0};
    wire [12:0] rounded_filter = {1'b0,filter_next} + 13'd8;
    wire [7:0] next_smoothed_gray = rounded_filter[11:4];

    function [2:0] select_level;
        input [2:0] current_level;
        input [7:0] measured;
        begin
            case (current_level)
                3'd0: select_level = measured >= 8'd80  ? 3'd1 : 3'd0;
                3'd1: select_level = measured < 8'd64   ? 3'd0 :
                                      measured >= 8'd128 ? 3'd2 : 3'd1;
                3'd2: select_level = measured < 8'd112  ? 3'd1 :
                                      measured >= 8'd152 ? 3'd3 : 3'd2;
                3'd3: select_level = measured < 8'd136  ? 3'd2 :
                                      measured >= 8'd200 ? 3'd4 : 3'd3;
                3'd4: select_level = measured < 8'd184  ? 3'd3 : 3'd4;
                default: select_level = 3'd2;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            sample_phase <= 0;
            frame_open <= 0; collect_frame <= 0;
            frame_source_id <= 0; last_source_id <= 0; last_source_valid <= 0;
            frame_sum <= 0; frame_count <= 0;
            div_busy <= 0; div_bit <= 0; div_numerator <= 0;
            div_quotient <= 0; div_denominator <= 0; div_remainder <= 0;
            div_source_id <= 0;
            mean_seen <= 0; filtered_q4 <= 12'd2048;
            mean_gray <= 8'd128; smoothed_gray <= 8'd128;
            mean_valid <= 0; mean_source_id <= 0;
            gamma_level <= 3'd2; level_request <= 3'd2; enable_active <= 0;
            stats_overrun <= 0; stats_overflow <= 0;
        end else begin
            mean_valid <= 0;
            stats_overrun <= 0;
            if (div_busy) begin
                div_numerator <= {div_numerator[30:0],1'b0};
                div_quotient <= quotient_next;
                div_remainder <= quotient_bit ?
                    trial_remainder - {1'b0,div_denominator} : trial_remainder;
                if (div_bit == 0) begin
                    div_busy <= 0;
                    mean_gray <= quotient_next[7:0];
                    filtered_q4 <= filter_next;
                    smoothed_gray <= next_smoothed_gray;
                    mean_seen <= 1;
                    mean_valid <= 1;
                    mean_source_id <= div_source_id;
                    level_request <= select_level(gamma_level, next_smoothed_gray);
                end else div_bit <= div_bit - 1'b1;
            end
            if (frame_start) begin
                enable_active <= enable;
                gamma_level <= level_request;
                if (frame_open && collect_frame && frame_count != 0) begin
                    if (!div_busy) begin
                        // Rounding is done once, before the serial division.
                        div_numerator <= frame_sum + {9'd0,frame_count[23:1]};
                        div_denominator <= frame_count;
                        div_remainder <= 0; div_quotient <= 0;
                        div_bit <= 6'd31; div_busy <= 1;
                        div_source_id <= frame_source_id;
                    end else stats_overrun <= 1;
                end
                frame_open <= 1;
                collect_frame <= accept_new_source;
                frame_source_id <= source_id;
                frame_sum <= (accept_new_source && in_de) ? {24'd0,raw_y} : 0;
                frame_count <= (accept_new_source && in_de) ? 24'd1 : 0;
                sample_phase <= in_de ? 1 : 0;
                if (accept_new_source && in_de) begin
                    last_source_valid <= 1; last_source_id <= source_id;
                end
            end else if (frame_open && in_de) begin
                sample_phase <= sample_phase + 1'b1;
                if (collect_frame && (SAMPLE_LOG2 == 0 || sample_phase == 0)) begin
                    if (frame_count != 24'hffffff) begin
                        frame_sum <= frame_sum + {24'd0,raw_y};
                        frame_count <= frame_count + 1'b1;
                        last_source_valid <= 1; last_source_id <= frame_source_id;
                    end else stats_overflow <= 1;
                end
            end
        end
    end

    wire [2:0] pixel_level = frame_start ? level_request : gamma_level;
    wire pixel_enabled = frame_start ? enable : enable_active;
    case4_v10_gamma_curve curve(
        .clk(clk),.rst(rst),.level(pixel_level),.enable(pixel_enabled),
        .in_hs(in_hs),.in_vs(in_vs),.in_de(in_de),.in_rgb(in_rgb),
        .out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),.out_rgb(out_rgb)
    );
endmodule

// Pure fixed-level curve: no mean accumulator, no divider and no frame state.
// Lock level/enable at the owner/job/frame boundary before starting a stream.
// This lets a DDR/background job reuse the exact foreground-selected exponent.
// The three registered stages match the adaptive wrapper above exactly.
module case4_v10_gamma_curve (
    input wire clk,rst,
    input wire [2:0] level,
    input wire enable,
    input wire in_hs,in_vs,in_de,
    input wire [23:0] in_rgb,
    output reg out_hs,out_vs,out_de,
    output reg [23:0] out_rgb
);
    // Table returns {base, delta} for one of sixteen power-of-two segments.
    // Generated with scripts/v10/generate_gamma_lut.py; checked by the test.
    function [15:0] knot_coeff;
        input [2:0] level;
        input [3:0] segment;
        begin
            case ({level,segment})
                // BEGIN GENERATED GAMMA COEFFICIENTS
                7'd0: knot_coeff = 16'h0007;
                7'd1: knot_coeff = 16'h0704;
                7'd2: knot_coeff = 16'h0b06;
                7'd3: knot_coeff = 16'h110a;
                7'd4: knot_coeff = 16'h1b0f;
                7'd5: knot_coeff = 16'h2a18;
                7'd6: knot_coeff = 16'h4214;
                7'd7: knot_coeff = 16'h5612;
                7'd8: knot_coeff = 16'h6810;
                7'd9: knot_coeff = 16'h780f;
                7'd10: knot_coeff = 16'h870e;
                7'd11: knot_coeff = 16'h950e;
                7'd12: knot_coeff = 16'ha319;
                7'd13: knot_coeff = 16'hbc18;
                7'd14: knot_coeff = 16'hd416;
                7'd15: knot_coeff = 16'hea16;
                7'd16: knot_coeff = 16'h0003;
                7'd17: knot_coeff = 16'h0302;
                7'd18: knot_coeff = 16'h0504;
                7'd19: knot_coeff = 16'h0907;
                7'd20: knot_coeff = 16'h100c;
                7'd21: knot_coeff = 16'h1c14;
                7'd22: knot_coeff = 16'h3013;
                7'd23: knot_coeff = 16'h4311;
                7'd24: knot_coeff = 16'h5411;
                7'd25: knot_coeff = 16'h6510;
                7'd26: knot_coeff = 16'h750f;
                7'd27: knot_coeff = 16'h840f;
                7'd28: knot_coeff = 16'h931d;
                7'd29: knot_coeff = 16'hb01b;
                7'd30: knot_coeff = 16'hcb1b;
                7'd31: knot_coeff = 16'he61a;
                7'd32: knot_coeff = 16'h0001;
                7'd33: knot_coeff = 16'h0101;
                7'd34: knot_coeff = 16'h0202;
                7'd35: knot_coeff = 16'h0404;
                7'd36: knot_coeff = 16'h0808;
                7'd37: knot_coeff = 16'h1010;
                7'd38: knot_coeff = 16'h2010;
                7'd39: knot_coeff = 16'h3010;
                7'd40: knot_coeff = 16'h4010;
                7'd41: knot_coeff = 16'h5010;
                7'd42: knot_coeff = 16'h6010;
                7'd43: knot_coeff = 16'h7010;
                7'd44: knot_coeff = 16'h8020;
                7'd45: knot_coeff = 16'ha020;
                7'd46: knot_coeff = 16'hc020;
                7'd47: knot_coeff = 16'he020;
                7'd48: knot_coeff = 16'h0000;
                7'd49: knot_coeff = 16'h0001;
                7'd50: knot_coeff = 16'h0100;
                7'd51: knot_coeff = 16'h0102;
                7'd52: knot_coeff = 16'h0305;
                7'd53: knot_coeff = 16'h080b;
                7'd54: knot_coeff = 16'h130d;
                7'd55: knot_coeff = 16'h200d;
                7'd56: knot_coeff = 16'h2d0f;
                7'd57: knot_coeff = 16'h3c0f;
                7'd58: knot_coeff = 16'h4b10;
                7'd59: knot_coeff = 16'h5b11;
                7'd60: knot_coeff = 16'h6c22;
                7'd61: knot_coeff = 16'h8e25;
                7'd62: knot_coeff = 16'hb326;
                7'd63: knot_coeff = 16'hd927;
                7'd64: knot_coeff = 16'h0000;
                7'd65: knot_coeff = 16'h0000;
                7'd66: knot_coeff = 16'h0001;
                7'd67: knot_coeff = 16'h0100;
                7'd68: knot_coeff = 16'h0103;
                7'd69: knot_coeff = 16'h0407;
                7'd70: knot_coeff = 16'h0b0a;
                7'd71: knot_coeff = 16'h150b;
                7'd72: knot_coeff = 16'h200d;
                7'd73: knot_coeff = 16'h2d0e;
                7'd74: knot_coeff = 16'h3b0f;
                7'd75: knot_coeff = 16'h4a11;
                7'd76: knot_coeff = 16'h5b24;
                7'd77: knot_coeff = 16'h7f28;
                7'd78: knot_coeff = 16'ha72b;
                7'd79: knot_coeff = 16'hd22e;
                // END GENERATED GAMMA COEFFICIENTS
                default: knot_coeff = 16'h0000;
            endcase
        end
    endfunction

    // Packed coefficient: base[23:16], delta[15:8], shift[7:5], fraction[4:0].
    function [23:0] pixel_coeff;
        input [2:0] level;
        input [7:0] value;
        reg [3:0] segment;
        reg [2:0] shift;
        reg [4:0] fraction;
        reg [15:0] coeff;
        begin
            if      (value < 8'd1)   begin segment=0; shift=0; fraction=0; end
            else if (value < 8'd2)   begin segment=1; shift=0; fraction=0; end
            else if (value < 8'd4)   begin segment=2; shift=1; fraction={4'd0,value[0]}; end
            else if (value < 8'd8)   begin segment=3; shift=2; fraction={3'd0,value[1:0]}; end
            else if (value < 8'd16)  begin segment=4; shift=3; fraction={2'd0,value[2:0]}; end
            else if (value < 8'd128) begin segment=4+value[6:4]; shift=4; fraction={1'b0,value[3:0]}; end
            else                    begin segment=8+value[7:5]; shift=5; fraction=value[4:0]; end
            coeff = knot_coeff(level,segment);
            pixel_coeff = {coeff,shift,fraction};
        end
    endfunction

    function [12:0] small_product;
        input [7:0] delta;
        input [4:0] fraction;
        begin
            small_product = (fraction[0] ? {5'd0,delta} : 13'd0) +
                            (fraction[1] ? {4'd0,delta,1'b0} : 13'd0) +
                            (fraction[2] ? {3'd0,delta,2'b0} : 13'd0) +
                            (fraction[3] ? {2'd0,delta,3'b0} : 13'd0) +
                            (fraction[4] ? {1'b0,delta,4'b0} : 13'd0);
        end
    endfunction

    function [7:0] finish_pixel;
        input [7:0] base;
        input [12:0] product;
        input [2:0] shift;
        input endpoint;
        reg [12:0] rounded;
        reg [13:0] result;
        begin
            rounded = product + (shift == 0 ? 13'd0 : (13'd1 << (shift-1'b1)));
            result = {6'd0,base} + (rounded >> shift);
            finish_pixel = endpoint ? 8'hff : (result > 255 ? 8'hff : result[7:0]);
        end
    endfunction

    reg s1_hs,s1_vs,s1_de,s1_apply;
    reg [23:0] s1_rgb,s1_r,s1_g,s1_b;
    reg s2_hs,s2_vs,s2_de,s2_apply;
    reg [23:0] s2_rgb;
    reg [7:0] s2_rbase,s2_gbase,s2_bbase;
    reg [12:0] s2_rproduct,s2_gproduct,s2_bproduct;
    reg [2:0] s2_rshift,s2_gshift,s2_bshift;
    always @(posedge clk) begin
        if (rst) begin
            s1_hs<=0; s1_vs<=0; s1_de<=0; s1_apply<=0;
            s1_rgb<=0; s1_r<=0; s1_g<=0; s1_b<=0;
            s2_hs<=0; s2_vs<=0; s2_de<=0; s2_apply<=0;
            s2_rgb<=0; s2_rbase<=0; s2_gbase<=0; s2_bbase<=0;
            s2_rproduct<=0; s2_gproduct<=0; s2_bproduct<=0;
            s2_rshift<=0; s2_gshift<=0; s2_bshift<=0;
            out_hs<=0; out_vs<=0; out_de<=0; out_rgb<=0;
        end else begin
            s1_hs<=in_hs; s1_vs<=in_vs; s1_de<=in_de;
            s1_rgb<=in_rgb; s1_apply<=enable && level != 2;
            s1_r<=pixel_coeff(level,in_rgb[23:16]);
            s1_g<=pixel_coeff(level,in_rgb[15:8]);
            s1_b<=pixel_coeff(level,in_rgb[7:0]);
            s2_hs<=s1_hs; s2_vs<=s1_vs; s2_de<=s1_de;
            s2_rgb<=s1_rgb; s2_apply<=s1_apply;
            s2_rbase<=s1_r[23:16]; s2_gbase<=s1_g[23:16]; s2_bbase<=s1_b[23:16];
            s2_rproduct<=small_product(s1_r[15:8],s1_r[4:0]);
            s2_gproduct<=small_product(s1_g[15:8],s1_g[4:0]);
            s2_bproduct<=small_product(s1_b[15:8],s1_b[4:0]);
            s2_rshift<=s1_r[7:5]; s2_gshift<=s1_g[7:5]; s2_bshift<=s1_b[7:5];
            out_hs<=s2_hs; out_vs<=s2_vs; out_de<=s2_de;
            out_rgb<=s2_apply ? {
                finish_pixel(s2_rbase,s2_rproduct,s2_rshift,s2_rgb[23:16]==255),
                finish_pixel(s2_gbase,s2_gproduct,s2_gshift,s2_rgb[15:8]==255),
                finish_pixel(s2_bbase,s2_bproduct,s2_bshift,s2_rgb[7:0]==255)
            } : s2_rgb;
        end
    end
endmodule
