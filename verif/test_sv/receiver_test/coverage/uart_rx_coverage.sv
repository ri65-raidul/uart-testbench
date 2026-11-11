module uart_rx_coverage
    import uart_rx_verif_pkg::*;
(
    input   logic   clk,
    input   logic   reset,

    // DUT outputs
    input   uart_rx_data_t  data,
    input   logic           rx_val,
    input   logic           frame_err
);

    covergroup uart_rx_cg @(negedge clk);

        // Received data patterns (8 bit UART)
        data_cp : coverpoint data iff (!reset && rx_val) {
            bins zeros          = {8'h00};
            bins ones           = {8'hFF};
            bins alternating    = {8'h55, 8'hAA};
            bins other          = {
                [8'h01 : 8'h54],
                [8'h56 : 8'hA9],
                [8'hAB : 8'hFE]
            };
        }

        // Framing error detection
        frame_err_cp    : coverpoint frame_err iff (!reset && rx_val) {
            bins frame_valid    = {1'b0};
            bins frame_error    = {1'b1};
        }

        data_frame_cross : cross data_cp, frame_err_cp
            iff (!reset && rx_val);

    endgroup

    uart_rx_cg coverage = new();

endmodule
