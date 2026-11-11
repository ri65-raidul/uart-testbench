import uart_verif_pkg::*;

class monitor_resp;

    virtual uart_if vif;
    mailbox #(uart_resp) mon2scb_mbx; // monitor to scoreboard

    function new(virtual uart_if vif_i);
        vif = vif_i;
    endfunction

    task run();
        $display("T=%0t [Monitor Resp] starting ...", $time);
        
        // Ensuring the DUT goes through a reset
        wait (!vif.rst);

        forever begin
            @(posedge vif.clk);

            // Ensuring val/rdy protocol is maintained
            if (vif.wrapper_send_val && vif.wrapper_send_rdy) begin

                // Creating a new transaction for the response
                uart_resp trans = new();
                trans.msg = vif.wrapper_send_msg;
                trans.print("Monitor-In");

                // Putting the transaction in the mailbox
                mon2scb_mbx.put(trans);
            end
        end
    endtask

endclass