module uart_rx_model
    import uart_rx_verif_pkg::*;
();

    // --------------------------------------------------------
    // Calculate expected results
    // --------------------------------------------------------

    function automatic uart_rx_result_t predict(
        input uart_rx_transaction transaction
    );
        uart_rx_result_t expected;

        // in data = out data
        expected.data = transaction.data;

        // frame_err when stop bit is low
        expected.frame_err = ~transaction.valid_stop;

        return expected;
    endfunction

endmodule
