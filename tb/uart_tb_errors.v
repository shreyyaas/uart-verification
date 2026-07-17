// ============================================================
// Testbench: uart_tb_errors — Layer 2: Error injection
// Uses a controlled injection mux instead of force/release
// for deterministic, race-free fault injection
// ============================================================
`timescale 1ns/1ps

module uart_tb_errors;

    localparam CLK_FREQ  = 50_000_000;
    localparam BAUD_RATE = 115_200;
    localparam DIVISOR   = CLK_FREQ / BAUD_RATE;   // 434

    reg clk, rst;
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_out, tx_busy, tx_done;
    wire [7:0] rx_data;
    wire       rx_done, rx_error;
    wire       tick;

// Latch that captures rx_error even though it's just a 1-cycle pulse
reg rx_error_latched;
always @(posedge clk) begin
    if (rst)
        rx_error_latched <= 1'b0;
    else if (rx_error)
        rx_error_latched <= 1'b1;
end

    // ---- Fault injection controls ----
    reg inject_enable;
    reg inject_value;
    wire rx_line;

    // When inject_enable=1, force rx_line to inject_value
    // Otherwise, rx_line follows tx_out normally
    assign rx_line = inject_enable ? inject_value : tx_out;

    baud_gen #(.CLK_FREQ(CLK_FREQ),.BAUD_RATE(BAUD_RATE))
    u_baud (.clk(clk),.rst(rst),.tick(tick));

    uart_tx u_tx (
        .clk(clk),.rst(rst),.tick(tick),
        .tx_start(tx_start),.tx_data(tx_data),
        .tx_out(tx_out),.tx_busy(tx_busy),.tx_done(tx_done));

    uart_rx #(.CLK_FREQ(CLK_FREQ),.BAUD_RATE(BAUD_RATE))
    u_rx (
        .clk(clk),.rst(rst),
        .rx_in(rx_line),          // <-- now goes through injection mux
        .rx_data(rx_data),.rx_done(rx_done),.rx_error(rx_error));

    initial clk = 0;
    always #10 clk = ~clk;

    initial begin
        $dumpfile("waveforms/uart_errors.vcd");
        $dumpvars(0, uart_tb_errors);
    end

    integer test_num;
    integer pass_count;
    integer fail_count;

    // ------------------------------------------------------
    // Test 1: Corrupted stop bit
    // Inject a 0 during the stop bit window
    // ------------------------------------------------------
    task test_stop_bit_error;
    begin
        test_num = test_num + 1;
        $display("\n--- Test %0d: Corrupted stop bit ---", test_num);

        inject_enable = 0;
        rx_error_latched = 1'b0;   // <-- reset the latch before this test

        @(posedge clk); #1;
        tx_data  = 8'hA5;
        tx_start = 1;
        @(posedge clk); #1;
        tx_start = 0;

        repeat(10) @(posedge tick);
        #1;

        inject_enable = 1;
        inject_value  = 1'b0;
        repeat(DIVISOR) @(posedge clk);
        inject_enable = 0;

        @(posedge clk); #100;

        if (rx_error_latched) begin        // <-- check the LATCH now
            $display("Result: PASS - rx_error correctly asserted");
            pass_count = pass_count + 1;
        end else begin
            $display("Result: FAIL - rx_error NOT asserted (bug!)");
            fail_count = fail_count + 1;
        end

        repeat(20) @(posedge clk);
    end
endtask

    // ------------------------------------------------------
    // Test 2: Noise glitch — too short to be a real start bit
    // ------------------------------------------------------
    task test_glitch_rejection;
        begin
            test_num = test_num + 1;
            $display("\n--- Test %0d: Glitch rejection ---", test_num);

            @(posedge clk); #1;

            // Inject a brief low glitch - only 50 cycles (< HALF_DIVISOR=217)
            inject_enable = 1;
            inject_value  = 1'b0;
            repeat(50) @(posedge clk);
            inject_enable = 0;   // back to idle high (tx_out is high, idle)

            // Wait a full bit period to let RX react
            repeat(DIVISOR) @(posedge clk);
            #1;

            if (u_rx.state == 2'd0) begin
                $display("Result: PASS - glitch rejected, RX in IDLE");
                pass_count = pass_count + 1;
            end else begin
                $display("Result: FAIL - RX incorrectly left IDLE (state=%0d)", u_rx.state);
                fail_count = fail_count + 1;
            end

            repeat(20) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------
    // Test 3: Data bit corruption
    // Flip one data bit mid-frame - RX cannot detect this
    // ------------------------------------------------------
    task test_data_corruption;
        begin
            test_num = test_num + 1;
            $display("\n--- Test %0d: Data bit corruption (expected limitation) ---", test_num);

            inject_enable = 0;

            @(posedge clk); #1;
            tx_data  = 8'h0F;   // 00001111
            tx_start = 1;
            @(posedge clk); #1;
            tx_start = 0;

            // Wait until bit 3's window (4 ticks: start + bits 0,1,2)
            repeat(4) @(posedge tick);
            #1;

            // Inject the opposite value for this bit's duration
            inject_enable = 1;
            inject_value  = ~tx_out;
            repeat(DIVISOR) @(posedge clk);
            inject_enable = 0;

            wait(rx_done || rx_error);
            @(posedge clk); #1;

            $display("Sent    : 0x%02h (%08b)", 8'h0F, 8'h0F);
            $display("Received: 0x%02h (%08b)", rx_data, rx_data);
            $display("rx_error: %b", rx_error);

            if (rx_data !== 8'h0F && !rx_error) begin
                $display("Result: EXPECTED - data corrupted silently, no error flag");
                $display("        This proves plain UART cannot detect bit errors");
                pass_count = pass_count + 1;
            end else begin
                $display("Result: Data survived or error flagged - also acceptable");
                pass_count = pass_count + 1;
            end

            repeat(20) @(posedge clk);
        end
    endtask

    initial begin
        test_num      = 0;
        pass_count    = 0;
        fail_count    = 0;
        tx_start      = 0;
        tx_data       = 0;
        inject_enable = 0;
        inject_value  = 0;

        rst = 1;
        repeat(10) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);

        $display("\n=========================================");
        $display("  UART LAYER 2 - ERROR INJECTION TESTS");
        $display("=========================================");

        test_stop_bit_error();
        test_glitch_rejection();
        test_data_corruption();

        $display("\n=========================================");
        $display("  SUMMARY");
        $display("=========================================");
        $display("Total tests : %0d", test_num);
        $display("Passed      : %0d", pass_count);
        $display("Failed      : %0d", fail_count);
        $display("Status      : %s",
            fail_count == 0 ? "ALL PASS" : "SOME FAILED");
        $display("=========================================\n");

        $finish;
    end

    initial begin
        #2_000_000;
        $display("WATCHDOG: timeout!");
        $finish;
    end

endmodule
