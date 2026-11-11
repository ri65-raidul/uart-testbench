import uart_transmitter_verif_pkg::*;

class uart_transmitter_monitor;

    virtual uart_tx_if vif;
    mailbox #(uart_tx_trans) scb_mbx;
    mailbox #(uart_tx_trans) model_mbx;
    int unsigned             ticks_per_bit = 16;

    // Task to wait a certain number of ticks
    task wait_ticks(int n);
        repeat(n) begin
            @(posedge vif.clk iff vif.tick);
        end
    endtask

    task run();
        $display("T=%0t [Monitor] starting ...", $time);

        // Ensuring the DUT goes through a reset
        wait (!vif.rst);

        // Starting both the input and output threads
        fork
            monitor_input();
            monitor_output();
        join_none

    endtask

    // This thread reads the input data to the DUT and
    // sends it to the functional model
    task monitor_input();
        forever begin
            @(posedge vif.clk);
            if (vif.tx_val && vif.tx_rdy) begin
                uart_tx_trans trans = new();
                trans.data = vif.tx_data;
                trans.print("Monitor-In");
                model_mbx.put(trans);
            end
        end

    endtask

    // This thread reads the output data from the DUT and
    // compiles the whole byte and sends it to the scoreboard
    task monitor_output();
        forever begin

            uart_tx_trans trans = new();
            
            // start bit
            @(negedge vif.tx);
            wait_ticks(ticks_per_bit/2);
            if (vif.tx != 1'b0) begin
                $error("T=%0t [Monitor] start bit not low at mid-bit", $time);
                continue; // false start: resync on next falling edge
            end

            // data bits
            for (int i = 0; i < $bits(trans.data); i++) begin
                wait_ticks(ticks_per_bit);
                trans.data[i] = vif.tx;
            end

            // stop bit
            wait_ticks(ticks_per_bit);
            if (vif.tx != 1'b1)
                $error("T=%0t [Monitor] framing error: stop bit is %b", $time, vif.tx);

            trans.print("Monitor-out");
            scb_mbx.put(trans);
        end
    endtask

endclass