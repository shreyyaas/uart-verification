// ============================================================
// Testbench: uart_tb — Layer 1: Baseline end-to-end test
// TX output wired directly to RX input (loopback)
// 6 directed test vectors covering all critical patterns
// ============================================================
`timescale 1ns/1ps

module uart_tb;
    localparam CLK_FREQ  = 50_000_000;
    localparam BAUD_RATE = 115_200;

    reg clk, rst;
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_out, tx_busy, tx_done;
    wire [7:0] rx_data;
    wire       rx_done, rx_error;
    wire       tick;

    baud_gen #(.CLK_FREQ(CLK_FREQ),.BAUD_RATE(BAUD_RATE))
    u_baud (.clk(clk),.rst(rst),.tick(tick));

    uart_tx u_tx (
        .clk(clk),.rst(rst),.tick(tick),
        .tx_start(tx_start),.tx_data(tx_data),
        .tx_out(tx_out),.tx_busy(tx_busy),.tx_done(tx_done));

    uart_rx #(.CLK_FREQ(CLK_FREQ),.BAUD_RATE(BAUD_RATE))
    u_rx (
        .clk(clk),.rst(rst),
        .rx_in(tx_out),
        .rx_data(rx_data),.rx_done(rx_done),.rx_error(rx_error));

    initial clk = 0;
    always #10 clk = ~clk;

    initial begin
        $dumpfile("waveforms/uart_full.vcd");
        $dumpvars(0, uart_tb);
    end

    integer errors;

    task send_and_verify;
        input [7:0] data;
        begin
            wait(!tx_busy);
            @(posedge clk); #1;
            tx_data  = data;
            tx_start = 1;
            @(posedge clk); #1;
            tx_start = 0;
            wait(rx_done);
            @(posedge clk); #1;
            $display("TX=0x%02h (%08b) | RX=0x%02h (%08b) | Err=%b | %s",
                data, data, rx_data, rx_data, rx_error,
                (rx_data === data && !rx_error) ? "PASS" : "FAIL");
            if (rx_data !== data || rx_error)
                errors = errors + 1;
        end
    endtask

    initial begin
        errors = 0; tx_start = 0; tx_data = 0;
        rst = 1; repeat(10) @(posedge clk); rst = 0;
        repeat(5) @(posedge clk);

        $display("\n=== UART END-TO-END TESTBENCH ===");
        $display("------------------------------------------");

        send_and_verify(8'h00);
        send_and_verify(8'hFF);
        send_and_verify(8'h55);
        send_and_verify(8'hAA);
        send_and_verify(8'hA5);
        send_and_verify(8'h3C);

        $display("\n=== RESULTS ===");
        $display("Tests  : 6");
        $display("Errors : %0d", errors);
        $display("Status : %s", errors==0 ? "ALL PASS" : "FAILED");
        $display("===============\n");
        $finish;
    end

    initial begin
        #500_000_000;
        $display("WATCHDOG: simulation timeout");
        $finish;
    end
endmodule
