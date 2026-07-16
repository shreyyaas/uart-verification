// ============================================================
// Module: uart_rx
// Description: UART Receiver
//   FSM: IDLE → START → DATA → STOP → IDLE
//   Detects start bit via falling edge
//   Samples at middle of each bit for noise immunity
//   Reconstructs 8 data bits, LSB first
// ============================================================
module uart_rx (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx_in,        // serial input line
    output reg  [7:0] rx_data,      // reconstructed byte
    output reg        rx_done,      // pulses high when byte ready
    output reg        rx_error      // high if stop bit invalid
);

    // ---- Parameters ----
    parameter CLK_FREQ  = 50_000_000;
    parameter BAUD_RATE = 115_200;

    localparam DIVISOR      = CLK_FREQ / BAUD_RATE;       // 434
    localparam HALF_DIVISOR = DIVISOR / 2;                // 217

    // ---- FSM states ----
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    // ---- Internal registers ----
    reg [1:0]  state;
    reg [8:0]  sample_cnt;   // counts clock cycles for bit timing
    reg [2:0]  bit_cnt;      // counts 0-7 data bits received
    reg [7:0]  shift_reg;    // assembles incoming bits

    // ---- RX line synchroniser ----
    // Synchronise rx_in to local clock domain
    // Two FF synchroniser prevents metastability
    reg rx_sync1, rx_sync2;
    wire rx;

    always @(posedge clk) begin
        rx_sync1 <= rx_in;
        rx_sync2 <= rx_sync1;
    end
    assign rx = rx_sync2;   // use synchronised version

    // ---- Falling edge detection ----
    reg rx_prev;
    wire start_detected;

    always @(posedge clk) begin
        rx_prev <= rx;
    end

    assign start_detected = rx_prev & ~rx;
    // rx_prev=1, rx=0 → falling edge → start bit detected

    // ---- Main FSM ----
    always @(posedge clk) begin
        if (rst) begin
            state      <= IDLE;
            sample_cnt <= 0;
            bit_cnt    <= 0;
            shift_reg  <= 8'b0;
            rx_data    <= 8'b0;
            rx_done    <= 1'b0;
            rx_error   <= 1'b0;
        end
        else begin
            // Default — clear single-cycle pulses
            rx_done  <= 1'b0;
            rx_error <= 1'b0;

            case (state)

                // ----------------------------------------
                // IDLE: wait for falling edge on RX line
                // ----------------------------------------
                IDLE: begin
                    if (start_detected) begin
                        sample_cnt <= 0;
                        state      <= START;
                    end
                end

                // ----------------------------------------
                // START: wait half bit period then verify
                // ----------------------------------------
                START: begin
                    if (sample_cnt == HALF_DIVISOR - 1) begin
                        sample_cnt <= 0;
                        // Verify line is still low
                        // (not a glitch — real start bit)
                        if (rx == 1'b0) begin
                            bit_cnt  <= 0;
                            state    <= DATA;
                        end
                        else begin
                            // False start — go back to idle
                            state <= IDLE;
                        end
                    end
                    else begin
                        sample_cnt <= sample_cnt + 1;
                    end
                end

                // ----------------------------------------
                // DATA: sample 8 bits, one per bit period
                // ----------------------------------------
                DATA: begin
                    if (sample_cnt == DIVISOR - 1) begin
                        sample_cnt        <= 0;
                        shift_reg         <= {rx, shift_reg[7:1]};
                        // Shift in from MSB side, rx fills top
                        // After 8 shifts: bit 0 received first
                        // ends up at position 0 — LSB correct
                        bit_cnt           <= bit_cnt + 1;
                        if (bit_cnt == 3'd7)
                            state <= STOP;
                    end
                    else begin
                        sample_cnt <= sample_cnt + 1;
                    end
                end

                // ----------------------------------------
                // STOP: sample stop bit, output data
                // ----------------------------------------
                STOP: begin
                    if (sample_cnt == DIVISOR - 1) begin
                        sample_cnt <= 0;
                        if (rx == 1'b1) begin
                            // Valid stop bit
                            rx_data <= shift_reg;
                            rx_done <= 1'b1;
                        end
                        else begin
                            // Invalid stop bit — framing error
                            rx_error <= 1'b1;
                        end
                        state <= IDLE;
                    end
                    else begin
                        sample_cnt <= sample_cnt + 1;
                    end
                end

            endcase
        end
    end

endmodule
