module uart_rx_driver
    import uart_rx_verif_pkg::*;
(
    input   logic   clk,
    input   logic   tick,
    output  logic   rx
);

    localparam int FULL = 16;

    // UART line idle on high
    initial begin
        rx = 1'b1;
    end

    // --------------------------------------------------------
    // Wait for a specified number of oversampling ticks
    // --------------------------------------------------------

    task automatic wait_ticks(input int unsigned num_ticks);

        repeat (num_ticks) begin
            do begin
                @(posedge clk);
            end while (tick !== 1'b1);
        end

        @(negedge clk);

    endtask


    // --------------------------------------------------------
    // Drive data to dut
    // --------------------------------------------------------

    task automatic send_frame(input uart_rx_transaction transaction);

        if (transaction == null)
            $fatal(1, "UART RX driver: null transaction");

        // Start on a falling clock edge
        @(negedge clk);

        // Start bit
        rx = 1'b0;
        wait_ticks(FULL);

        // Data bits (LSB first)
        for (int i = 0; i < DATA_W; i++) begin
            rx = transaction.data[i];
            wait_ticks(FULL);
        end

        // Stop bit
        rx = transaction.valid_stop;
        wait_ticks(FULL);

        // Return to idle
        rx = 1'b1;

    endtask


    // --------------------------------------------------------
    // Send false start to dut
    // --------------------------------------------------------

    task automatic send_false_start();
        
        // Begin from IDLE
        @(negedge clk);
        rx   = 1'b1;
        wait_ticks(2);

        // Send a short pulse
        rx   = 1'b0;
        wait_ticks(2);

        // Go back to IDLE
        rx   = 1'b1;
    endtask


    // --------------------------------------------------------
    // Send partial frame
    // --------------------------------------------------------

    task automatic send_partial_frame(
        input uart_rx_transaction   transaction,
        input int unsigned          num_data_bits
    );

        if (transaction == null)
            $fatal(1, "UART RX null transaction");

        if (num_data_bits == 0 || num_data_bits >= DATA_W)
            $fatal(1, "Invalid partial frame length");

        // Start on a falling clock edge
        @(negedge clk);

        // Start bit
        rx = 1'b0;
        wait_ticks(FULL);

        // Transmit only part of the data
        for (int i = 0; i < num_data_bits; i++) begin
            rx = transaction.data[i];
            wait_ticks(16);
        end

        // Return to IDLE
        rx = 1'b1;
    endtask


    // --------------------------------------------------------
    // Send two back-to-back UART frames
    // --------------------------------------------------------

    task automatic send_back_to_back_frames(
        input uart_rx_transaction first,
        input uart_rx_transaction second
    );

        uart_rx_transaction transaction;

        if (first == null || second == null)
            $fatal(1, "UART RX null transaction");

        @(negedge clk);

        for (int frame = 0; frame < 2; frame++) begin

            // Select current transaction
            if (frame == 0)
                transaction = first;
            else
                transaction = second;

            // Start bit
            rx = 1'b0;
            wait_ticks(16);

            // Data bits (LSB first)
            for (int i = 0; i < DATA_W; i++) begin
                rx = transaction.data[i];
                wait_ticks(16);
            end

            // Stop bit
            rx = transaction.valid_stop;
            wait_ticks(16);
        end

        // Return to idle after both frames
        rx = 1'b1;
    endtask

endmodule
