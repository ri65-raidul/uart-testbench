import uart_transmitter_verif_pkg::*;

class uart_transmitter_driver;

    virtual uart_tx_if       vif;
    mailbox #(uart_tx_trans) drv_mbx;
    event                    drv_done;

    task run();
        $display ("T=%0t [Driver] starting ...", $time);
        
        // Reset values
        vif.tx_val <= 1'b0;
        vif.tx_data <= '0;

        // Ensure the DUT has a reset before it starts sampling
        wait (vif.rst);
        wait (!vif.rst);

        @(posedge vif.clk);

        forever begin

            // Getting the uart transaction from the test top
            uart_tx_trans transaction;
            drv_mbx.get(transaction);

            transaction.print("Driver");

            // delay between transfers
            repeat (transaction.delay) begin
                @(posedge vif.clk);
            end

            // Sending the values to the virtual interface
            vif.tx_data <= transaction.data;
            vif.tx_val  <= 1'b1;

            // Ensure tx_rdy is high when the byte is offered
            do @(posedge vif.clk); while (!vif.tx_rdy);

            // If tx_val becomes 0, we know transmission is complete
            vif.tx_val <= 1'b0;
            -> drv_done;
        end
    endtask

endclass