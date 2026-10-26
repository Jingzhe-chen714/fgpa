`timescale 1ns/1ps
// Small, always-visible capture diagnostic panel. No font ROM or block RAM.
// Rows 0..3 display diag0..diag3 as eight hexadecimal digits, MS nibble first.
// Active-video origin is (0,0); panel occupies x=24..183, y=300..427.
// VS is active low. The upstream producer must synchronize diagnostic status
// into clk; this module takes one coherent display snapshot at each VS fall.
// RGB and all three timing signals have exactly one registered stage.
module case4_v12_diag_osd (
    input wire clk, rst,
    input wire in_hs, in_vs, in_de,
    input wire [23:0] in_rgb,
    input wire [31:0] diag0, diag1, diag2, diag3,
    output reg out_hs, out_vs, out_de,
    output reg [23:0] out_rgb
);
    reg [10:0] x, y;
    reg de_q, vs_q;
    reg [31:0] held0, held1, held2, held3;
    always @(posedge clk) begin
        if (rst) begin
            x <= 0; y <= 0; de_q <= 0; vs_q <= 1;
            held0 <= 0; held1 <= 0; held2 <= 0; held3 <= 0;
        end else begin
            de_q <= in_de; vs_q <= in_vs;
            if (!in_vs) begin x <= 0; y <= 0; end
            else if (in_de) x <= x + 1'b1;
            else begin
                x <= 0;
                if (de_q) y <= y + 1'b1;
            end
            if (vs_q && !in_vs) begin
                held0 <= diag0; held1 <= diag1;
                held2 <= diag2; held3 <= diag3;
            end
        end
    end

    // Constant logic for seven segments {a,b,c,d,e,f,g}; hex B/D use b/d.
    function automatic [6:0] seven(input [3:0] value);
        begin
            case (value)
                4'h0: seven=7'b1111110; 4'h1: seven=7'b0110000;
                4'h2: seven=7'b1101101; 4'h3: seven=7'b1111001;
                4'h4: seven=7'b0110011; 4'h5: seven=7'b1011011;
                4'h6: seven=7'b1011111; 4'h7: seven=7'b1110000;
                4'h8: seven=7'b1111111; 4'h9: seven=7'b1111011;
                4'ha: seven=7'b1110111; 4'hb: seven=7'b0011111;
                4'hc: seven=7'b1001110; 4'hd: seven=7'b0111101;
                4'he: seven=7'b1001111; 4'hf: seven=7'b1000111;
            endcase
        end
    endfunction

    wire panel = in_de && in_vs && x>=11'd24 && x<11'd184 &&
                 y>=11'd300 && y<11'd428;
    wire [7:0] panel_x = x - 11'd24;
    wire [6:0] panel_y = y - 11'd300;
    wire [3:0] column = panel_x[7:4];
    wire [3:0] dx = panel_x[3:0];
    wire [4:0] dy = panel_y[4:0];
    wire [1:0] row = panel_y[6:5];
    reg [31:0] word_value;
    reg [3:0] digit;
    always @* begin
        case (row)
            0: word_value=held0; 1: word_value=held1;
            2: word_value=held2; 3: word_value=held3;
        endcase
        case (column)
            0: digit={2'b0,row};
            2: digit=word_value[31:28]; 3: digit=word_value[27:24];
            4: digit=word_value[23:20]; 5: digit=word_value[19:16];
            6: digit=word_value[15:12]; 7: digit=word_value[11:8];
            8: digit=word_value[7:4]; 9: digit=word_value[3:0];
            default: digit=0;
        endcase
    end
    wire [6:0] segments=seven(digit);
    wire horizontal=dx>=2 && dx<=9;
    wire upper=dy>=2 && dy<=10;
    wire lower=dy>=13 && dy<=21;
    wire ink=(column!=1) && (
        (segments[6] && horizontal && dy<=2) ||
        (segments[5] && dx>=9 && dx<=11 && upper) ||
        (segments[4] && dx>=9 && dx<=11 && lower) ||
        (segments[3] && horizontal && dy>=21 && dy<=23) ||
        (segments[2] && dx<=2 && lower) ||
        (segments[1] && dx<=2 && upper) ||
        (segments[0] && horizontal && dy>=10 && dy<=12));
    wire colon=column==1 && dx>=2 && dx<=4 &&
               ((dy>=6 && dy<=8)||(dy>=16 && dy<=18));
    always @(posedge clk) begin
        if (rst) begin
            out_hs<=1; out_vs<=1; out_de<=0; out_rgb<=0;
        end else begin
            out_hs<=in_hs; out_vs<=in_vs; out_de<=in_de;
            if (panel) out_rgb <= (ink||colon) ?
                (column<2 ? 24'h00ffff : 24'hffffff) : 24'h001018;
            else out_rgb<=in_rgb;
        end
    end
endmodule
