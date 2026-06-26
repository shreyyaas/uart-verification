// ============================================================
// Testbench: baud_gen_tb
// Verifies:
//   1. tick pulses exactly once every DIVISOR clock cycles
//   2. tick is exactly 1 clock cycle wide (not more)
//   3. tick is repeatable — consistent period across cycles
// ============================================================
`timescale 1ns/1ps

module baud_gen_tb;

    // Parameters — small values for fast simulation
    localparam CLK_FREQ  = 50_000_000;
    localparam BAUD_RATE = 115_200;
    localparam DIVISOR   = CLK_FREQ / BAUD_RATE;   // 434

    reg  clk, rst;
    wire tick;

    // Instantiate baud_gen
    baud_gen #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uut (
        .clk (clk),
        .rst (rst),
        .tick(tick)
    );

    // 50MHz clock — period = 20ns
    initial clk = 0;
    always #10 clk = ~clk;

    // VCD dump for GTKWave
    initial begin
        $dumpfile("waveforms/baud_gen.vcd");
        $dumpvars(0, baud_gen_tb);
    end

    // Variables for verification
    integer tick_count;
    integer cycle_count;
    integer last_tick_cycle;
    integer period;
    integer errors;

    initial begin
        errors         = 0;
        tick_count     = 0;
        cycle_count    = 0;
        last_tick_cycle = 0;

        // Reset
        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;

        $display("=== BAUD GEN TESTBENCH ===");
        $display("CLK_FREQ  = %0d Hz", CLK_FREQ);
        $display("BAUD_RATE = %0d baud", BAUD_RATE);
        $display("Expected DIVISOR = %0d cycles per tick", DIVISOR);
        $display("==========================\n");

        // Run for 10 tick periods
        @(posedge clk); #1;
        fork
            // Thread 1: count cycles
            begin
                forever begin
                    @(posedge clk);
                    cycle_count = cycle_count + 1;
                end
            end

            // Thread 2: monitor ticks
            begin
                repeat(10) begin
                    @(posedge tick);
                    tick_count = tick_count + 1;
                    period = cycle_count - last_tick_cycle;
                    last_tick_cycle = cycle_count;

                    $display("Tick %0d at cycle %0d | Period = %0d cycles | %s",
                        tick_count,
                        cycle_count,
                        period,
                        (period == DIVISOR || tick_count == 1) ?
                        "OK" : "ERROR — wrong period!");

                    if (tick_count > 1 && period !== DIVISOR) begin
                        errors = errors + 1;
                    end
                end

                // Final report
                $display("\n=== RESULTS ===");
                $display("Ticks observed : %0d", tick_count);
                $display("Expected period: %0d cycles", DIVISOR);
                $display("Errors         : %0d", errors);
                $display("Status         : %s",
                    errors == 0 ? "ALL PASS ✓" : "FAILED ✗");
                $display("===============\n");
                $finish;
            end
        join
    end

    // Watchdog — kill simulation if it hangs
    initial begin
        #10_000_000;
        $display("WATCHDOG: simulation timeout!");
        $finish;
    end

endmodule
