//===========================================================
// UART RX Random Tests
//===========================================================

// --------------------------------------------------------
// Test 3: Random UART Frames
// --------------------------------------------------------

task automatic test_random_frames(
    input int unsigned num_frames = 100
);

    uart_rx_transaction transaction;
    transaction = new();

    repeat (num_frames) begin
        assert (transaction.randomize())
            else $fatal(1, " UART RX transaction randomization failed");
        run_frame(transaction);
    end

endtask