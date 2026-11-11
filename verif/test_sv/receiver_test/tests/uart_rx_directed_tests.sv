//===========================================================
// UART RX Directed Tests
//===========================================================

// Number of cycles to monitor rx_val for false starts
// (8 data + 1 start + 1 stop + 1 margin bits)
// (* 16 ticks per UART bit * 8 clock cycles per tick)
localparam int unsigned FRAME_TIMEOUT_CYCLES =
    (DATA_W + 3) * FULL * TICK_DIV;

// --------------------------------------------------------
// Test 1: Valid UART Frames
// --------------------------------------------------------

task automatic test_valid_frames();

    uart_rx_transaction transaction;
    transaction = new();
    
    // Valid stop bit
    transaction.valid_stop = 1'b1;

    // All zeros
    transaction.data = 8'h00;
    run_frame(transaction);

    // All ones
    transaction.data = 8'hFF;
    run_frame(transaction);

    // Alternating bits
    transaction.data = 8'h55;
    run_frame(transaction);

    transaction.data = 8'hAA;
    run_frame(transaction);

    // Mixed data
    transaction.data = 8'hAB;
    run_frame(transaction);

endtask


// --------------------------------------------------------
// Test 2: Framing errors
// --------------------------------------------------------

task automatic test_framing_errors();

    uart_rx_transaction transaction;
    transaction = new();
    
    // Non-valid stop bit
    transaction.valid_stop = 1'b0;

    // All zeros
    transaction.data = 8'h00;
    run_frame(transaction);

    // All ones
    transaction.data = 8'hFF;
    run_frame(transaction);

    // Alternating bits
    transaction.data = 8'h55;
    run_frame(transaction);

    transaction.data = 8'hAA;
    run_frame(transaction);

    // Mixed data
    transaction.data = 8'hAB;
    run_frame(transaction);

endtask


// --------------------------------------------------------
// Test 4: False starts
// --------------------------------------------------------

task automatic test_false_starts();

    fork
        // Generate false start stimulus
        begin
            driver.send_false_start();
        end

        // Ensure no frame is received
        begin
            repeat (FRAME_TIMEOUT_CYCLES) begin
                @(negedge clk);

                if (rx_val !== 1'b0) begin
                    $fatal(1, "UART RX false start");
                end
            end
        end
    join

    $display("UART RX PASS: false start rejected");

endtask


// --------------------------------------------------------
// Test 5: Disable during reception
// --------------------------------------------------------

task automatic test_disable_mid_frame();

    uart_rx_transaction transaction;
    transaction = new();

    transaction.data        = 8'hA5;
    transaction.valid_stop  = 1'b1;

    // Begin with receiver enabled
    en = 1'b1;

    fork
        // Transmit a complete frame
        begin
            driver.send_frame(transaction);
            driver.wait_ticks(FULL);
        end

        // Disable during DATA state
        begin
            // Wait until START bit begins
            @(negedge rx);

            // Wait 3 bit periods
            driver.wait_ticks(3 * FULL);

            // Abort
            en = 1'b0;
        end

        // Checker: aborted frame must not complete
        begin
            repeat (FRAME_TIMEOUT_CYCLES) begin
                @(negedge clk);

                if (rx_val !== 1'b0) begin
                    $fatal(1, "UART RX produced rx_val during aborted frame");
                end
            end
        end
    join

    $display("UART RX PASS: frame aborted when disabled");

    // Re-enable receiver
    @(negedge clk);
    en = 1'b1;

    driver.wait_ticks(FULL);

    // Confirm receiver can still process new frame
    transaction.data = 8'h55;
    run_frame(transaction);

    $display("UART RX PASS: receiver recovered after disable");

endtask


// --------------------------------------------------------
// Test 6: Reset during reception
// --------------------------------------------------------

task automatic test_reset_mid_frame();

    uart_rx_transaction transaction;
    transaction = new();

    transaction.valid_stop = 1'b1;

    // receive a valid nonzero byte to test reset
    transaction.data = 8'hA5;
    run_frame(transaction);

    // interrupt second frame
    transaction.data = 8'h3C;

    fork
        // Stimulus and reset control
        begin
            driver.send_partial_frame(transaction, 3);

            // Assert reset while receiving data
            reset_inject = 1'b1;

            // Give synchronous reset time to propagate
            repeat (4) @(negedge clk);

            // Verify reset cleared outputs
            if (data !== '0 ||
                rx_val !== 1'b0 ||
                frame_err !== 1'b0) begin
                $fatal(1, "UART RX outputs not cleared by reset");
            end

            reset_inject = 1'b0;
        end

        // Check that the interrupted frame
        // never produces a completion pulse
        begin
            repeat (FRAME_TIMEOUT_CYCLES) begin
                @(negedge clk);

                if (rx_val !== 1'b0) begin
                    $fatal(1,
                        "UART RX produced rx_val for reset frame");
                end
            end
        end
    join

    $display("UART RX PASS: reset aborted partial frame");

    driver.wait_ticks(FULL);

    // Confirm receiver can still process new frame
    transaction.data = 8'h55;
    run_frame(transaction);

    $display("UART RX PASS: receiver recovered after reset");

endtask



// --------------------------------------------------------
// Test 7: Back-to-back UART frames
// --------------------------------------------------------

task automatic test_back_to_back_frames();

    uart_rx_transaction first;
    uart_rx_transaction second;

    uart_rx_result_t expected_first;
    uart_rx_result_t expected_second;

    uart_rx_result_t actual_first;
    uart_rx_result_t actual_second;

    first  = new();
    second = new();

    // First frame
    first.data       = 8'hA5;
    first.valid_stop = 1'b1;

    // Second frame
    second.data       = 8'h3C;
    second.valid_stop = 1'b1;

    // Predict both expected results
    expected_first  = model.predict(first);
    expected_second = model.predict(second);

    fork

        // transmit two consecutive frames
        begin
            driver.send_back_to_back_frames(first, second);
        end

        // capture two received frames
        begin
            monitor.receive(actual_first);
            monitor.receive(actual_second);
        end

    join

    // Check both results
    scoreboard.check(expected_first, actual_first);
    scoreboard.check(expected_second, actual_second);

    $display("UART RX PASS: back-to-back frames received");

    // Extra idle time after both frames
    driver.wait_ticks(FULL);

endtask