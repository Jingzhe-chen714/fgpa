`timescale 1ns/1ps
// Native RGB565 history store, using the board's original asynchronous FIFOs.
// 64 physical 4 MiB slots retain at most63 complete, acknowledged frames.
// History entry stops whole-frame admissions and drains the accepted frame;
// replay/compare then read an immutable chronological snapshot. Comparison
// alternates reference/current bursts and uses one output FIFO, so the two
// source frames can never drift by a pixel after a read stall.
module case4_history_store #(
    parameter C_ID_LEN=4,
    parameter C_RD_END_ADDR=1920*1080*2,
    parameter C_W_WIDTH=8,
    parameter C_R_WIDTH=16,
    parameter C_BUF_SIZE=22,
    parameter C_BURST_LEN=128,
    parameter C_BANK_BITS=6,
    parameter [31:0] C_HISTORY_BASE=32'h02000000,
    parameter C_REPLAY_DIV=4
)(
    input wire axi_clk, axi_reset,
    output wire [31:0] axi_awaddr,
    output wire [7:0] axi_awlen,
    output wire axi_awvalid,
    input wire axi_awready,
    output wire [127:0] axi_wdata,
    output wire [15:0] axi_wstrb,
    output wire axi_wlast, axi_wvalid,
    input wire axi_wready,
    input wire [C_ID_LEN-1:0] axi_bid,
    input wire [1:0] axi_bresp,
    input wire axi_bvalid,
    output wire axi_bready,
    output wire [C_ID_LEN-1:0] axi_arid,
    output wire [31:0] axi_araddr,
    output wire [7:0] axi_arlen,
    output wire axi_arvalid,
    input wire axi_arready,
    input wire [C_ID_LEN-1:0] axi_rid,
    input wire [127:0] axi_rdata,
    input wire [1:0] axi_rresp,
    input wire axi_rlast, axi_rvalid,
    output wire axi_rready,
    input wire wframe_pclk, wframe_vsync, wframe_data_en,
    input wire [C_W_WIDTH-1:0] wframe_data,
    input wire rframe_pclk, rframe_vsync, rframe_data_en,
    output wire [C_R_WIDTH-1:0] rframe_data,
    input wire freeze_request,
    output reg frozen,
    output wire frame_ready,
    output wire error,
    output wire [31:0] tp_o,
    input wire [1:0] history_mode,
    input wire history_paused,
    input wire step_prev_toggle, step_next_toggle, reference_toggle,
    input wire [7:0] compare_threshold,
    output reg history_ready,
    output reg [6:0] history_count,
    output reg [5:0] selected_index, reference_index,
    output reg [1:0] active_mode,
    output reg active_paused,
    output reg history_status_toggle
);
    localparam BURST_BYTES=C_BURST_LEN*16;
    localparam FRAME_WORDS=C_RD_END_ADDR/(C_W_WIDTH/8);
    localparam SLOTS=1<<C_BANK_BITS, HISTORY_MAX=SLOTS-1;
    localparam W_IDLE=0,W_ADDR=1,W_DATA=2,W_RESP=3,W_RESET=4;
    localparam R_IDLE=0,R_ADDR=1,R_DATA=2,R_RESET=3,R_RELEASE=4,R_DRAIN=5;
    reg [2:0] ws,rs;
    reg [C_BANK_BITS-1:0] write_bank,read_bank,reference_bank,latest_bank;
    reg [C_BANK_BITS-1:0] history_bank [0:HISTORY_MAX-1];
    reg latest_valid,read_valid;
    reg [C_BUF_SIZE-1:0] write_offset,read_offset;
    reg [7:0] write_beat,read_beat;
    reg [6:0] write_reset_count,read_reset_count;
    reg write_fifo_reset,read_fifo_reset;
    reg write_failed,bus_error,read_error;
    reg end_pending,end_good,capture_ack,read_pending;
    reg read_reference;
    reg [3:0] drain_count;
    reg [7:0] replay_count,threshold_latched;
    (* async_reg="true" *) reg [2:0] eof_sync,display_sync,quiesced_sync;
    (* async_reg="true" *) reg [1:0] freeze_sync,pause_sync;
    (* async_reg="true" *) reg [1:0] mode_meta,mode_sync;
    reg [1:0] mode_previous,mode_ui;
    (* async_reg="true" *) reg [7:0] threshold_meta,threshold_sync;
    (* async_reg="true" *) reg [2:0] prev_sync,next_sync,reference_sync;
    reg prev_seen,next_seen,reference_seen;
    reg prev_pending,next_pending,reference_pending;
    wire stop_capture=(mode_ui!=0)||(active_mode!=0);

    wire write_full,write_empty,write_almost_empty,write_busy;
    wire [127:0] write_data;
    wire read_full,read_empty,read_busy;
    wire [15:0] read_data;
    wire write_pop=axi_wvalid&&axi_wready;
    wire read_take=axi_rvalid&&axi_rready;

    reg capture_vsync_d,capture_armed,capture_bad;
    reg capture_started,capture_boundary_seen;
    reg [24:0] capture_count;
    reg capture_eof_toggle,capture_good,camera_quiesced;
    (* async_reg="true" *) reg [1:0] writer_reset_sync,capture_ack_sync,stop_sync;
    wire capture_end=capture_vsync_d&&!wframe_vsync;
    wire capture_admit=!capture_started&&capture_boundary_seen&&
        capture_ack_sync[1]==capture_eof_toggle&&!writer_reset_sync[1]&&
        !write_busy&&!stop_sync[1];
    wire capture_accept=(capture_armed||capture_admit)&&wframe_data_en&&
        !writer_reset_sync[1]&&!write_busy&&(capture_count<FRAME_WORDS);
    always @(posedge wframe_pclk or posedge axi_reset) begin
        if(axi_reset) begin
            capture_vsync_d<=0;capture_armed<=0;capture_started<=0;
            capture_boundary_seen<=0;capture_bad<=0;capture_count<=0;
            capture_eof_toggle<=0;capture_good<=0;writer_reset_sync<=3;
            capture_ack_sync<=0;stop_sync<=0;camera_quiesced<=0;
        end else begin
            capture_vsync_d<=wframe_vsync;
            writer_reset_sync<={writer_reset_sync[0],write_fifo_reset};
            capture_ack_sync<={capture_ack_sync[0],capture_ack};
            stop_sync<={stop_sync[0],stop_capture};
            // ACK equality ensures an EOF in flight cannot be mistaken for
            // an idle camera. An already admitted frame is never truncated.
            camera_quiesced<=stop_sync[1]&&!capture_armed&&
                (capture_ack_sync[1]==capture_eof_toggle);
            if(capture_end) begin
                if(capture_armed) begin
                    capture_good<=!capture_bad&&(capture_count==FRAME_WORDS);
                    capture_eof_toggle<=!capture_eof_toggle;
                end
                capture_count<=0;capture_bad<=0;capture_armed<=0;
                capture_started<=0;capture_boundary_seen<=1;
            end else if(wframe_data_en) begin
                if(!capture_started) begin
                    capture_started<=1;capture_armed<=capture_admit;
                end
                if(capture_armed||capture_admit) begin
                    if(capture_count<FRAME_WORDS+1) capture_count<=capture_count+1'b1;
                    if(!capture_accept||write_full) capture_bad<=1;
                end
            end
        end
    end
    W0_FIFO_8 capture_fifo(
        .wr_clk_i(wframe_pclk),.wr_en_i(capture_accept&&!write_full),
        .wdata(wframe_data),.a_rst_i(axi_reset||write_fifo_reset),
        .rd_clk_i(axi_clk),.rd_en_i(write_pop),.rdata(write_data),
        .prog_empty_o(write_almost_empty),.empty_o(write_empty),
        .full_o(write_full),.rst_busy(write_busy));

    reg display_vsync_d,display_toggle,display_bad;
    (* async_reg="true" *) reg [1:0] read_valid_sync;
    always @(posedge rframe_pclk or posedge axi_reset) begin
        if(axi_reset) begin
            display_vsync_d<=0;display_toggle<=0;display_bad<=0;read_valid_sync<=0;
        end else begin
            display_vsync_d<=rframe_vsync;
            read_valid_sync<={read_valid_sync[0],read_valid};
            if(display_vsync_d&&!rframe_vsync) begin
                display_toggle<=!display_toggle;display_bad<=0;
            end else if(rframe_data_en&&read_valid_sync[1]&&read_empty) display_bad<=1;
        end
    end

    // Reference burst scratch: synchronous read, no reset,128x128=16Kibit.
    // REF and CURRENT phases never overlap, so same-address collisions cannot
    // occur. The selected beat follows the scratch read by exactly one cycle.
    reg [127:0] reference_burst [0:C_BURST_LEN-1];
    reg [127:0] reference_word,selected_word;
    reg selected_valid;
    always @(posedge axi_clk) begin
        if(read_take&&read_reference) reference_burst[read_beat]<=axi_rdata;
        if(read_take&&!read_reference) begin
            reference_word<=reference_burst[read_beat];
            selected_word<=axi_rdata;
        end
    end
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) selected_valid<=0;
        else selected_valid<=read_take&&!read_reference&&(active_mode==2);
    end
    wire diff_valid;
    wire [127:0] diff_data;
    case4_frame_diff128 difference(
        .clk(axi_clk),.reset(axi_reset),.in_valid(selected_valid),
        .in_selected(selected_word),.in_reference(reference_word),
        .threshold(threshold_latched),.out_valid(diff_valid),.out_data(diff_data));
    wire fifo_push=(active_mode==2)?diff_valid:(read_take&&!read_reference);
    wire [127:0] fifo_data=(active_mode==2)?diff_data:axi_rdata;
    R0_FIFO_16 display_fifo(
        .wr_clk_i(axi_clk),.wr_en_i(fifo_push),.wdata(fifo_data),
        .a_rst_i(axi_reset||read_fifo_reset),.prog_full_o(read_full),.rst_busy(read_busy),
        .rd_clk_i(rframe_pclk),
        .rd_en_i(rframe_data_en&&read_valid_sync[1]&&!read_empty),
        .rdata(read_data),.empty_o(read_empty));
    assign rframe_data=read_valid_sync[1]&&!read_empty&&!display_bad?read_data:16'b0;

    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin
            eof_sync<=0;display_sync<=0;quiesced_sync<=0;freeze_sync<=0;
            mode_meta<=0;mode_sync<=0;mode_previous<=0;mode_ui<=0;
            pause_sync<=0;threshold_meta<=32;threshold_sync<=32;
            prev_sync<=0;next_sync<=0;reference_sync<=0;
        end else begin
            eof_sync<={eof_sync[1:0],capture_eof_toggle};
            display_sync<={display_sync[1:0],display_toggle};
            quiesced_sync<={quiesced_sync[1:0],camera_quiesced};
            freeze_sync<={freeze_sync[0],freeze_request};
            mode_meta<=history_mode;mode_sync<=mode_meta;mode_previous<=mode_sync;
            if(mode_sync==mode_previous) mode_ui<=(mode_sync==3)?0:mode_sync;
            pause_sync<={pause_sync[0],history_paused};
            threshold_meta<=compare_threshold;threshold_sync<=threshold_meta;
            prev_sync<={prev_sync[1:0],step_prev_toggle};
            next_sync<={next_sync[1:0],step_next_toggle};
            reference_sync<={reference_sync[1:0],reference_toggle};
        end
    end

    // While live, a frozen display can pin the oldest entry. Evict the next
    // oldest instead; every remaining entry is still in chronological order.
    // During history/compare no camera admission occurs. SLOTS>=4 guarantees
    // a victim even with the reader pinned, plus one private construction bank.
    wire evict_second=read_valid&&(history_bank[0]==read_bank);
    wire [C_BANK_BITS-1:0] evicted_bank=evict_second?history_bank[1]:history_bank[0];
    integer h;
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin
            ws<=W_RESET;write_bank<=0;latest_bank<=0;latest_valid<=0;
            history_count<=0;write_offset<=0;write_beat<=0;
            write_reset_count<=63;write_fifo_reset<=1;write_failed<=0;bus_error<=0;
            end_pending<=0;end_good<=0;capture_ack<=0;
            for(h=0;h<HISTORY_MAX;h=h+1) history_bank[h]<=0;
        end else begin
            if(eof_sync[2]!=eof_sync[1]) begin end_pending<=1;end_good<=capture_good;end
            case(ws)
                W_RESET: if(write_reset_count!=0) write_reset_count<=write_reset_count-1'b1;
                    else begin write_fifo_reset<=0;ws<=W_IDLE;end
                W_IDLE: begin
                    if(!write_almost_empty&&write_offset<C_RD_END_ADDR) begin
                        write_beat<=0;ws<=W_ADDR;
                    end else if(end_pending&&(!end_good||write_failed||write_offset==C_RD_END_ADDR)) begin
                        if(end_good&&!write_failed&&write_offset==C_RD_END_ADDR) begin
                            latest_bank<=write_bank;latest_valid<=1;
                            if(history_count<HISTORY_MAX) begin
                                history_bank[history_count]<=write_bank;
                                history_count<=history_count+1'b1;
                                write_bank<=write_bank+1'b1;
                            end else begin
                                for(h=0;h<HISTORY_MAX-1;h=h+1)
                                    if(h!=0||!evict_second) history_bank[h]<=history_bank[h+1];
                                history_bank[HISTORY_MAX-1]<=write_bank;
                                write_bank<=evicted_bank;
                            end
                        end
                        write_offset<=0;write_failed<=0;end_pending<=0;
                        capture_ack<=eof_sync[2];write_fifo_reset<=1;
                        write_reset_count<=63;ws<=W_RESET;
                    end
                end
                W_ADDR: if(axi_awready) ws<=W_DATA;
                W_DATA: if(axi_wready) begin
                    if(write_empty) begin write_failed<=1;bus_error<=1;end
                    if(write_beat==C_BURST_LEN-1) ws<=W_RESP;
                    else write_beat<=write_beat+1'b1;
                end
                W_RESP: if(axi_bvalid) begin
                    if(axi_bresp!=0) begin write_failed<=1;bus_error<=1;end
                    write_offset<=write_offset+BURST_BYTES;ws<=W_IDLE;
                end
                default: ws<=W_RESET;
            endcase
        end
    end

    wire snapshot_settled=quiesced_sync[2]&&(ws==W_IDLE)&&!end_pending&&
        capture_ack==eof_sync[2]&&!write_busy;
    reg [5:0] next_selected,next_reference;
    reg [7:0] next_replay_count;
    wire prev_command=prev_pending||(prev_seen!=prev_sync[2]);
    wire next_command=next_pending||(next_seen!=next_sync[2]);
    wire reference_command=reference_pending||(reference_seen!=reference_sync[2]);
    always @* begin
        next_selected=selected_index;next_reference=reference_index;
        next_replay_count=replay_count;
        if(active_mode==0&&mode_ui!=0) begin
            next_selected=(mode_ui==2&&history_count!=0)?history_count-1'b1:0;
            next_reference=0;next_replay_count=0;
        end else if(mode_ui!=active_mode) next_replay_count=0;
        if(history_count!=0&&mode_ui!=0) begin
            if(next_command) begin
                next_selected=(next_selected+1>=history_count)?0:next_selected+1'b1;
                next_replay_count=0;
            end else if(prev_command) begin
                next_selected=(next_selected==0)?history_count-1'b1:next_selected-1'b1;
                next_replay_count=0;
            end else if(mode_ui==active_mode&&mode_ui!=0&&!pause_sync[1]) begin
                if(replay_count==C_REPLAY_DIV-1) begin
                    next_selected=(selected_index+1>=history_count)?0:selected_index+1'b1;
                    next_replay_count=0;
                end else next_replay_count=replay_count+1'b1;
            end
            if(reference_command) next_reference=next_selected;
        end
    end
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin
            rs<=R_RESET;read_bank<=0;reference_bank<=0;read_valid<=0;read_pending<=1;
            read_offset<=0;read_beat<=0;read_reset_count<=63;read_fifo_reset<=1;
            read_error<=0;frozen<=0;read_reference<=0;drain_count<=0;
            history_ready<=0;selected_index<=0;reference_index<=0;active_mode<=0;
            active_paused<=0;history_status_toggle<=0;replay_count<=0;threshold_latched<=32;
            prev_seen<=0;next_seen<=0;reference_seen<=0;
            prev_pending<=0;next_pending<=0;reference_pending<=0;
        end else begin
            prev_seen<=prev_sync[2];next_seen<=next_sync[2];reference_seen<=reference_sync[2];
            if(mode_ui!=0) begin
                if(prev_seen!=prev_sync[2]) prev_pending<=1;
                if(next_seen!=next_sync[2]) next_pending<=1;
                if(reference_seen!=reference_sync[2]) reference_pending<=1;
            end else begin prev_pending<=0;next_pending<=0;reference_pending<=0;end
            if(display_sync[2]!=display_sync[1]) read_pending<=1;
            case(rs)
                R_IDLE: begin
                    if(read_pending) begin
                        read_pending<=0;
                        // All outstanding AXI/RGB pipeline data has retired.
                        // The FIFO reset and selection occur only in blanking.
                        if(mode_ui==0) begin
                            active_mode<=0;active_paused<=0;history_ready<=0;replay_count<=0;
                            if((!frozen||!freeze_sync[1]||!read_valid||active_mode!=0)&&latest_valid) begin
                                read_bank<=latest_bank;read_valid<=1;
                            end
                            frozen<=freeze_sync[1]&&(read_valid||latest_valid);
                        end else if(snapshot_settled) begin
                            active_mode<=mode_ui;active_paused<=pause_sync[1];history_ready<=1;
                            selected_index<=next_selected;reference_index<=next_reference;
                            replay_count<=next_replay_count;
                            if(history_count!=0) begin
                                read_bank<=history_bank[next_selected];
                                reference_bank<=history_bank[next_reference];read_valid<=1;
                            end else read_valid<=0;
                            frozen<=history_count!=0;
                            prev_pending<=0;next_pending<=0;reference_pending<=0;
                        end
                        threshold_latched<=threshold_sync;
                        history_status_toggle<=!history_status_toggle;
                        read_offset<=0;read_reference<=0;read_fifo_reset<=1;
                        read_reset_count<=63;rs<=R_RESET;
                    end else if(read_valid&&!read_full&&read_offset<C_RD_END_ADDR) begin
                        read_reference<=active_mode==2;read_beat<=0;rs<=R_ADDR;
                    end
                end
                R_ADDR: if(axi_arready) rs<=R_DATA;
                R_DATA: if(read_take) begin
                    if(axi_rlast!=(read_beat==C_BURST_LEN-1)) read_error<=1;
                    if(axi_rlast) begin
                        read_beat<=0;
                        if(read_reference) begin read_reference<=0;rs<=R_ADDR;end
                        else begin
                            read_offset<=read_offset+BURST_BYTES;
                            // One synchronous scratch read + two diff stages.
                            // Wait five clocks before allowing a FIFO reset.
                            drain_count<=5;rs<=R_DRAIN;
                        end
                    end else read_beat<=read_beat+1'b1;
                end
                R_DRAIN: if(drain_count!=0) drain_count<=drain_count-1'b1;
                    else rs<=R_IDLE;
                R_RESET: if(read_reset_count!=0) read_reset_count<=read_reset_count-1'b1;
                    else begin read_fifo_reset<=0;read_reset_count<=15;rs<=R_RELEASE;end
                R_RELEASE: if(read_reset_count!=0) read_reset_count<=read_reset_count-1'b1;
                    else if(!read_busy) rs<=R_IDLE;
                default: rs<=R_RESET;
            endcase
            if(read_take&&axi_rresp!=0) read_error<=1;
        end
    end
    assign axi_awaddr=C_HISTORY_BASE+({{(32-C_BANK_BITS){1'b0}},write_bank}<<C_BUF_SIZE)+write_offset;
    assign axi_araddr=C_HISTORY_BASE+({{(32-C_BANK_BITS){1'b0}},(read_reference?reference_bank:read_bank)}<<C_BUF_SIZE)+read_offset;
    assign axi_awlen=C_BURST_LEN-1;
    assign axi_arlen=C_BURST_LEN-1;
    assign axi_arid=0;
    assign axi_awvalid=ws==W_ADDR;
    assign axi_wvalid=ws==W_DATA;
    assign axi_wlast=write_beat==C_BURST_LEN-1;
    assign axi_wdata=write_data;
    assign axi_wstrb=16'hffff;
    assign axi_bready=ws==W_RESP;
    assign axi_arvalid=rs==R_ADDR;
    assign axi_rready=rs==R_DATA;
    assign frame_ready=latest_valid;
    assign error=bus_error||read_error;
    assign tp_o={19'b0,history_ready,active_mode,error,frozen,latest_valid,read_valid,rs,ws[2:0]};
endmodule
