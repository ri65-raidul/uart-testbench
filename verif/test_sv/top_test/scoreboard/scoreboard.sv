/*
==========================================================================
scoreboard.sv
==========================================================================
*/
import uart_verif_pkg::*;

class scoreboard;

    // From model (expected)
    mailbox #(uart_resp)  model2scb_resp;
    mailbox #(uart_frame) model2scb_frame;

    // From monitors (actual)
    mailbox #(uart_resp)  mon2scb_resp;    // monitor_resp
    mailbox #(uart_frame) mon2scb_frame;   // monitor_tx

    int resp_pass = 0, resp_fail = 0;
    int tx_pass   = 0, tx_fail   = 0;

    logic [31:0] last_status_rdata = '0;
    int unsigned status_read_count = 0;

    task run();
        fork
            check_resp();
            check_tx();
        join_none
    endtask

    // ------------------------------------------------------------------
    // send_msg vs expected response
    // ------------------------------------------------------------------
    task check_resp();
        forever begin
            uart_resp act, exp;
            bit       ok;

            mon2scb_resp.get(act);
            model2scb_resp.get(exp);

            if (exp.msg[39:38] == 2'b10) begin
                ok = (act.msg[78:32] === exp.msg[78:32]);

                if (!exp.msg[78]) begin // save status data on status read
                    last_status_rdata = act.msg[31:0];
                    status_read_count++;
                end
            end
            else
                ok = (act.msg === exp.msg);

            if (ok) begin
                resp_pass++;
            end else begin
                resp_fail++;
                $error("T=%0t [Scoreboard] RESP mismatch: exp=0x%0h act=0x%0h",
                       $time, exp.msg, act.msg);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // tx_collected vs expected tx frame
    // ------------------------------------------------------------------
    task check_tx();
        forever begin
            uart_frame act, exp;

            mon2scb_frame.get(act);
            model2scb_frame.get(exp);

            if (act.data === exp.data && act.frame_err == 1'b0) begin
                tx_pass++;
            end else begin
                tx_fail++;
                $error("T=%0t [Scoreboard] TX mismatch: exp=0x%02h act=0x%02h frame_err=%0b",
                       $time, exp.data, act.data, act.frame_err);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Call at the end of the test
    // ------------------------------------------------------------------
    function void report();
        int resp_left = model2scb_resp.num();
        int tx_left   = model2scb_frame.num();

        $display("==================================================");
        $display("[Scoreboard] RESP: %0d passed, %0d failed", resp_pass, resp_fail);
        $display("[Scoreboard] TX  : %0d passed, %0d failed", tx_pass,   tx_fail);

        // Expected items that never showed up are failures too
        if (resp_left) $error("[Scoreboard] %0d expected responses never arrived", resp_left);
        if (tx_left)   $error("[Scoreboard] %0d expected tx frames never arrived", tx_left);

        if (resp_fail || tx_fail || resp_left || tx_left)
            $display("[Scoreboard] TEST FAILED");
        else
            $display("[Scoreboard] TEST PASSED");
        $display("==================================================");
    endfunction

endclass
