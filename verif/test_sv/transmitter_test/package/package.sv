package uart_transmitter_verif_pkg;

    localparam int DATA_W = 8;

    typedef logic [DATA_W-1:0] tx_data_t;

    class uart_tx_trans;
        rand tx_data_t    data;
        rand int unsigned delay;

        constraint c_delay { delay inside {[0:10]}; }

        function void print(string tag = "");
            $display("T=%0t [%s] data=0x%0h delay=%0d", $time, tag, data, delay);
        endfunction
    endclass

endpackage