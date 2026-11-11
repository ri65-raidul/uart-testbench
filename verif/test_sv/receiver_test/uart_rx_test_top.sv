module uart_rx_test_top;
    import uart_rx_verif_pkg::*;

    localparam int unsigned TICK_DIV = 8;
    localparam int unsigned FULL = 16;


    // --------------------------------------------------------
    // UART RX Assertions
    // --------------------------------------------------------

    // rx_val must never remain high for consecutive cycles
    property p_rx_val_one_cycle;
        @(posedge clk)
        disable iff (reset)
        rx_val |=> !rx_val;
    endproperty

    a_rx_val_one_cycle: assert property (p_rx_val_one_cycle)
        else $fatal(1,
            "UART RX ASSERTION FAILED: rx_val high for multiple cycles");


    // --------------------------------------------------------
    // DUT Signals
    // --------------------------------------------------------

    logic   clk;
    logic   reset;
    logic   utility_reset;
    logic   reset_inject;
    logic   en;
    logic   tick;
    logic   rx;

    uart_rx_data_t  data;
    logic           rx_val;
    logic           frame_err;


    // --------------------------------------------------------
    // Test Utils
    // --------------------------------------------------------

    TestUtilsClkRst t
    (
        .clk    (clk),
        .rst    (utility_reset)
    );

    assign reset = utility_reset || reset_inject;


    // --------------------------------------------------------
    // Tick Generation
    // --------------------------------------------------------

    int unsigned tick_div_count;

    always_ff @(posedge clk) begin
        if (reset) begin
            tick_div_count  <= 0;
            tick        <= 1'b0;
        end
        else if (tick_div_count == TICK_DIV - 1) begin
            tick_div_count  <= 0;
            tick            <= 1'b1;
        end
        else begin
            tick_div_count  <= tick_div_count + 1;
            tick            <= 1'b0;
        end
    end


    // --------------------------------------------------------
    // DUT
    // --------------------------------------------------------

    uart_Receiver #(
        .DATA_W         (DATA_W)
    ) u_dut (
        .clk            (clk),
        .en             (en),
        .reset          (reset),
        .tick           (tick),
        .rx             (rx),

        // dut outputs
        .data           (data),
        .rx_val         (rx_val),
        .frame_err      (frame_err)
    );


    // --------------------------------------------------------
    // Verif Components
    // --------------------------------------------------------

    uart_rx_driver driver
    (
        .clk            (clk),
        .tick           (tick),
        .rx             (rx)
    );

    uart_rx_model model ();

    uart_rx_monitor monitor
    (
        .clk            (clk),
        // dut outputs
        .data           (data),
        .rx_val         (rx_val),
        .frame_err      (frame_err)
    );

    uart_rx_scoreboard scoreboard ();

    uart_rx_coverage coverage
    (
        .clk            (clk),
        .reset          (reset),
        // dut outputs
        .data           (data),
        .rx_val         (rx_val),
        .frame_err      (frame_err)
    );


    // --------------------------------------------------------
    // Run one UART frame
    // --------------------------------------------------------

    task automatic run_frame(input uart_rx_transaction transaction);
        uart_rx_result_t    expected;
        uart_rx_result_t    actual;

        expected = model.predict(transaction);

        fork
            driver.send_frame(transaction);
            monitor.receive(actual);
        join

        scoreboard.check(expected, actual);

        // Allow driver to idle before next frame
        driver.wait_ticks(FULL);
    endtask


    // --------------------------------------------------------
    // Tests
    // --------------------------------------------------------

    `include "uart_rx_directed_tests.sv"
    `include "uart_rx_random_tests.sv"


 // --------------------------------------------------------
 // Main Test Sequence
 // --------------------------------------------------------

    initial begin
        en              = 1'b0;
        reset_inject    = 1'b0;

        t.test_bench_begin();
        t.test_suite_begin("UART RX Verification");

        // --------------------------------------------------------
        // Test 1: Valid UART frames
        // --------------------------------------------------------

        if (t.n == 0 || t.n == 1) begin

            en = 1'b0;
            t.test_case_begin("Valid UART Frames", 1);
            scoreboard.reset();

            @(negedge clk);
            en = 1'b1;

            repeat (4) @(negedge clk);

            test_valid_frames();

            if (scoreboard.error_count != 0)
                $fatal(1, "Valid frame test failed");

            t.test_case_end();
        end

        // --------------------------------------------------------
        // Test 2: Framing errors
        // --------------------------------------------------------

        if (t.n == 0 || t.n == 2) begin

            en = 1'b0;
            t.test_case_begin("UART Framing Errors", 2);
            scoreboard.reset();

            @(negedge clk);
            en = 1'b1;

            repeat (4) @(negedge clk);

            test_framing_errors();

            if (scoreboard.error_count != 0)
                $fatal(1, "Framing error test failed");

            t.test_case_end();
        end

        // --------------------------------------------------------
        // Test 3: Random UART frames
        // --------------------------------------------------------

        if (t.n == 0 || t.n == 3) begin

            en = 1'b0;
            t.test_case_begin("Random UART Frames", 3);
            scoreboard.reset();

            @(negedge clk);
            en = 1'b1;

            repeat (4) @(negedge clk);

            test_random_frames(100);

            if (scoreboard.error_count != 0)
                $fatal(1, "Random UART test failed");

            t.test_case_end();
        end


        // --------------------------------------------------------
        // Test 4: False Starts
        // --------------------------------------------------------

        if (t.n == 0 || t.n == 4) begin

            en = 1'b0;
            t.test_case_begin("False Start test", 4);
            $display("");
            scoreboard.reset();

            @(negedge clk);
            en = 1'b1;

            repeat (4) @(negedge clk);

            test_false_starts();

            if (scoreboard.error_count != 0)
                $fatal(1, "False start test failed");

            t.test_case_end();
        end


        // --------------------------------------------------------
        // Test 5: Disable during reception
        // --------------------------------------------------------

        if (t.n == 0 || t.n == 5) begin

            en = 1'b0;
            t.test_case_begin("Disable During Reception", 5);
            scoreboard.reset();

            @(negedge clk);
            en = 1'b1;

            repeat (4) @(negedge clk);

            test_disable_mid_frame();

            if (scoreboard.error_count != 0 ||
                scoreboard.pass_count != 1)
                $fatal(1, "UART RX disable test failed");

            t.test_case_end();
        end


        // --------------------------------------------------------
        // Test 6: Reset during reception
        // --------------------------------------------------------

        if (t.n == 0 || t.n == 6) begin

            en = 1'b0;
            t.test_case_begin("Reset During Reception", 6);

            scoreboard.reset();

            @(negedge clk);
            en = 1'b1;

            repeat (4) @(negedge clk);

            test_reset_mid_frame();

            // Two completed frames:
            // 1. Before reset
            // 2. Recovery after reset
            if (scoreboard.error_count != 0 ||
                scoreboard.pass_count != 2)
                $fatal(1, "UART RX reset test failed");

            t.test_case_end();
        end



        // --------------------------------------------------------
        // Test 7: Back-to-back UART frames
        // --------------------------------------------------------

        if (t.n == 0 || t.n == 7) begin

            en = 1'b0;

            t.test_case_begin("Back-to-Back UART Frames", 7);
            $display("");

            scoreboard.reset();

            @(negedge clk);
            en = 1'b1;

            repeat (4) @(negedge clk);

            test_back_to_back_frames();

            // Exactly two correctly checked frames expected
            if (scoreboard.error_count != 0 ||
                scoreboard.pass_count != 2)
                $fatal(1, "UART RX back-to-back test failed");

            t.test_case_end();

        end

        if (t.n < 0 || t.n > 7)
            $fatal(1, "Unknown UART RX test case: %0d", t.n);

        t.test_suite_end();
        t.test_bench_end();
    end


endmodule
