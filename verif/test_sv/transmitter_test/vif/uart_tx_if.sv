interface uart_tx_if
    import uart_transmitter_verif_pkg::*;
(
    input logic clk,
    input logic rst
);

    logic              tick;

    logic [DATA_W-1:0] tx_data;
    logic              tx_val;

    logic              tx_rdy;
    logic              tx;
    logic              tx_busy;

    int unsigned       tick_div = 12;

endinterface