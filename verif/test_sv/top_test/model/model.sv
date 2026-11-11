/*
==========================================================================
model.sv
==========================================================================
*/

import uart_verif_pkg::*;

class model;

    mailbox #(uart_req)   drv2model_req;    // from bus driver
    mailbox #(uart_frame) drv2model_frame;  // from rx driver
    mailbox #(uart_resp)  model2scb_resp;   // expected responses
    mailbox #(uart_frame) model2scb_frame;  // expected tx frames

    coverage cov;

    localparam int Q_SIZE = 8;
    logic frame_error_flag = 1'b0; // STATUS[5]
    logic rx_overrun_flag = 1'b0;  // STATUS[6]

    // Mirrored DUT state
    logic        uart_en  = 1'b0;
    logic [15:0] baud_div = '0;
    logic [7:0]  rx_q[$];

    // Utility bit for tx disable test (prevent resp)
    bit predict_tx_frames = 1'b1;   // = 0 in tx disable test

    function new();
        cov = new();
    endfunction

    task run();
        fork
            handle_rx();
            handle_reqs();
        join_none
    endtask

    // Bytes arriving on rx go into the RX queue
    task handle_rx();
        forever begin
            uart_frame frame;
            drv2model_frame.get(frame);
            cov.sample_frame(frame, rx_q.size());
            if      (!uart_en)               ;                          // ignored
            else if (frame.frame_err)        frame_error_flag = 1'b1;   // dropped
            else if (rx_q.size() >= Q_SIZE)  rx_overrun_flag  = 1'b1;   // dropped
            else                             rx_q.push_back(frame.data);
        end
    endtask

    // Every request gets one expected response
    task handle_reqs();
        forever begin
            uart_req     req;
            uart_resp    exp = new();
            logic        op;
            logic [1:0]  sel;
            logic [31:0] rdata = '0;

            drv2model_req.get(req);
            op  = req.msg[78];
            sel = req.msg[39:38];   // addr[3:2]

            cov.sample_req(req, rx_q.size(), uart_en);

            // Read data (regs.sv returns this for writes too)
            case (sel)
                2'b01: if (rx_q.size()) rdata[7:0] = rx_q[0];   // RXDATA
                2'b10: begin
                    rdata[0] = (rx_q.size() > 0);
                    rdata[1] = (rx_q.size() >= Q_SIZE);
                    rdata[5] = frame_error_flag;
                    rdata[6] = rx_overrun_flag;
                end
                2'b11: begin                                    // CTRL
                    rdata[0]     = uart_en;
                    rdata[31:16] = baud_div;
                end
                default: ;   // TXDATA: 0
            endcase

            // Side effects
            if (op && sel == 2'b00 && predict_tx_frames) begin   // TXDATA write
                uart_frame tx_frame = new();
                tx_frame.data = req.msg[7:0];
                model2scb_frame.put(tx_frame);
            end
            if (op && sel == 2'b11) begin                        // CTRL write
                baud_div = req.msg[31:16];
                uart_en  = req.msg[0] && (baud_div != '0);
            end
            if (op && sel == 2'b01 && rx_q.size())             // RXDATA write pops (read peeks)
                void'(rx_q.pop_front());

            if (op && sel == 2'b10) begin
                if (req.msg[5]) frame_error_flag = 1'b0;
                if (req.msg[6]) rx_overrun_flag  = 1'b0;
            end

            // Echo bits 78:32, add read data
            exp.msg = {req.msg[78:32], rdata};
            model2scb_resp.put(exp);
        end
    endtask

endclass