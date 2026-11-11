module uart_baud_gen_test_top
();

    localparam int unsigned DIV_W = 16;

    // --------------------------------------------------------
    // DUT signals
    // --------------------------------------------------------

    logic               clk;
    logic               reset_inject;
    logic               utility_reset;
    logic               reset;
    logic               en;
    logic [DIV_W-1:0]   div;
    logic               tick;


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
    // DUT
    // --------------------------------------------------------

    uart_BaudRateGenerator #(
        .DIV_W      (DIV_W)
    ) dut (
        .clk        (clk),
        .reset      (reset),
        .en         (en),
        .div        (div),
        .tick       (tick)
    );


    // --------------------------------------------------------
    // Test 1: Verify divisor timing
    // --------------------------------------------------------

    task automatic test_divisor(
        input int unsigned divisor,
        input int unsigned num_ticks
    );

        logic expected_tick;

        // Initialize gen
        @(negedge clk);
        reset_inject = 1'b1;
        en    = 1'b0;
        div   = DIV_W'(divisor);

        repeat (2) @(negedge clk);

        if (tick !== 1'b0)
            $fatal(1, "Tick asserted during reset");

        // Enable gen
        reset_inject = 1'b0;
        en    = 1'b1;

        // Check tick on each clock cycle
        for (int cycle = 1;
            cycle <= divisor * num_ticks;
            cycle++) begin

            @(negedge clk);

            expected_tick = (((cycle - 1) % divisor) == 0);

            if (tick !== expected_tick) begin
                $fatal(1,
                    "div=%0d cycle=%0d expected=%b actual=%b",
                    divisor, cycle, expected_tick, tick);
            end
        end

        $display("PASS: div=%0d, ticks=%0d",
                divisor, num_ticks);

    endtask


    // --------------------------------------------------------
    // Test 2: Reset or disable during counting
    // --------------------------------------------------------

    task automatic test_restart(input bit use_reset);

        @(negedge clk);
        reset_inject = 1'b1;
        en    = 1'b0;
        div   = 8;

        repeat (2) @(negedge clk);

        reset_inject = 1'b0;
        en    = 1'b1;

        // Count partway toward first tick
        repeat (3) @(negedge clk);

        if (tick !== 1'b0)
            $fatal(1, "Unexpected early tick");

        // Interrupt by either reset or disable
        if (use_reset)
            reset_inject = 1'b1;
        else
            en = 1'b0;

        repeat (2) begin
            @(negedge clk);
            if (tick !== 1'b0)
                $fatal(1, "Tick during reset/disable");
        end

        // Restart gen
        reset_inject = 1'b0;
        en    = 1'b1;

        // First tick should occur after 8 full cycles
        for (int cycle = 1; cycle <= 16; cycle++) begin

            @(negedge clk);

            if (tick !== ((cycle - 1) % 8 == 0))
                $fatal(1,
                    "Incorrect tick after reset/disable");
        end

        if (use_reset)
            $display("PASS: reset during counting");
        else
            $display("PASS: disable during counting");

    endtask


initial begin

    reset_inject = 1'b1;
    en           = 1'b0;
    div          = 8;

    t.test_bench_begin();
    t.test_suite_begin("UART Baud Rate Generator Verification");

    // --------------------------------------------------------
    // Test 1: Divisor timing
    // --------------------------------------------------------

    if (t.n == 0 || t.n == 1) begin
        t.test_case_begin("Divisor Timing", 1);
        $display("");

        test_divisor(1, 5);
        test_divisor(2, 5);
        test_divisor(7, 5);
        test_divisor(8, 5);
        test_divisor(16, 5);
        test_divisor(65, 5);

        t.test_case_end();
    end

    // --------------------------------------------------------
    // Test 2: Reset and enable
    // --------------------------------------------------------

    if (t.n == 0 || t.n == 2) begin
        t.test_case_begin("Reset and Enable", 2);
        $display("");

        test_restart(1'b0);
        test_restart(1'b1);

        t.test_case_end();
    end

    if (t.n < 0 || t.n > 2)
        $fatal(1, "Unknown baud generator test case: %0d", t.n);

    $display("ALL BAUD RATE GENERATOR TESTS PASSED");

    t.test_suite_end();
    t.test_bench_end();

end


endmodule
