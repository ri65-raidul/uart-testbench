import uart_transmitter_verif_pkg::*;

class uart_transmitter_scoreboard;

    mailbox #(uart_tx_trans) scb_mbx;
    mailbox #(uart_tx_trans) exp_mbx;
    int unsigned             correct;
    int unsigned             incorrect;

    task run();

        uart_tx_trans trans_actual;
        uart_tx_trans trans_expected;

        forever begin
            // Getting the actual output from the monitor
            scb_mbx.get(trans_actual);

            // Getting the expected output from the model
            if (!exp_mbx.try_get(trans_expected)) begin
                $error("T=%0t [Scoreboard] unexpected frame on tx: 0x%0h",
                $time, trans_actual.data);
                incorrect++; 
                continue;
            end

            if (trans_actual.data === trans_expected.data) begin
                correct++;
            end
            else begin
                incorrect++;
                $error("T=%0t [Scoreboard] mismatch: expected 0x%0h, got 0x%0h",
                       $time, trans_expected.data, trans_actual.data);
            end
        end

    endtask

    function void report();
        if (exp_mbx.num() != 0) begin
            $error("[Scoreboard] %0d byte(s) accepted but never transmitted",
                   exp_mbx.num());
            incorrect += exp_mbx.num();
        end
        $display("[Scoreboard] correct=%0d incorrect=%0d", correct, incorrect);
    endfunction

endclass