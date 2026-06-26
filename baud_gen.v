// ============================================================
// Module: baud_gen
// Description: Baud rate generator
//   Counts system clock cycles and pulses 'tick' once every
//   (CLK_FREQ / BAUD_RATE) cycles — one tick = one bit period
//
// Parameters:
//   CLK_FREQ  = system clock frequency in Hz (default 50MHz)
//   BAUD_RATE = desired baud rate (default 115200)
//
// Example: 50MHz / 115200 = 434 cycles per bit
// ============================================================
module baud_gen #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire clk,
    input  wire rst,
    output reg  tick        // pulses high for 1 cycle every bit period
);

    // Number of clock cycles per bit period
    localparam DIVISOR = CLK_FREQ / BAUD_RATE;

    // Counter — counts from 0 to DIVISOR-1
    reg [$clog2(DIVISOR)-1:0] count;

    always @(posedge clk) begin
        if (rst) begin
            count <= 0;
            tick  <= 0;
        end
        else if (count == DIVISOR - 1) begin
            count <= 0;
            tick  <= 1;     // pulse tick for exactly 1 clock cycle
        end
        else begin
            count <= count + 1;
            tick  <= 0;
        end
    end

endmodule
EOF
