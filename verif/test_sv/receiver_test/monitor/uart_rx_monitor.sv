module uart_rx_monitor
    import uart_rx_verif_pkg::*;
(
    input   logic           clk,
    input   uart_rx_data_t  data,
    input   logic           rx_val,
    input   logic           frame_err
);

    task automatic receive(output uart_rx_result_t actual);

        // Wait until the receiver produces a valid byte
        do begin
            @(negedge clk);
        end while (rx_val !== 1'b1);

        // Capture DUT output
        actual.data         = data;
        actual.frame_err    = frame_err;

    endtask

endmodule
