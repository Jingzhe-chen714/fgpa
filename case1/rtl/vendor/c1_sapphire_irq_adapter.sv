`timescale 1ns/1ps

// Map the single Case-1 level IRQ to one of Sapphire's eight user interrupt
// inputs.  Sapphire's PLIC expects a level, and c1_apb_csr keeps IRQ asserted
// until software acknowledges the corresponding IRQ_STATUS bit; no pulse
// stretcher is needed here.
module c1_sapphire_irq_adapter #(
    parameter integer USER_INTERRUPT_INDEX = 0
) (
    input  wire       c1_irq,
    output wire [7:0] sapphire_user_interrupt
);

    assign sapphire_user_interrupt =
        ({8{c1_irq}} & (8'b00000001 << USER_INTERRUPT_INDEX));

`ifndef SYNTHESIS
    initial begin
        if ((USER_INTERRUPT_INDEX < 0) || (USER_INTERRUPT_INDEX > 7))
            $fatal(1, "USER_INTERRUPT_INDEX must be in the range 0..7");
    end
`endif

endmodule

