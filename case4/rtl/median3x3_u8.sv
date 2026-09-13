`timescale 1ns/1ps
// Unsigned nine-sample median, 19 compare decisions, II=1.
// Default: THREE registered stages (row sort / cross-row selection / median).
// An input accepted at edge N is visible immediately after edge N+2.
// PIPELINE_STAGES=1 is an explicit low-frequency/legacy-latency option;
// REGISTER_OUTPUT=0 defaults to PIPELINE_STAGES=0 (combinational reference).
// Registered modes use active-high synchronous reset and flush all sideband.
module median3x3_u8 #(
    parameter integer PIXEL_BITS = 8,
    parameter integer X_BITS = 10,
    parameter integer Y_BITS = 9,
    parameter bit REGISTER_OUTPUT = 1'b1,
    parameter integer PIPELINE_STAGES = REGISTER_OUTPUT ? 3 : 0
) (
    input logic clk, rst,
    input logic in_valid, in_sof, in_eol, in_eof,
    input logic [X_BITS-1:0] in_x,
    input logic [Y_BITS-1:0] in_y,
    input logic [PIXEL_BITS-1:0] in_p00, in_p01, in_p02,
    input logic [PIXEL_BITS-1:0] in_p10, in_p11, in_p12,
    input logic [PIXEL_BITS-1:0] in_p20, in_p21, in_p22,
    output logic out_valid, out_sof, out_eol, out_eof,
    output logic [X_BITS-1:0] out_x,
    output logic [Y_BITS-1:0] out_y,
    output logic [PIXEL_BITS-1:0] out_pixel
);
    initial begin
        if (PIXEL_BITS < 1 || X_BITS < 1 || Y_BITS < 1)
            $fatal(1, "CASE4_PARAM_MEDIAN_WIDTH: port widths must be positive");
        if (!(PIPELINE_STAGES == 0 || PIPELINE_STAGES == 1 || PIPELINE_STAGES == 3)
            || (REGISTER_OUTPUT != (PIPELINE_STAGES != 0)))
            $fatal(1, "CASE4_PARAM_MEDIAN_PIPE: supported stages 0/1/3; REGISTER_OUTPUT must agree");
    end

    // Packed result {lo, mid, hi}; exactly three unsigned compare-swaps.
    function automatic logic [3*PIXEL_BITS-1:0] sort3(
        input logic [PIXEL_BITS-1:0] a, b, c
    );
        logic [PIXEL_BITS-1:0] lo, mid, hi, tmp;
        begin
            lo=a; mid=b; hi=c; tmp='0;
            if (lo > mid) begin tmp=lo; lo=mid; mid=tmp; end
            if (mid > hi) begin tmp=mid; mid=hi; hi=tmp; end
            if (lo > mid) begin tmp=lo; lo=mid; mid=tmp; end
            sort3={lo,mid,hi};
        end
    endfunction
    function automatic logic [PIXEL_BITS-1:0] median3(
        input logic [PIXEL_BITS-1:0] a, b, c
    );
        logic [3*PIXEL_BITS-1:0] ordered;
        begin ordered=sort3(a,b,c); median3=ordered[2*PIXEL_BITS-1:PIXEL_BITS]; end
    endfunction
    function automatic logic [PIXEL_BITS-1:0] min3(
        input logic [PIXEL_BITS-1:0] a, b, c
    );
        logic [PIXEL_BITS-1:0] tmp;
        begin tmp=(a < b) ? a : b; min3=(tmp < c) ? tmp : c; end
    endfunction
    function automatic logic [PIXEL_BITS-1:0] max3(
        input logic [PIXEL_BITS-1:0] a, b, c
    );
        logic [PIXEL_BITS-1:0] tmp;
        begin tmp=(a > b) ? a : b; max3=(tmp > c) ? tmp : c; end
    endfunction

    wire [3*PIXEL_BITS-1:0] row_sorted[0:2];
    logic [3*PIXEL_BITS-1:0] row_values[0:2];
    wire [PIXEL_BITS-1:0] selection_comb[0:2];
    logic [PIXEL_BITS-1:0] selection_values[0:2];
    wire [PIXEL_BITS-1:0] median_comb;
    assign row_sorted[0]=sort3(in_p00,in_p01,in_p02);
    assign row_sorted[1]=sort3(in_p10,in_p11,in_p12);
    assign row_sorted[2]=sort3(in_p20,in_p21,in_p22);
    assign selection_comb[0]=max3(row_values[0][3*PIXEL_BITS-1:2*PIXEL_BITS],
                                 row_values[1][3*PIXEL_BITS-1:2*PIXEL_BITS],
                                 row_values[2][3*PIXEL_BITS-1:2*PIXEL_BITS]);
    assign selection_comb[1]=median3(row_values[0][2*PIXEL_BITS-1:PIXEL_BITS],
                                    row_values[1][2*PIXEL_BITS-1:PIXEL_BITS],
                                    row_values[2][2*PIXEL_BITS-1:PIXEL_BITS]);
    assign selection_comb[2]=min3(row_values[0][PIXEL_BITS-1:0],
                                 row_values[1][PIXEL_BITS-1:0],
                                 row_values[2][PIXEL_BITS-1:0]);
    assign median_comb=median3(selection_values[0],selection_values[1],selection_values[2]);

    generate
        if (PIPELINE_STAGES == 3) begin : g_split
            always_ff @(posedge clk) begin
                for (integer i=0; i<3; i=i+1) begin
                    if (rst) begin row_values[i]<='0; selection_values[i]<='0; end
                    else begin row_values[i]<=row_sorted[i]; selection_values[i]<=selection_comb[i]; end
                end
            end
        end else begin : g_unsplit
            for (genvar i=0; i<3; i=i+1) begin : g_values
                assign row_values[i]=row_sorted[i];
                assign selection_values[i]=selection_comb[i];
            end
        end
        if (PIPELINE_STAGES > 0) begin : g_registered
            localparam integer SIDE_W=4+X_BITS+Y_BITS;
            logic [SIDE_W-1:0] side_pipe[0:PIPELINE_STAGES-1];
            always_ff @(posedge clk) begin
                if (rst) begin
                    for (integer i=0; i<PIPELINE_STAGES; i=i+1) side_pipe[i]<='0;
                    out_pixel<='0;
                end else begin
                    side_pipe[0]<={in_valid, in_valid && in_sof, in_valid && in_eol,
                                   in_valid && in_eof, in_x, in_y};
                    for (integer i=1; i<PIPELINE_STAGES; i=i+1) side_pipe[i]<=side_pipe[i-1];
                    out_pixel<=median_comb;
                end
            end
            assign {out_valid,out_sof,out_eol,out_eof,out_x,out_y}=side_pipe[PIPELINE_STAGES-1];
        end else begin : g_combinational
            assign {out_valid,out_sof,out_eol,out_eof,out_x,out_y}=
                {in_valid, in_valid && in_sof, in_valid && in_eol, in_valid && in_eof, in_x, in_y};
            assign out_pixel=median_comb;
        end
    endgenerate
endmodule
