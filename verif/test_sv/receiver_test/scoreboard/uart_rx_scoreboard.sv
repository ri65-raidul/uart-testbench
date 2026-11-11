module uart_rx_scoreboard;
    import uart_rx_verif_pkg::*;

    int pass_count  = 0;
    int error_count = 0;

    // --------------------------------------------------------
    // Reset scoreboard
    // --------------------------------------------------------

    function void reset();
        pass_count  = 0;
        error_count = 0;
    endfunction


    // --------------------------------------------------------
    // Compare results
    // --------------------------------------------------------

    task automatic check(
        input   uart_rx_result_t    expected,
        input   uart_rx_result_t    actual
    );

        bit match;

        match = 1'b1;

        // Check received data
        if (actual.data !== expected.data) begin
            error_count++;
            match = 1'b0;

            $error(
                "UART RX data mismatch: expected=%h, actual=%h",
                expected.data,
                actual.data
            );
        end

        // Check framing error
        if (actual.frame_err !== expected.frame_err) begin
            error_count++;
            match = 1'b0;

            $error(
                "UART RX frame error mismatch: expected=%b, actual=%b",
                expected.frame_err,
                actual.frame_err
            );
        end

        // Record successful transaction
        if (match) begin
            pass_count++;

            $display(
                "UART RX PASS: data=%h, frame_err=%b",
                actual.data,
                actual.frame_err
            );
        end

    endtask

endmodule
