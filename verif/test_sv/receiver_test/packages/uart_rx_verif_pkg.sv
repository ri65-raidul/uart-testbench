package uart_rx_verif_pkg;

    parameter int DATA_W = 8;

    typedef logic [DATA_W-1:0] uart_rx_data_t;

    typedef struct packed {
        uart_rx_data_t  data;
        logic           frame_err;
    } uart_rx_result_t;

    class uart_rx_transaction;
        rand    uart_rx_data_t      data;
        rand    bit                 valid_stop;
    endclass

endpackage
