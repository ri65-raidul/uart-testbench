/*
==========================================================================
uart_tx_test_top.sv
==========================================================================
 - Top level testbench for the UART transmitter module.
*/

module uart_tx_test_top;
    import uart_transmitter_verif_pkg::*;

    // --------------------------------------------------------
    // Clock & reset
    // --------------------------------------------------------
    logic clk;
    logic rst;

    // 100 MHz clock (10 ns period)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Active-high reset: asserted at time 0, released after 5 cycles
    initial begin
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst <= 1'b0;
    end

    // --------------------------------------------------------
    // Virtual Interface
    // --------------------------------------------------------
    uart_tx_if vif(clk, rst);

    // --------------------------------------------------------
    // Tick generation
    // --------------------------------------------------------
    initial begin
        int count = 0;
        vif.tick = 0;
        forever begin
            @(posedge clk);
            if (rst) begin
                vif.tick <= 0;
                count = 0;
            end else if (count >= vif.tick_div - 1) begin
                vif.tick <= 1;
                count = 0;
            end else begin
                vif.tick <= 0;
                count++;
            end
        end
    end

    // --------------------------------------------------------
    // DUT
    // --------------------------------------------------------
    uart_Transmitter #(
        .DATA_W  (DATA_W)
    ) dut (
        .clk     (clk),
        .reset   (rst),
        .en      (1'b1),
        .tick    (vif.tick),
        .tx_data (vif.tx_data),
        .tx_val  (vif.tx_val),
        .tx_rdy  (vif.tx_rdy),

        // dut outputs
        .tx      (vif.tx),
        .tx_busy (vif.tx_busy)
    );

    // --------------------------------------------------------
    // Verif Components
    // --------------------------------------------------------
    mailbox #(uart_tx_trans) drv_mbx;
    mailbox #(uart_tx_trans) model_mbx;
    mailbox #(uart_tx_trans) exp_mbx;
    mailbox #(uart_tx_trans) scb_mbx;

    uart_transmitter_driver         drv;
    uart_transmitter_monitor        mon;
    uart_transmitter_model          model;
    uart_transmitter_scoreboard     scb;
    uart_transmitter_directed_tests tests;

    initial begin
        // Mailboxes
        drv_mbx   = new();
        model_mbx = new();
        exp_mbx   = new();
        scb_mbx   = new();

        // Components
        drv   = new();
        mon   = new();
        model = new();
        scb   = new();
        tests = new();

        // Connections
        drv.vif     = vif;
        drv.drv_mbx = drv_mbx;

        mon.vif       = vif;
        mon.model_mbx = model_mbx;
        mon.scb_mbx   = scb_mbx;

        model.model_mbx = model_mbx;
        model.exp_mbx   = exp_mbx;

        scb.scb_mbx = scb_mbx;
        scb.exp_mbx = exp_mbx;

        tests.vif     = vif;
        tests.drv_mbx = drv_mbx;
        tests.scb     = scb;

        // Start components
        fork
            drv.run();
            mon.run();
            model.run();
            scb.run();
        join_none

        // Run tests
        wait (!rst);
        tests.test_single_byte();
        // tests.run_all();

        // Finish
        scb.report();
        $finish;
    end

    // --------------------------------------------------------
    // Watchdog
    // --------------------------------------------------------
    initial begin
        #10ms;
        $fatal(1, "Timeout: test did not finish");
    end

    // --------------------------------------------------------
    // Waves
    // --------------------------------------------------------
    initial begin
        $dumpfile("uart_tx.vcd");
        $dumpvars(0, uart_tx_test_top);
    end

endmodule