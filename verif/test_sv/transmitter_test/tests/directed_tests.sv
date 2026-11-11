import uart_transmitter_verif_pkg::*;

class uart_transmitter_directed_tests;
    virtual uart_tx_if vif;
    mailbox #(uart_tx_trans) drv_mbx;
    uart_transmitter_scoreboard scb;

    int unsigned sent;
    int unsigned check_errors;

    // ----------------- Helpers ------------------
    
    // Queue one byte for the driver
    task send_byte(bit [7:0] data, int delay = 0);
        uart_tx_trans trans = new();
        trans.data = data;
        trans.delay = delay;
        drv_mbx.put(trans);
        sent++;
    endtask

    // Wait until every byte sent so far has been checked by the scoreboard
    task drain();
        wait(scb.correct + scb.incorrect == sent);
        repeat (10) @(posedge vif.clk); //small idle gap
    endtask

    // ----------------- Tests ------------------
    // Simple test - to check if the testbench is working
    task test_single_byte();
        $display("[Test] single byte");
        send_byte(8'hA5);
        drain();
    endtask

    // tx_data patterns: all 1s, all 0s, alternating, half and half
    task test_data_patterns();
        $display("[Test] data patterns");
        send_byte('1);                                   // all 1s       (FF)
        send_byte('0);                                   // all 0s       (00)
        send_byte({DATA_W/2{2'b01}});                    // alternating  (55)
        send_byte({DATA_W/2{2'b10}});                    // alternating  (AA)
        send_byte({{DATA_W/2{1'b0}}, {DATA_W/2{1'b1}}}); // half / half  (0F)
        send_byte({{DATA_W/2{1'b1}}, {DATA_W/2{1'b0}}}); // half / half  (F0)
        drain();
    endtask

    task test_baud_rates();
        int unsigned default_div = vif.tick_div;
 
        $display("[Test] baud rates");
        foreach (baud_rates[i]) begin
            set_baud(baud_rates[i]);
            send_byte(8'hA5);
            send_byte(8'h3C);
            drain();
        end
 
        vif.tick_div = default_div;
        $display("T=%0t [Test] tick_div restored to %0d", $time, default_div);
    endtask

    // ==========================================================
    // Run all / report
    // ==========================================================
 
    task run_all();
        test_single_byte();
        test_data_patterns();
        test_baud_rates();
    endtask

    function void report();
        $display("[Test] directed checks failed = %0d", check_errors);
    endfunction

endclass
