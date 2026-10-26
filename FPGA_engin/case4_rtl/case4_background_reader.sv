`timescale 1ns/1ps
// One pinned RGB565 frame fetched independently of the visible frame.
// start is a pixel-domain pulse in vertical blank; bank is held until idle.
// abort drains every offered AXI burst before resetting the paired FIFO.
module case4_background_reader #(
    parameter integer FRAME_BYTES=1920*1080*2, BANK_BITS=6,
    parameter integer BURST_BEATS=128,
    parameter [31:0] HISTORY_BASE=32'h02000000
)(
    input wire clk,rst,start,abort,input wire [BANK_BITS-1:0] bank,
    input wire pixel_de,output wire [23:0] pixel_rgb,
    output wire active,idle,output reg fault,
    input wire axiclk,axirst,
    output wire [31:0] m_araddr,output wire [7:0] m_arlen,
    output wire m_arvalid,input wire m_arready,
    input wire [127:0] m_rdata,input wire [1:0] m_rresp,
    input wire m_rlast,m_rvalid,output wire m_rready
);
    reg request;
    reg [BANK_BITS-1:0] held_bank;
    reg acknowledge,ui_active,ui_fault;
    (* async_reg="true" *) reg [2:0] req_sync;
    (* async_reg="true" *) reg [1:0] cancel_sync,active_sync,idle_sync,error_sync;
    reg request_seen;
    reg fifo_reset;
    wire full,empty,fifo_busy;
    wire [15:0] rgb565;
    reg [22:0] pixel_count;
    wire pop=active_sync[1] && !abort && pixel_de && pixel_count<FRAME_BYTES/2;
    reg [2:0] state;
    localparam RESET=0,WAIT=1,ADDR=2,DATA=3,DONE=4;
    reg [7:0] reset_count,beat;
    reg [31:0] offset,base;
    wire ui_idle=state==WAIT && !fifo_busy && !fifo_reset;
    wire read_take=m_rvalid&&m_rready;
    assign m_araddr=base+offset;
    assign m_arlen=BURST_BEATS-1;
    assign m_arvalid=state==ADDR;
    assign m_rready=state==DATA;
    assign active=active_sync[1]&&!abort&&!fault;
    assign idle=idle_sync[1]&&!active_sync[1];
    assign pixel_rgb=active&&!empty ? {rgb565[15:11],rgb565[15:13],rgb565[10:5],rgb565[10:9],rgb565[4:0],rgb565[4:2]} : 24'd0;
    R0_FIFO_16 pixels(
        .wr_clk_i(axiclk),.wr_en_i(read_take&&!cancel_sync[1]),.wdata(m_rdata),
        .a_rst_i(axirst||fifo_reset),.prog_full_o(full),.rst_busy(fifo_busy),
        .rd_clk_i(clk),.rd_en_i(pop&&!empty),.rdata(rgb565),.empty_o(empty));
    always @(posedge clk) begin
        if(rst) begin request<=0;held_bank<=0;active_sync<=0;idle_sync<=0;error_sync<=0;fault<=0;pixel_count<=0;end
        else begin
            active_sync<={active_sync[0],ui_active};idle_sync<={idle_sync[0],ui_idle};error_sync<={error_sync[0],ui_fault};
            if(start&&idle) begin request<=!request;held_bank<=bank;fault<=0;pixel_count<=0;end
            if(pop) begin
                if(empty) fault<=1;
                pixel_count<=pixel_count+1'b1;
            end
            if(error_sync[1]) fault<=1;
            if(abort) begin fault<=0;pixel_count<=0;end
        end
    end
    always @(posedge axiclk) begin
        if(axirst) begin req_sync<=0;cancel_sync<=3;end
        else begin req_sync<={req_sync[1:0],request};cancel_sync<={cancel_sync[0],abort||rst};end
    end
    always @(posedge axiclk) begin
        if(axirst) begin
            state<=RESET;fifo_reset<=1;reset_count<=63;request_seen<=0;acknowledge<=0;
            ui_active<=0;ui_fault<=0;offset<=0;base<=0;beat<=0;
        end else begin
            case(state)
                RESET: begin
                    ui_active<=0;
                    if(reset_count!=0) reset_count<=reset_count-1'b1;
                    else begin fifo_reset<=0;if(!fifo_busy)state<=WAIT;end
                end
                WAIT: begin
                    if(cancel_sync[1]) begin request_seen<=req_sync[2];ui_fault<=0;end
                    else if(request_seen!=req_sync[2]) begin
                        request_seen<=req_sync[2];base<=HISTORY_BASE+({{(32-BANK_BITS){1'b0}},held_bank}<<22);
                        offset<=0;beat<=0;ui_fault<=0;ui_active<=1;state<=DONE;
                    end
                end
                DONE: begin
                    if(cancel_sync[1]) begin fifo_reset<=1;reset_count<=63;state<=RESET;ui_active<=0;end
                    else if(offset<FRAME_BYTES&&!full) begin beat<=0;state<=ADDR;end
                end
                ADDR: if(m_arready) state<=DATA;
                DATA: if(read_take) begin
                    if(m_rresp!=0 || m_rlast!=(beat==BURST_BEATS-1)) ui_fault<=1;
                    if(m_rlast) begin offset<=offset+BURST_BEATS*16;state<=DONE;end
                    else beat<=beat+1'b1;
                end
                default: state<=RESET;
            endcase
        end
    end
endmodule
