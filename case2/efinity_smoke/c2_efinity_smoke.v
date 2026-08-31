// Minimal Efinity CLI smoke design for Ti60F225.
// This file is deliberately independent of the Case 2 IP blackboxes; it only
// verifies that the installed Efinity 2026.1 tool can parse and map a local
// Verilog top for the target device.
module c2_efinity_smoke (
    input  wire clk,
    input  wire rst_n,
    output wire led
);
    reg [23:0] counter;

    always @(posedge clk) begin
        if (!rst_n)
            counter <= 24'd0;
        else
            counter <= counter + 24'd1;
    end

    assign led = counter[23];
endmodule
