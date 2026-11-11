/*
==========================================================================
coverage.sv
==========================================================================
*/

import uart_verif_pkg::*;

class coverage;

    // ------------------------------------------------------------------
    // Every request: which registers were read and written
    // ------------------------------------------------------------------
    covergroup cg_req with function sample(logic op, logic [1:0] sel, logic uart_en);

        cp_op : coverpoint op {
            bins read  = {1'b0};
            bins write = {1'b1};
        }

        cp_reg : coverpoint sel {
            bins txdata = {2'b00};
            bins rxdata = {2'b01};
            bins status = {2'b10};
            bins ctrl   = {2'b11};
        }

        cp_en  : coverpoint uart_en {
            bins off = {1'b0};
            bins on  = {1'b1};
        }

        // Every register hit with both a read and a write
        cx_op_reg    : cross cp_op, cp_reg;
        cx_op_reg_en : cross cp_op, cp_reg, cp_en;

    endgroup

    // ------------------------------------------------------------------
    // CTRL writes only
    // ------------------------------------------------------------------
    covergroup cg_ctrl with function sample(logic en, logic [15:0] div);

        cp_ctrl_en : coverpoint en {
            bins disable_ = {1'b0};
            bins enable_  = {1'b1};
        }

        cp_baud_div : coverpoint div {
            // Counter boundaries
            bins zero      = {0};
            bins one       = {1};
            bins max       = {16'hFFFF};

            // Common baud rates (100 MHz, 16x oversampling)
            bins b921600   = {7};
            bins b230400   = {27};
            bins b115200   = {54};
            bins b9600     = {651};

            // Everything else, grouped
            bins div_other = default;
        }

        cx_en_div : cross cp_ctrl_en, cp_baud_div;

    endgroup

    // ------------------------------------------------------------------
    // TXDATA writes only
    // ------------------------------------------------------------------
    covergroup cg_tx with function sample(logic [7:0] data);

        cp_tx_byte : coverpoint data {
            bins zero  = {8'h00};
            bins ones  = {8'hFF};
            bins other = {[8'h01:8'hFE]};
        }

    endgroup

    // ------------------------------------------------------------------
    // STATUS writes only (clear_bits = data[7:5])
    //   [0] = bit 5 frame error, [1] = bit 6 overrun, [2] = bit 7 tx overflow
    // ------------------------------------------------------------------
    covergroup cg_status with function sample(logic [2:0] clear_bits);

        cp_status_clear : coverpoint clear_bits {
            bins none        = {3'b000};
            bins frame_err   = {3'b001};
            bins overrun     = {3'b010};
            bins tx_overflow = {3'b100};
            bins multiple    = {3'b011, 3'b101, 3'b110, 3'b111};
        }

    endgroup

    // ------------------------------------------------------------------
    // RX frames arriving on rx (sampled in handle_rx, before the push)
    // ------------------------------------------------------------------
    covergroup cg_frame with function sample(logic [7:0] data, bit frame_err, int rx_level);

        cp_data : coverpoint data {
            bins zero  = {8'h00};
            bins ones  = {8'hFF};
            bins other = {[8'h01:8'hFE]};
        }

        cp_frame_err : coverpoint frame_err {
            bins good = {1'b0};
            bins bad  = {1'b1};
        }

        cp_level : coverpoint rx_level {
            bins empty   = {0};
            bins partial = {[1:7]};
            bins full    = {8};
        }

        cx_err_level : cross cp_frame_err, cp_level;

    endgroup

    // ------------------------------------------------------------------
    // RXDATA accesses (sampled in handle_reqs, before side effects)
    // ------------------------------------------------------------------
    covergroup cg_rx_access with function sample(logic op, int rx_level);

        cp_rx_op : coverpoint op {
            bins peek = {1'b0};   // read
            bins pop  = {1'b1};   // write
        }

        cp_rx_level : coverpoint rx_level {
            bins empty   = {0};
            bins one     = {1};
            bins partial = {[2:7]};
            bins full    = {8};
        }

        cx_rx_op_level : cross cp_rx_op, cp_rx_level;

    endgroup

    function new();
        cg_req       = new();
        cg_ctrl      = new();
        cg_tx        = new();
        cg_status    = new();
        cg_rx_access = new();
        cg_frame     = new();
    endfunction

    // Call BEFORE the model applies the request's side effects,
    // so rx_level / uart_en are what the DUT saw.
    function void sample_req(uart_req req, int rx_level, bit uart_en);
        logic       op  = req.msg[78];
        logic [1:0] sel = req.msg[39:38];

        cg_req.sample(op, sel, uart_en);

        if (op && sel == 2'b11) cg_ctrl.sample(req.msg[0], req.msg[31:16]);
        if (op && sel == 2'b00) cg_tx.sample(req.msg[7:0]);
        if (op && sel == 2'b10) cg_status.sample(req.msg[7:5]);
        if (sel == 2'b01)       cg_rx_access.sample(op, rx_level);
    endfunction

    // Call BEFORE the model pushes the frame
    function void sample_frame(uart_frame frame, int rx_level);
        cg_frame.sample(frame.data, frame.frame_err, rx_level);
    endfunction

    function void report();
        $display("[Coverage] requests : %0.1f%%", cg_req.get_inst_coverage());
        $display("[Coverage] ctrl     : %0.1f%%", cg_ctrl.get_inst_coverage());
        $display("[Coverage] tx       : %0.1f%%", cg_tx.get_inst_coverage());
        $display("[Coverage] status   : %0.1f%%", cg_status.get_inst_coverage());
        $display("[Coverage] rx access: %0.1f%%", cg_rx_access.get_inst_coverage());
        $display("[Coverage] rx frames: %0.1f%%", cg_frame.get_inst_coverage());
    endfunction

endclass