import uart_verif_pkg::*;

class monitor_tx;

    virtual uart_if vif;
    mailbox #(uart_frame) mon2scb_mbx; // monitor to scoreboard

    logic [15:0] baud_div;
    logic [32:0] clks_per_bit;
    logic [7:0]  tx_gathered;
    logic        frame_err;

    int TICKS_PER_BIT = 16;

    function new(virtual uart_if vif_i);
        vif = vif_i;
    endfunction

    task run();
        $display("T=%0t [Monitor tx] starting ...", $time);
        
        // Ensuring the DUT goes through a reset
        wait (!vif.rst);
        
        fork
            track_baud_div();
            sample_frame();
        join_none

    endtask

    task track_baud_div();
        forever begin
            @(posedge vif.clk) begin
            if (vif.wrapper_recv_val && vif.wrapper_recv_rdy && // handshake
                vif.wrapper_recv_msg[78] &&                     // write
                vif.wrapper_recv_msg[39:38] == 2'b11) begin     // CTRL
                baud_div = vif.wrapper_recv_msg[31:16];
                clks_per_bit = baud_div * TICKS_PER_BIT;
                $display("T=%0t [Monitor TX] clks_per_bit=%0d",
                         $time, clks_per_bit);
            end
            end
        end
    endtask

    // Task to sample each frame
    task sample_frame();

        forever begin
            uart_frame trans = new();

            // start bit
            @(negedge vif.tx);
            repeat (clks_per_bit/2) begin
                @(posedge vif.clk);
            end

            // gather the byte
            for (int i = 0; i < 8; i++) begin
                repeat(clks_per_bit) begin
                    @(posedge vif.clk);
                end
                tx_gathered[i] = vif.tx;
            end

            // stop bit
            repeat(clks_per_bit) begin
                @(posedge vif.clk);
            end
            frame_err = (vif.tx !== 1'b1);

            // Putting the data in the mailbox
            trans.data = tx_gathered;
            trans.frame_err = frame_err;
            mon2scb_mbx.put(trans);
        end

    endtask


endclass