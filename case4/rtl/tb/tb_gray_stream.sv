`timescale 1ns/1ps

// Small transaction-level smoke test for the RGB unpack and gray blocks.
// It checks both pixel formats, arithmetic, one-cycle latency, and sideband.

module tb_gray_stream;
    localparam integer X_W = 8;
    localparam integer Y_W = 8;

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    reg                 in_valid = 1'b0;
    reg                 in_sof   = 1'b0;
    reg                 in_eol   = 1'b0;
    reg                 in_eof   = 1'b0;
    reg [X_W-1:0]       in_x     = 0;
    reg [Y_W-1:0]       in_y     = 0;
    reg [15:0]          pixel565 = 0;
    reg [23:0]          pixel888 = 0;

    wire                 u565_valid;
    wire                 u565_sof, u565_eol, u565_eof;
    wire [X_W-1:0]       u565_x;
    wire [Y_W-1:0]       u565_y;
    wire [7:0]           u565_r, u565_g, u565_b;
    wire                 u888_valid;
    wire                 u888_sof, u888_eol, u888_eof;
    wire [X_W-1:0]       u888_x;
    wire [Y_W-1:0]       u888_y;
    wire [7:0]           u888_r, u888_g, u888_b;
    wire                 g565_valid, g565_sof, g565_eol, g565_eof;
    wire [X_W-1:0]       g565_x;
    wire [Y_W-1:0]       g565_y;
    wire [7:0]           g565_gray;
    wire [16:0]          g565_acc;
    wire                 g888_valid, g888_sof, g888_eol, g888_eof;
    wire [X_W-1:0]       g888_x;
    wire [Y_W-1:0]       g888_y;
    wire [7:0]           g888_gray;
    wire [16:0]          g888_acc;

    rgb_unpack_stream #(.PIXEL_FORMAT(0), .X_W(X_W), .Y_W(Y_W)) u_unpack565 (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_eof(in_eof), .in_x(in_x), .in_y(in_y),
        .pixel_in({8'd0, pixel565}), .m_valid(u565_valid), .m_sof(u565_sof),
        .m_eol(u565_eol), .m_eof(u565_eof), .m_x(u565_x), .m_y(u565_y),
        .m_r(u565_r), .m_g(u565_g), .m_b(u565_b)
    );

    rgb_unpack_stream #(.PIXEL_FORMAT(1), .X_W(X_W), .Y_W(Y_W)) u_unpack888 (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_eof(in_eof), .in_x(in_x), .in_y(in_y),
        .pixel_in(pixel888), .m_valid(u888_valid), .m_sof(u888_sof),
        .m_eol(u888_eol), .m_eof(u888_eof), .m_x(u888_x), .m_y(u888_y),
        .m_r(u888_r), .m_g(u888_g), .m_b(u888_b)
    );

    gray_rgb_stream #(.PIXEL_FORMAT(0), .X_W(X_W), .Y_W(Y_W)) u_gray565 (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_eof(in_eof), .in_x(in_x), .in_y(in_y),
        .pixel_in({8'd0, pixel565}), .m_valid(g565_valid), .m_sof(g565_sof),
        .m_eol(g565_eol), .m_eof(g565_eof), .m_x(g565_x), .m_y(g565_y),
        .m_gray(g565_gray), .m_acc(g565_acc)
    );

    gray_rgb_stream #(.PIXEL_FORMAT(1), .X_W(X_W), .Y_W(Y_W)) u_gray888 (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_eof(in_eof), .in_x(in_x), .in_y(in_y),
        .pixel_in(pixel888), .m_valid(g888_valid), .m_sof(g888_sof),
        .m_eol(g888_eol), .m_eof(g888_eof), .m_x(g888_x), .m_y(g888_y),
        .m_gray(g888_gray), .m_acc(g888_acc)
    );

    function automatic [7:0] expand5(input [4:0] v);
        expand5 = {v, v[4:2]};
    endfunction
    function automatic [7:0] expand6(input [5:0] v);
        expand6 = {v, v[5:4]};
    endfunction
    function automatic [7:0] expected_gray(
        input [7:0] r, input [7:0] g, input [7:0] b
    );
        integer a;
        begin
            a = 77*r + 150*g + 29*b;
            expected_gray = (a + 128) >> 8;
        end
    endfunction
    function automatic [16:0] expected_acc(
        input [7:0] r, input [7:0] g, input [7:0] b
    );
        begin
            expected_acc = 77*r + 150*g + 29*b;
        end
    endfunction

    integer errors = 0;
    task automatic send_pair;
        input [15:0] p565_i;
        input [23:0] p888_i;
        input [X_W-1:0] x_i;
        input [Y_W-1:0] y_i;
        input s_i;
        input l_i;
        input f_i;
        reg [7:0] r565_e, g565_e, b565_e;
        reg [7:0] r888_e, g888_e, b888_e;
        reg [7:0] y565_e, y888_e;
        reg [16:0] a565_e, a888_e;
        begin
            r565_e = expand5(p565_i[15:11]);
            g565_e = expand6(p565_i[10:5]);
            b565_e = expand5(p565_i[4:0]);
            r888_e = p888_i[23:16];
            g888_e = p888_i[15:8];
            b888_e = p888_i[7:0];
            y565_e = expected_gray(r565_e, g565_e, b565_e);
            y888_e = expected_gray(r888_e, g888_e, b888_e);
            a565_e = expected_acc(r565_e, g565_e, b565_e);
            a888_e = expected_acc(r888_e, g888_e, b888_e);

            @(negedge clk);
            in_valid = 1'b1;
            in_sof = s_i;
            in_eol = l_i;
            in_eof = f_i;
            in_x = x_i;
            in_y = y_i;
            pixel565 = p565_i;
            pixel888 = p888_i;
            @(posedge clk);
            #1;
            if (!u565_valid || !u888_valid || !g565_valid || !g888_valid) begin
                $display("ERROR valid latency at x=%0d y=%0d", x_i, y_i);
                errors = errors + 1;
            end
            if ({u565_r,u565_g,u565_b} !== {r565_e,g565_e,b565_e}) begin
                $display("ERROR RGB565 unpack: got %h expected %h", {u565_r,u565_g,u565_b}, {r565_e,g565_e,b565_e});
                errors = errors + 1;
            end
            if ({u888_r,u888_g,u888_b} !== {r888_e,g888_e,b888_e}) begin
                $display("ERROR RGB888 unpack: got %h expected %h", {u888_r,u888_g,u888_b}, {r888_e,g888_e,b888_e});
                errors = errors + 1;
            end
            if (g565_gray !== y565_e || g565_acc !== a565_e) begin
                $display("ERROR RGB565 gray: got %0d/%0d expected %0d/%0d", g565_gray, g565_acc, y565_e, a565_e);
                errors = errors + 1;
            end
            if (g888_gray !== y888_e || g888_acc !== a888_e) begin
                $display("ERROR RGB888 gray: got %0d/%0d expected %0d/%0d", g888_gray, g888_acc, y888_e, a888_e);
                errors = errors + 1;
            end
            if (g888_sof !== s_i || g888_eol !== l_i || g888_eof !== f_i ||
                g888_x !== x_i || g888_y !== y_i) begin
                $display("ERROR sideband at x=%0d y=%0d", x_i, y_i);
                errors = errors + 1;
            end

            @(negedge clk);
            in_valid = 1'b0;
            in_sof = 1'b0;
            in_eol = 1'b0;
            in_eof = 1'b0;
            in_x = 0;
            in_y = 0;
            pixel565 = 0;
            pixel888 = 0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        #1 rst = 1'b0;

        // Exact primary colors in both formats.
        send_pair(16'hF800, 24'hFF0000, 8'd3, 8'd4, 1'b1, 1'b0, 1'b0);
        send_pair(16'h07E0, 24'h00FF00, 8'd4, 8'd4, 1'b0, 1'b1, 1'b0);
        send_pair(16'h001F, 24'h0000FF, 8'd5, 8'd4, 1'b0, 1'b0, 1'b0);
        send_pair(16'h0000, 24'h000000, 8'd6, 8'd4, 1'b0, 1'b0, 1'b1);
        send_pair(16'hFFFF, 24'hFFFFFF, 8'd7, 8'd4, 1'b0, 1'b0, 1'b0);

        // A nontrivial RGB565 expansion and arbitrary RGB888 code.
        send_pair(16'b10001_100001_01001, 24'h0C65EF, 8'd8, 8'd9, 1'b0, 1'b0, 1'b0);

        @(posedge clk);
        #1;
        if (g888_valid || u888_valid) begin
            $display("ERROR valid not cleared during gap");
            errors = errors + 1;
        end
        if (errors == 0)
            $display("tb_gray_stream: PASS");
        else
            $display("tb_gray_stream: FAIL errors=%0d", errors);
        $finish;
    end
endmodule

