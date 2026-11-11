import uart_verif_pkg::*;

class driver_req;

    virtual uart_if vif;

    mailbox #(uart_req) drv2model_req;

    function new(virtual uart_if vif_i);
        vif = vif_i;
    endfunction

    task init();
        vif.wrapper_recv_val = 1'b0;
        vif.wrapper_recv_msg = '0;
        vif.wrapper_send_rdy = 1'b1;
    endtask

    task send(input uart_req req);

        uart_req accepted_req;

        if (req == null)
            $fatal(1, "[driver_req] send() received a null request");
    
        wait(vif.rst === 1'b0);
        @(negedge vif.clk);

        vif.wrapper_recv_msg = req.msg; // prepare msg
        vif.wrapper_recv_val = 1'b1;    // present msg
    
        do begin
            @(posedge vif.clk);  // wait until UART accepts req
        end while (vif.wrapper_recv_rdy !== 1'b1);

        accepted_req = new();
        accepted_req.msg = req.msg;
        drv2model_req.put(accepted_req);

        // request has now been accepted
        @(negedge vif.clk);
        vif.wrapper_recv_val = 1'b0;    // no longer presenting a msg
        vif.wrapper_recv_msg = '0;      // clear out msg
    endtask

    // Optional task to stall/continue DUT's resp channel
    task set_resp_ready(input bit ready);
        @(negedge vif.clk);
        vif.wrapper_send_rdy = ready;
    endtask

endclass
