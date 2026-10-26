`timescale 1ns/1ps
// Two independent round-robin burst arbiters. A granted writer owns AW/W/B
// until its B response; a reader owns AR/R through accepted RLAST.
// Selection is registered BEFORE presenting VALID, so stalls cannot change
// the selected address/data. One outstanding transaction per direction.
// Both clients use fixed ID zero. Reset only with the downstream AXI reset;
// a client abort MUST drain any transaction already offered to this mux.
module case4_axi_arbiter (input wire clk, rst,
    input wire [31:0] s0_awaddr,
    input wire [7:0] s0_awlen,
    input wire s0_awvalid,
    output wire s0_awready,
    input wire [127:0] s0_wdata,
    input wire [15:0] s0_wstrb,
    input wire s0_wlast,
    input wire s0_wvalid,
    output wire s0_wready,
    output wire [1:0] s0_bresp,
    output wire s0_bvalid,
    input wire s0_bready,
    input wire [31:0] s0_araddr,
    input wire [7:0] s0_arlen,
    input wire s0_arvalid,
    output wire s0_arready,
    output wire [127:0] s0_rdata,
    output wire [1:0] s0_rresp,
    output wire s0_rlast,
    output wire s0_rvalid,
    input wire s0_rready,
    input wire [31:0] s1_awaddr,
    input wire [7:0] s1_awlen,
    input wire s1_awvalid,
    output wire s1_awready,
    input wire [127:0] s1_wdata,
    input wire [15:0] s1_wstrb,
    input wire s1_wlast,
    input wire s1_wvalid,
    output wire s1_wready,
    output wire [1:0] s1_bresp,
    output wire s1_bvalid,
    input wire s1_bready,
    input wire [31:0] s1_araddr,
    input wire [7:0] s1_arlen,
    input wire s1_arvalid,
    output wire s1_arready,
    output wire [127:0] s1_rdata,
    output wire [1:0] s1_rresp,
    output wire s1_rlast,
    output wire s1_rvalid,
    input wire s1_rready,
    output wire [31:0] m_awaddr,
    output wire [7:0] m_awlen,
    output wire m_awvalid,
    input wire m_awready,
    output wire [127:0] m_wdata,
    output wire [15:0] m_wstrb,
    output wire m_wlast,
    output wire m_wvalid,
    input wire m_wready,
    input wire [1:0] m_bresp,
    input wire m_bvalid,
    output wire m_bready,
    output wire [31:0] m_araddr,
    output wire [7:0] m_arlen,
    output wire m_arvalid,
    input wire m_arready,
    input wire [127:0] m_rdata,
    input wire [1:0] m_rresp,
    input wire m_rlast,
    input wire m_rvalid,
    output wire m_rready);
    localparam IDLE=0, ADDR=1, DATA=2, RESP=3;
    reg [1:0] ws,rs; reg wo,ro,wnext,rnext;
    always @(posedge clk) begin
        if(rst) begin ws<=IDLE;rs<=IDLE;wo<=0;ro<=0;wnext<=0;rnext<=0;end
        else begin
            case(ws)
                IDLE: if(s0_awvalid || s1_awvalid) begin
                    wo<=s0_awvalid && s1_awvalid ? wnext : s1_awvalid;ws<=ADDR;end
                ADDR: if(m_awvalid && m_awready) ws<=DATA;
                DATA: if(m_wvalid && m_wready && m_wlast) ws<=RESP;
                RESP: if(m_bvalid && m_bready) begin ws<=IDLE;wnext<=!wo;end
            endcase
            case(rs)
                IDLE: if(s0_arvalid || s1_arvalid) begin
                    ro<=s0_arvalid && s1_arvalid ? rnext : s1_arvalid;rs<=ADDR;end
                ADDR: if(m_arvalid && m_arready) rs<=DATA;
                DATA: if(m_rvalid && m_rready && m_rlast) begin rs<=IDLE;rnext<=!ro;end
                default: rs<=IDLE;
            endcase
        end
    end
    assign m_awaddr=(wo ? s1_awaddr : s0_awaddr);
    assign m_awlen=(wo ? s1_awlen : s0_awlen);
    assign m_awvalid=!rst && (ws==ADDR) && (wo ? s1_awvalid : s0_awvalid);
    assign s0_awready=!rst && (ws==ADDR) && (wo==1'b0) && m_awready;
    assign s1_awready=!rst && (ws==ADDR) && (wo==1'b1) && m_awready;
    assign m_wdata=(wo ? s1_wdata : s0_wdata);
    assign m_wstrb=(wo ? s1_wstrb : s0_wstrb);
    assign m_wlast=(wo ? s1_wlast : s0_wlast);
    assign m_wvalid=!rst && (ws==DATA) && (wo ? s1_wvalid : s0_wvalid);
    assign s0_wready=!rst && (ws==DATA) && (wo==1'b0) && m_wready;
    assign s1_wready=!rst && (ws==DATA) && (wo==1'b1) && m_wready;
    assign s0_bresp=m_bresp;
    assign s1_bresp=m_bresp;
    assign s0_bvalid=!rst && (ws==RESP) && (wo==1'b0) && m_bvalid;
    assign s1_bvalid=!rst && (ws==RESP) && (wo==1'b1) && m_bvalid;
    assign m_bready=!rst && (ws==RESP) && (wo ? s1_bready : s0_bready);
    assign m_araddr=(ro ? s1_araddr : s0_araddr);
    assign m_arlen=(ro ? s1_arlen : s0_arlen);
    assign m_arvalid=!rst && (rs==ADDR) && (ro ? s1_arvalid : s0_arvalid);
    assign s0_arready=!rst && (rs==ADDR) && (ro==1'b0) && m_arready;
    assign s1_arready=!rst && (rs==ADDR) && (ro==1'b1) && m_arready;
    assign s0_rdata=m_rdata;
    assign s1_rdata=m_rdata;
    assign s0_rresp=m_rresp;
    assign s1_rresp=m_rresp;
    assign s0_rlast=m_rlast;
    assign s1_rlast=m_rlast;
    assign s0_rvalid=!rst && (rs==DATA) && (ro==1'b0) && m_rvalid;
    assign s1_rvalid=!rst && (rs==DATA) && (ro==1'b1) && m_rvalid;
    assign m_rready=!rst && (rs==DATA) && (ro ? s1_rready : s0_rready);
endmodule
