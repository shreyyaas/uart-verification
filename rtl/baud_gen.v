// ============================================================
// Module: baud_gen
// Description: Baud rate generator
//   Counts system clock cycles, pulses tick once per bit period
//   CLK_FREQ / BAUD_RATE = 50MHz / 115200 = 434 cycles per bit
// ============================================================
module baud_gen #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire clk,
    input  wire rst,
    output reg  tick
);
    localparam DIVISOR = CLK_FREQ / BAUD_RATE;
    reg [$clog2(DIVISOR)-1:0] count;

    always @(posedge clk) begin
        if (rst) begin
            count <= 0;
            tick  <= 0;
        end
        else if (count == DIVISOR - 1) begin
            count <= 0;
            tick  <= 1;
        end
        else begin
            count <= count + 1;
            tick  <= 0;
        end
    end
endmodule

