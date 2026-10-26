`timescale 1ns/1ps
// Exact 8-connected hysteresis for one captured WIDTH x HEIGHT region.
// 00=background, 01=weak, 11=strong. Pulse load_start while idle/ready and
// subsequently supply exactly WIDTH*HEIGHT row-major samples, last on load_last.
//
// A forward sweep follows updated left/up-left/up/up-right neighbors; a reverse
// sweep follows the corresponding right/down neighbors. Repeat whole pairs
// until neither sweep promotes a pixel. The strong set grows monotonically,
// and a zero-change pair proves that no weak pixel is adjacent to it in ANY
// of the eight directions. Thus every strong-connected weak chain is retained,
// regardless of length; disconnected weak components are rejected. No cap.
//
// One pixel is processed per clock. Port A reads the next center while port B
// writes a promotion of the previous center. Distinct addresses avoid any
// read-during-write dependence. WIDTH+1 shift-history bits provide all four
// causal neighbors without additional frame RAM or random neighbor reads.
// rd_edge is a one-clock synchronous read, enabled only after convergence.
// The parent holds the source RGB frame until its final map has been shown.
module case4_hysteresis #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 720,
    parameter integer ADDR_BITS = $clog2(WIDTH*HEIGHT),
    parameter integer X_BITS = $clog2(WIDTH),
    parameter integer Y_BITS = $clog2(HEIGHT)
) (
    input wire clk, rst_n, abort,
    input wire load_start, load_valid, load_last,
    input wire [1:0] load_state,
    output reg busy, ready, fault,
    output reg [15:0] changed_sweeps,
    input wire rd_en,
    input wire [ADDR_BITS-1:0] rd_addr,
    output wire rd_edge
);
    localparam integer PIXELS=WIDTH*HEIGHT;
    localparam [2:0] IDLE=0,LOAD=1,SCAN_INIT=2,SCAN=3,DRAIN=4,SCAN_END=5,DONE=6;
    reg [2:0] state;
    reg [1:0] map_ram[0:PIXELS-1];
    reg [1:0] center_q,display_q;
    reg display_valid;
    reg [ADDR_BITS-1:0] load_addr,issue_addr,center_addr;
    reg [X_BITS-1:0] issue_x,center_x;
    reg [Y_BITS-1:0] issue_y,center_y;
    reg center_valid,reverse_scan,sweep_changed,pair_changed;
    // History[0] is the preceding processed pixel. Upper row neighbors are
    // WIDTH, WIDTH-1 and WIDTH-2 clocks/pixels back. The first row/column
    // guards make old history contents irrelevant, so no bulk reset is needed.
    reg [WIDTH:0] history;
    wire processing=rst_n && !abort && center_valid && (state==SCAN || state==DRAIN);
    wire connected=(center_x!=0 && history[0]) ||
        (center_y!=0 && ((center_x!=0 && history[WIDTH]) ||
                       history[WIDTH-1] ||
                       (center_x!=WIDTH-1 && history[WIDTH-2])));
    wire promote=processing && center_q==2'b01 && connected;
    wire final_edge=center_q[1] || (center_q==2'b01 && connected);
    wire issue_read=rst_n && !abort && state==SCAN;
    wire load_write=rst_n && !abort && state==LOAD && load_valid;
    wire display_read=rst_n && !abort && ready && rd_en && rd_addr<PIXELS;
    wire [ADDR_BITS-1:0] port_a_addr=load_write ? load_addr : issue_addr;
    wire [ADDR_BITS-1:0] port_b_addr=promote ? center_addr : rd_addr;

    // True dual-port RAM inference. These are the ONLY memory access sites.
    // During LOAD only A writes; during SCAN A reads and B may write an older
    // address; during DONE only B reads. At scan reversals the drain and setup
    // clocks complete the final write before the same address is read again.
    // Both read and write MUST use the same explicit address net per port for
    // Efinity TDP inference. Outputs during writes are ignored by the consumer.
    always @(posedge clk) begin
        if(load_write || issue_read) begin
            if(load_write) map_ram[port_a_addr]<=load_state;
            center_q<=map_ram[port_a_addr];
        end
    end
    always @(posedge clk) begin
        if(promote || display_read) begin
            if(promote) map_ram[port_b_addr]<=2'b11;
            display_q<=map_ram[port_b_addr];
        end
        display_valid<=display_read;
    end
    always @(posedge clk) begin
        if(processing) history<={history[WIDTH-1:0],final_edge};
    end
    assign rd_edge=rst_n && !abort && ready && display_valid && display_q[1];

    always @(posedge clk) begin
        if(!rst_n || abort) begin
            state<=IDLE;busy<=0;ready<=0;fault<=0;changed_sweeps<=0;
            load_addr<=0;issue_addr<=0;center_addr<=0;
            issue_x<=0;issue_y<=0;center_x<=0;center_y<=0;
            center_valid<=0;reverse_scan<=0;sweep_changed<=0;pair_changed<=0;
        end else begin
            // Synchronous RAM result and this coordinate tag refer to the
            // same issued pixel. No result is consumed before its first read.
            center_valid<=issue_read;
            if(issue_read) begin
                center_addr<=issue_addr;center_x<=issue_x;center_y<=issue_y;
            end
            if(promote) sweep_changed<=1;
            case(state)
                IDLE,DONE: begin
                    if(load_start) begin
                        state<=LOAD;busy<=1;ready<=0;fault<=0;
                        load_addr<=0;changed_sweeps<=0;
                    end
                end
                LOAD: if(load_valid) begin
                    if(load_state==2'b10 || load_last!=(load_addr==PIXELS-1)) begin
                        state<=IDLE;busy<=0;ready<=0;fault<=1;
                    end else if(load_last) begin
                        state<=SCAN_INIT;reverse_scan<=0;pair_changed<=0;
                    end else load_addr<=load_addr+1'b1;
                end
                SCAN_INIT: begin
                    issue_addr<=reverse_scan ? PIXELS-1 : 0;
                    issue_x<=0;issue_y<=0;
                    sweep_changed<=0;center_valid<=0;state<=SCAN;
                end
                SCAN: begin
                    if(issue_x==WIDTH-1 && issue_y==HEIGHT-1) state<=DRAIN;
                    else begin
                        issue_addr<=reverse_scan ? issue_addr-1'b1 : issue_addr+1'b1;
                        if(issue_x==WIDTH-1) begin issue_x<=0;issue_y<=issue_y+1'b1;end
                        else issue_x<=issue_x+1'b1;
                    end
                end
                DRAIN: state<=SCAN_END;
                SCAN_END: begin
                    if(sweep_changed && changed_sweeps!=16'hffff)
                        changed_sweeps<=changed_sweeps+1'b1;
                    if(!reverse_scan) begin
                        pair_changed<=sweep_changed;
                        reverse_scan<=1;state<=SCAN_INIT;
                    end else if(pair_changed || sweep_changed) begin
                        reverse_scan<=0;pair_changed<=0;state<=SCAN_INIT;
                    end else begin state<=DONE;busy<=0;ready<=1;end
                end
                default: begin state<=IDLE;busy<=0;ready<=0;fault<=1;end
            endcase
        end
    end
endmodule
