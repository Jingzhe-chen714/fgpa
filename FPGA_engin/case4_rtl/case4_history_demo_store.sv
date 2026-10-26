`timescale 1ns/1ps
// V7 generation-safe event recall + background publication + native RGB565 history store, using the board's original asynchronous FIFOs.
// 64 physical 4 MiB slots retain at most63 complete, acknowledged frames.
// History entry stops whole-frame admissions and drains the accepted frame;
// replay/compare then read an immutable chronological snapshot. Comparison
// alternates reference/current bursts and preserves RGB in the main FIFO.
// A paired8-to1 mask FIFO carries change bits at identical pixel positions.
// Both FIFOs reset, write and pop together; either empty stalls both.
// Parameters require C_BANK_BITS>=3, IMG_WIDTH%16==0, and complete
// RGB half-lines; coordinator writes the entire map and retires its final
// BRESP before publish_toggle. Slots0/1 alternate outside this module.
module case4_history_demo_store #(
    parameter IMG_WIDTH=1920,
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
    output wire rframe_change,
    output wire rframe_edge,
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
    output reg history_status_toggle,
    input wire canny_enable,
    input wire process_request_toggle,process_release_toggle,publish_toggle,publish_slot,
    output reg process_ack_toggle,process_valid,
    output reg [5:0] process_bank,
    output reg publish_ack_toggle,canny_display_valid,canny_display_slot,
    // Mark payload is the actual video source, held across the toggle CDC.
    input wire event_mark_toggle,
    input wire [5:0] event_mark_bank,
    input wire [31:0] event_mark_frame_id,
    input wire event_recall_toggle,
    output reg event_valid,event_expired,
    output reg [2:0] event_status,
    output reg [5:0] event_selected_index,
    output reg [5:0] display_bank,
    output reg [31:0] display_frame_id,
    output reg display_frame_toggle,
    output reg [31:0] capture_count
);
    localparam BURST_BYTES=C_BURST_LEN*16;
    localparam RGB_READ_BEATS=IMG_WIDTH/16;
    localparam RGB_READ_BYTES=IMG_WIDTH;
    localparam MAP_READ_BEATS=((IMG_WIDTH/2)+127)/128;
    localparam MAP_ROW_BYTES=MAP_READ_BEATS*16;
    localparam [31:0] MAP_BASE0=32'h01200000,MAP_BASE1=32'h01240000;
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
    //0=current RGB,1=reference RGB,2=published Canny map row.
    reg [1:0] read_kind;
    wire read_reference=read_kind==1;
    wire read_map=read_kind==2;
    reg read_half;
    reg [8:0] half_progress,read_rgb_beats;
    wire [8:0] half_remaining=RGB_READ_BEATS-half_progress;
    wire [8:0] page_remaining=9'd256-{1'b0,read_offset[11:4]};
    wire [8:0] next_rgb_beats=half_remaining<page_remaining?half_remaining:page_remaining;
    wire [8:0] current_half_beat=half_progress+read_beat;
    reg [15:0] read_row;
    (* async_reg="true" *) reg [1:0] canny_sync,slot_sync;
    (* async_reg="true" *) reg [2:0] request_sync,release_sync,publish_sync;
    reg release_seen;
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
    wire rgb_full,rgb_empty,rgb_busy,mask_full,mask_empty,mask_busy;
    wire read_full=rgb_full||mask_full;
    wire read_empty=rgb_empty||mask_empty;
    wire read_busy=rgb_busy||mask_busy;
    wire mask_data;
    wire [15:0] read_data;
    wire write_pop=axi_wvalid&&axi_wready;
    wire read_take=axi_rvalid&&axi_rready;

    reg capture_vsync_d,capture_armed,capture_bad;
    reg capture_started,capture_boundary_seen;
    reg [24:0] camera_word_count;
    reg capture_eof_toggle,capture_good,camera_quiesced;
    (* async_reg="true" *) reg [1:0] writer_reset_sync,capture_ack_sync,stop_sync;
    wire capture_end=capture_vsync_d&&!wframe_vsync;
    wire capture_admit=!capture_started&&capture_boundary_seen&&
        capture_ack_sync[1]==capture_eof_toggle&&!writer_reset_sync[1]&&
        !write_busy&&!stop_sync[1];
    wire capture_accept=(capture_armed||capture_admit)&&wframe_data_en&&
        !writer_reset_sync[1]&&!write_busy&&(camera_word_count<FRAME_WORDS);
    always @(posedge wframe_pclk or posedge axi_reset) begin
        if(axi_reset) begin
            capture_vsync_d<=0;capture_armed<=0;capture_started<=0;
            capture_boundary_seen<=0;capture_bad<=0;camera_word_count<=0;
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
                    capture_good<=!capture_bad&&(camera_word_count==FRAME_WORDS);
                    capture_eof_toggle<=!capture_eof_toggle;
                end
                camera_word_count<=0;capture_bad<=0;capture_armed<=0;
                capture_started<=0;capture_boundary_seen<=1;
            end else if(wframe_data_en) begin
                if(!capture_started) begin
                    capture_started<=1;capture_armed<=capture_admit;
                end
                if(capture_armed||capture_admit) begin
                    if(camera_word_count<FRAME_WORDS+1) camera_word_count<=camera_word_count+1'b1;
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
    (* async_reg="true" *) reg [1:0] pixel_mask_meta,pixel_mask_sync;
    wire [1:0] mask_kind=(active_mode==2)?2'd1:
        ((active_mode==0&&canny_display_valid)?2'd2:2'd0);
    always @(posedge rframe_pclk or posedge axi_reset) begin
        if(axi_reset) begin
            display_vsync_d<=0;display_toggle<=0;display_bad<=0;read_valid_sync<=0;
            pixel_mask_meta<=0;pixel_mask_sync<=0;
        end else begin
            pixel_mask_meta<=mask_kind;pixel_mask_sync<=pixel_mask_meta;
            display_vsync_d<=rframe_vsync;
            read_valid_sync<={read_valid_sync[0],read_valid};
            if(display_vsync_d&&!rframe_vsync) begin
                display_toggle<=!display_toggle;display_bad<=0;
            end else if(rframe_data_en&&read_valid_sync[1]&&read_empty) display_bad<=1;
        end
    end

    // Reference scratch holds one RGB half-line. Published map scratch holds
    // one right-half row, padded to128bits. Map bit0 is its leftmost pixel.
    // Synchronous reads add one common stage to RGB and its mask metadata.
    reg [127:0] reference_burst [0:RGB_READ_BEATS-1];
    reg [127:0] map_burst [0:MAP_READ_BEATS-1];
    reg [127:0] reference_word,selected_word,map_word;
    reg [3:0] map_lane;
    reg selected_valid,current_valid,selected_edge_valid;
    always @(posedge axi_clk) begin
        if(read_take&&read_reference) reference_burst[read_beat]<=axi_rdata;
        if(read_take&&read_map) map_burst[read_beat]<=axi_rdata;
        if(read_take&&read_kind==0) begin
            reference_word<=reference_burst[read_beat];
            map_word<=map_burst[current_half_beat>>4];
            map_lane<=current_half_beat[3:0];
            selected_word<=axi_rdata;
        end
    end
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin selected_valid<=0;current_valid<=0;selected_edge_valid<=0;end
        else begin
            current_valid<=read_take&&read_kind==0;
            selected_valid<=read_take&&read_kind==0&&(active_mode==2);
            selected_edge_valid<=read_take&&read_kind==0&&read_half&&
                active_mode==0&&canny_display_valid;
        end
    end
    wire [7:0] map_eight=map_word>>{map_lane,3'b0};
    wire [7:0] map_fifo_order={map_eight[0],map_eight[1],map_eight[2],map_eight[3],
        map_eight[4],map_eight[5],map_eight[6],map_eight[7]};
    wire diff_valid;
    wire [127:0] diff_data;
    wire [7:0] diff_mask;
    case4_frame_mask128 difference(
        .clk(axi_clk),.reset(axi_reset),.in_valid(selected_valid),
        .in_selected(selected_word),.in_reference(reference_word),
        .threshold(threshold_latched),.out_valid(diff_valid),.out_data(diff_data),
        .out_mask(diff_mask));
    wire fifo_push=(active_mode==2)?diff_valid:current_valid;
    wire [127:0] fifo_data=(active_mode==2)?diff_data:selected_word;
    R0_FIFO_16 display_fifo(
        .wr_clk_i(axi_clk),.wr_en_i(fifo_push),.wdata(fifo_data),
        .a_rst_i(axi_reset||read_fifo_reset),.prog_full_o(rgb_full),.rst_busy(rgb_busy),
        .rd_clk_i(rframe_pclk),
        .rd_en_i(rframe_data_en&&read_valid_sync[1]&&!read_empty),
        .rdata(read_data),.empty_o(rgb_empty));
    R0_FIFO_MASK change_fifo(
        .wr_clk_i(axi_clk),.wr_en_i(fifo_push),
        .wdata((active_mode==2)?diff_mask:(selected_edge_valid?map_fifo_order:8'b0)),
        .a_rst_i(axi_reset||read_fifo_reset),.prog_full_o(mask_full),.rst_busy(mask_busy),
        .rd_clk_i(rframe_pclk),
        .rd_en_i(rframe_data_en&&read_valid_sync[1]&&!read_empty),
        .rdata(mask_data),.empty_o(mask_empty));
    assign rframe_data=read_valid_sync[1]&&!read_empty&&!display_bad?read_data:16'b0;
    assign rframe_change=read_valid_sync[1]&&!read_empty&&!display_bad&&mask_data&&pixel_mask_sync==1;
    assign rframe_edge=read_valid_sync[1]&&!read_empty&&!display_bad&&mask_data&&pixel_mask_sync==2;

    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin
            eof_sync<=0;display_sync<=0;quiesced_sync<=0;freeze_sync<=0;
            canny_sync<=0;slot_sync<=0;request_sync<=0;release_sync<=0;publish_sync<=0;
            mode_meta<=0;mode_sync<=0;mode_previous<=0;mode_ui<=0;
            pause_sync<=0;threshold_meta<=32;threshold_sync<=32;
            prev_sync<=0;next_sync<=0;reference_sync<=0;
        end else begin
            eof_sync<={eof_sync[1:0],capture_eof_toggle};
            display_sync<={display_sync[1:0],display_toggle};
            quiesced_sync<={quiesced_sync[1:0],camera_quiesced};
            freeze_sync<={freeze_sync[0],freeze_request};
            canny_sync<={canny_sync[0],canny_enable};slot_sync<={slot_sync[0],publish_slot};
            request_sync<={request_sync[1:0],process_request_toggle};
            release_sync<={release_sync[1:0],process_release_toggle};
            publish_sync<={publish_sync[1:0],publish_toggle};
            mode_meta<=history_mode;mode_sync<=mode_meta;mode_previous<=mode_sync;
            if(mode_sync==mode_previous) mode_ui<=(mode_sync==3)?0:mode_sync;
            pause_sync<={pause_sync[0],history_paused};
            threshold_meta<=compare_threshold;threshold_sync<=threshold_meta;
            prev_sync<={prev_sync[1:0],step_prev_toggle};
            next_sync<={next_sync[1:0],step_next_toggle};
            reference_sync<={reference_sync[1:0],reference_toggle};
        end
    end

    // Reader and asynchronous processor independently pin committed RGB banks.
    // Evict the oldest unpinned entry; with at least8physical slots, one of
    // the oldest3 is available and cannot be latest (also protected against
    // a same-clock request/read selecting latest during a writer commit).
    wire pin0=(read_valid&&history_bank[0]==read_bank)||
        (process_valid&&history_bank[0]==process_bank);
    wire pin1=(read_valid&&history_bank[1]==read_bank)||
        (process_valid&&history_bank[1]==process_bank);
    wire [1:0] evict_index=!pin0?0:!pin1?1:2;
    wire [C_BANK_BITS-1:0] evicted_bank=history_bank[evict_index];
    // A generation is assigned only after the complete frame and every BRESP
    // have retired successfully. An evicted bank expires immediately, before
    // its next write, so address reuse can never impersonate a saved event.
    wire commit_frame=(ws==W_IDLE)&&end_pending&&end_good&&!write_failed&&
        write_offset==C_RD_END_ADDR;
    wire evict_frame=commit_frame&&(history_count==HISTORY_MAX);
    reg [31:0] capture_sequence;
    reg [SLOTS-1:0] bank_retained;
    reg [31:0] generation_display [0:SLOTS-1];
    reg [31:0] generation_event [0:SLOTS-1];
    always @(posedge axi_clk) if(commit_frame&&!axi_reset) begin
        generation_display[write_bank]<=capture_sequence+1'b1;
        generation_event[write_bank]<=capture_sequence+1'b1;
    end
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin capture_sequence<=0;bank_retained<=0;end
        else if(commit_frame) begin
            capture_sequence<=capture_sequence+1'b1;
            bank_retained[write_bank]<=1;
            if(evict_frame) bank_retained[evicted_bank]<=0;
        end
    end

    // Two small synchronous-read RAM copies avoid wide asynchronous muxes.
    // Publish the metadata after selection, then toggle one UI clock later.
    // The receiver synchronizes payload twice and each toggle three times,
    // binding this identity at the next active-video frame start, after blank.
    wire display_boundary=(rs==R_IDLE)&&read_pending;
    reg [2:0] metadata_phase;
    reg [31:0] metadata_id,metadata_capture;
    reg [5:0] metadata_bank;
    reg metadata_valid,display_identity_valid,metadata_changed;
    always @(posedge axi_clk) if(metadata_phase[0])
        metadata_id<=generation_display[read_bank];
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin
            metadata_phase<=0;metadata_capture<=0;metadata_bank<=0;
            metadata_valid<=0;display_identity_valid<=0;metadata_changed<=0;
            display_bank<=0;display_frame_id<=0;capture_count<=0;
            display_frame_toggle<=0;history_status_toggle<=0;
        end else begin
            metadata_phase<={metadata_phase[1:0],display_boundary};
            if(metadata_phase[0]) begin
                metadata_bank<=read_bank;metadata_valid<=read_valid;
                metadata_capture<=capture_sequence;
            end
            if(metadata_phase[1]) begin
                display_bank<=metadata_bank;
                display_frame_id<=metadata_valid?metadata_id:0;
                capture_count<=metadata_capture;
                display_identity_valid<=metadata_valid;
                metadata_changed<=metadata_valid&&(!display_identity_valid||
                    display_frame_id!=metadata_id||display_bank!=metadata_bank);
            end
            if(metadata_phase[2]) begin
                history_status_toggle<=!history_status_toggle;
                if(metadata_changed) display_frame_toggle<=!display_frame_toggle;
            end
        end
    end

    localparam EVENT_NONE=0,EVENT_SAVED=1,EVENT_PENDING=2,EVENT_RECALLED=3,
        EVENT_EXPIRED=4,EVENT_CANCELLED=5,EVENT_INVALID=6;
    (* async_reg="true" *) reg [2:0] mark_sync,recall_sync;
    (* async_reg="true" *) reg [5:0] mark_bank_meta,mark_bank_sync;
    (* async_reg="true" *) reg [31:0] mark_id_meta,mark_id_sync;
    reg mark_seen,recall_seen,mark_check,mark_was_retained;
    reg [5:0] mark_bank_latched,saved_event_bank;
    reg [31:0] mark_id_latched,mark_generation,saved_event_id;
    reg recall_pending,recall_saw_history;
    wire mark_command=mark_sync[2]!=mark_seen;
    wire recall_command=recall_sync[2]!=recall_seen;
    wire event_evicted=evict_frame&&evicted_bank==saved_event_bank;
    wire event_eligible=event_valid&&!event_evicted;
    reg event_found;
    reg [5:0] event_lookup;
    integer event_scan;
    always @* begin
        event_found=0;event_lookup=0;
        for(event_scan=0;event_scan<HISTORY_MAX;event_scan=event_scan+1)
            if(event_scan<history_count&&history_bank[event_scan]==saved_event_bank) begin
                event_found=1;event_lookup=event_scan;
            end
    end
    wire recall_apply=display_boundary&&mode_ui!=0&&snapshot_settled&&
        (recall_pending||recall_command)&&event_eligible&&event_found&&
        !mark_command&&!mark_check;
    always @(posedge axi_clk) if(mark_command)
        mark_generation<=generation_event[mark_bank_sync[C_BANK_BITS-1:0]];
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin
            mark_sync<=0;recall_sync<=0;mark_bank_meta<=0;mark_bank_sync<=0;
            mark_id_meta<=0;mark_id_sync<=0;mark_seen<=0;recall_seen<=0;
            mark_check<=0;mark_was_retained<=0;mark_bank_latched<=0;mark_id_latched<=0;
            saved_event_bank<=0;saved_event_id<=0;recall_pending<=0;recall_saw_history<=0;
            event_valid<=0;event_expired<=0;event_status<=EVENT_NONE;event_selected_index<=0;
        end else begin
            mark_sync<={mark_sync[1:0],event_mark_toggle};
            recall_sync<={recall_sync[1:0],event_recall_toggle};
            mark_bank_meta<=event_mark_bank;mark_bank_sync<=mark_bank_meta;
            mark_id_meta<=event_mark_frame_id;mark_id_sync<=mark_id_meta;
            mark_seen<=mark_sync[2];recall_seen<=recall_sync[2];
            mark_check<=mark_command;
            if(recall_pending&&mode_ui!=0) recall_saw_history<=1;
            if(recall_command) begin
                if(event_eligible) begin
                    recall_pending<=1;recall_saw_history<=mode_ui!=0||active_mode!=0;
                    event_status<=EVENT_PENDING;
                end else begin
                    recall_pending<=0;
                    event_status<=event_expired||event_evicted?EVENT_EXPIRED:EVENT_INVALID;
                end
            end
            // Returning LIVE after history was requested explicitly cancels a
            // pending recall. A recall arriving before mode CDC is held safely.
            if(recall_pending&&recall_saw_history&&mode_ui==0) begin
                recall_pending<=0;event_status<=EVENT_CANCELLED;
            end
            if(recall_apply) begin
                recall_pending<=0;recall_saw_history<=0;
                event_selected_index<=event_lookup;event_status<=EVENT_RECALLED;
            end
            if(display_boundary&&mode_ui==0&&active_mode!=0&&event_status==EVENT_RECALLED)
                event_status<=EVENT_SAVED;
            if(event_valid&&event_evicted) begin
                event_valid<=0;event_expired<=1;event_status<=EVENT_EXPIRED;recall_pending<=0;
            end
            if(mark_command) begin
                mark_bank_latched<=mark_bank_sync;mark_id_latched<=mark_id_sync;
                mark_was_retained<=mark_bank_sync<SLOTS&&
                    bank_retained[mark_bank_sync[C_BANK_BITS-1:0]]&&
                    !(evict_frame&&evicted_bank==mark_bank_sync);
                recall_pending<=0;recall_saw_history<=0;
            end
            if(mark_check) begin
                recall_pending<=0;
                if(mark_bank_latched>=SLOTS) begin
                    event_valid<=0;event_expired<=0;event_status<=EVENT_INVALID;
                end else if(mark_was_retained&&bank_retained[mark_bank_latched[C_BANK_BITS-1:0]]&&
                    mark_generation==mark_id_latched&&
                    !(evict_frame&&evicted_bank==mark_bank_latched)) begin
                    saved_event_bank<=mark_bank_latched;saved_event_id<=mark_id_latched;
                    event_valid<=1;event_expired<=0;event_status<=EVENT_SAVED;
                end else begin
                    event_valid<=0;event_expired<=1;event_status<=EVENT_EXPIRED;
                end
            end
        end
    end
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
                                    if(h>=evict_index) history_bank[h]<=history_bank[h+1];
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
            if(recall_apply) begin next_selected=event_lookup;next_replay_count=0;end
        end
    end
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin
            rs<=R_RESET;read_bank<=0;reference_bank<=0;read_valid<=0;read_pending<=1;
            read_offset<=0;read_beat<=0;read_reset_count<=63;read_fifo_reset<=1;
            read_error<=0;frozen<=0;read_kind<=0;drain_count<=0;
            read_half<=0;read_row<=0;half_progress<=0;read_rgb_beats<=RGB_READ_BEATS;canny_display_slot<=0;canny_display_valid<=0;
            process_ack_toggle<=0;process_valid<=0;process_bank<=0;
            publish_ack_toggle<=0;release_seen<=0;
            history_ready<=0;selected_index<=0;reference_index<=0;active_mode<=0;
            active_paused<=0;replay_count<=0;threshold_latched<=32;
            prev_seen<=0;next_seen<=0;reference_seen<=0;
            prev_pending<=0;next_pending<=0;reference_pending<=0;
        end else begin
            // Commands use stable payloads held until their acknowledged toggle.
            // Request while already pinned is idempotent. Release is legal only
            // after the external processing reader has drained all AXI traffic.
            release_seen<=release_sync[2];
            if(request_sync[2]!=process_ack_toggle) begin
                process_ack_toggle<=request_sync[2];
                if(!process_valid&&mode_ui==0&&active_mode==0&&canny_sync[1]&&latest_valid&&
                    release_sync[2]==release_seen) begin
                    process_valid<=1;process_bank<=latest_bank;
                end
            end
            if(release_sync[2]!=release_seen) process_valid<=0;
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
                            if((!canny_sync[1]||!canny_display_valid)&&
                                (!frozen||!freeze_sync[1]||!read_valid||active_mode!=0)&&latest_valid) begin
                                read_bank<=latest_bank;read_valid<=1;
                            end
                            frozen<=freeze_sync[1]&&(read_valid||latest_valid);
                            if(!canny_sync[1]) canny_display_valid<=0;
                        end else if(snapshot_settled) begin
                            canny_display_valid<=0;
                            active_mode<=mode_ui;active_paused<=recall_apply?1'b1:pause_sync[1];history_ready<=1;
                            selected_index<=next_selected;reference_index<=next_reference;
                            replay_count<=next_replay_count;
                            if(history_count!=0) begin
                                read_bank<=history_bank[next_selected];
                                reference_bank<=history_bank[next_reference];read_valid<=1;
                            end else read_valid<=0;
                            frozen<=history_count!=0;
                            prev_pending<=0;next_pending<=0;reference_pending<=0;
                        end
                        // Publish ONLY at blanking, after all selected read and
                        // mask-pipeline traffic drained. An acknowledged cancelled
                        // publication retains its process pin until explicit release.
                        if(publish_sync[2]!=publish_ack_toggle) begin
                            publish_ack_toggle<=publish_sync[2];
                            if(mode_ui==0&&canny_sync[1]&&!freeze_sync[1]&&process_valid&&
                                release_sync[2]==release_seen) begin
                                read_bank<=process_bank;read_valid<=1;
                                canny_display_slot<=slot_sync[1];canny_display_valid<=1;
                                process_valid<=0;
                            end
                        end
                        if(mode_ui!=0) canny_display_valid<=0;
                        threshold_latched<=threshold_sync;
                        read_offset<=0;read_kind<=0;read_half<=0;read_row<=0;half_progress<=0;read_fifo_reset<=1;
                        read_reset_count<=63;rs<=R_RESET;
                    end else if(read_valid&&!read_full&&read_offset<C_RD_END_ADDR) begin
                        read_kind<=(active_mode==2)?1:
                            ((active_mode==0&&canny_display_valid&&read_half&&half_progress==0)?2:0);
                        read_rgb_beats<=next_rgb_beats;read_beat<=0;rs<=R_ADDR;
                    end
                end
                R_ADDR: if(axi_arready) rs<=R_DATA;
                R_DATA: if(read_take) begin
                    if(axi_rlast!=(read_beat==((read_map?MAP_READ_BEATS:read_rgb_beats)-1))) read_error<=1;
                    if(axi_rlast) begin
                        read_beat<=0;
                        if(read_kind!=0) begin read_kind<=0;rs<=R_ADDR;end
                        else begin
                            read_offset<=read_offset+(read_rgb_beats<<4);
                            if(half_progress+read_rgb_beats==RGB_READ_BEATS) begin
                                half_progress<=0;read_half<=!read_half;
                                if(read_half) read_row<=read_row+1'b1;
                            end else half_progress<=half_progress+read_rgb_beats;
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
    assign axi_araddr=read_map?
        ((canny_display_slot?MAP_BASE1:MAP_BASE0)+read_row*MAP_ROW_BYTES):
        (C_HISTORY_BASE+({{(32-C_BANK_BITS){1'b0}},(read_reference?reference_bank:read_bank)}<<C_BUF_SIZE)+read_offset);
    assign axi_awlen=C_BURST_LEN-1;
    assign axi_arlen=(read_map?MAP_READ_BEATS:read_rgb_beats)-1;
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
