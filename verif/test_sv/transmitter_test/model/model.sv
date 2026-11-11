import uart_transmitter_verif_pkg::*;

class uart_transmitter_model;

    mailbox #(uart_tx_trans) model_mbx;
    mailbox #(uart_tx_trans) exp_mbx;

    task run();
        uart_tx_trans trans_in;
        uart_tx_trans trans_exp;

        forever begin

            // If there is no input, the thread goes to sleep
            model_mbx.get(trans_in);

            // Predict the expected output
            trans_exp = new();
            trans_exp.data = trans_in.data;

            trans_exp.print("Model");
            exp_mbx.put(trans_exp);
        end
    endtask

endclass