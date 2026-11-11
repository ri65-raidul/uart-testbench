//=========================================================================
// UART integration testbench
//=========================================================================

module uart_test_top;

    import uart_verif_pkg::*;

    localparam int unsigned BAUD_DIV       = 8;
    localparam int unsigned CLKS_PER_BIT   = 16 * BAUD_DIV;
    int unsigned TIMEOUT_CYCLES = 60000;

    int expected_resp;
    int expected_tx;

    //---------------------------------------------------------------------
    // Clock, rst, vif, and dut
    //---------------------------------------------------------------------

    logic clk;
    logic rst;

    TestUtilsClkRst t (
        .clk (clk),
        .rst (rst)
    );

    uart_if vif (
        .clk (clk),
        .rst (rst)
    );

    uart_Top dut (
        .clk              (clk),
        .reset            (rst),

        .wrapper_recv_val (vif.wrapper_recv_val),
        .wrapper_recv_rdy (vif.wrapper_recv_rdy),
        .wrapper_recv_msg (vif.wrapper_recv_msg),

        .wrapper_send_val (vif.wrapper_send_val),
        .wrapper_send_rdy (vif.wrapper_send_rdy),
        .wrapper_send_msg (vif.wrapper_send_msg),

        .tx               (vif.tx),
        .rx               (vif.rx)
    );

    //---------------------------------------------------------------------
    // Environment components
    //---------------------------------------------------------------------

    driver_req   req_drv;
    driver_rx    rx_drv;
    monitor_resp resp_mon;
    monitor_tx   tx_mon;
    model        ref_model;
    scoreboard   scb;

    //---------------------------------------------------------------------
    // Shared mailboxes
    //---------------------------------------------------------------------

    mailbox #(uart_req)   req_in;
    mailbox #(uart_frame) rx_in;

    mailbox #(uart_resp)  expected_resp_mbx;
    mailbox #(uart_frame) expected_tx_mbx;

    mailbox #(uart_resp)  actual_resp;
    mailbox #(uart_frame) actual_tx;

    int unsigned requests_sent  = 0;
    int unsigned responses_seen = 0;

    // Count accepted responses independently of the scoreboard
    always @(posedge clk) begin
        if (rst === 1'b1)
            responses_seen = 0;
        else if (rst === 1'b0 &&
                 vif.wrapper_send_val === 1'b1 &&
                 vif.wrapper_send_rdy === 1'b1)
            responses_seen++;
    end

    //---------------------------------------------------------------------
    // Shared bus-access helper
    //---------------------------------------------------------------------

    task automatic access_reg(
        input bit          write,
        input logic [31:0] addr,
        input logic [31:0] data
    );
        uart_req req;
        msg_t fields;

        req = new();

        fields        = '0;
        fields.op     = write;
        fields.opaque = 8'(requests_sent);
        fields.addr   = addr;
        fields.strb   = 4'hF;
        fields.data   = data;

        req.msg = fields;

        req_drv.send(req);
        requests_sent++;

        // wait bounded by watchdog
        wait ((scb.resp_pass + scb.resp_fail) >= requests_sent);

        if (scb.resp_fail != 0)
            $fatal(1, "[TB] Bus response comparison failed");
    endtask

    //---------------------------------------------------------------------
    // Test cases
    //---------------------------------------------------------------------

    `include "ip/uart/verif/test_sv/top_test/tests/uart_directed_tests.sv"

    //---------------------------------------------------------------------
    // Verification Environment
    //---------------------------------------------------------------------

    task automatic build_environment();
        req_in            = new();
        rx_in             = new();
        expected_resp_mbx = new();
        expected_tx_mbx   = new();
        actual_resp       = new();
        actual_tx         = new();

        req_drv   = new(vif);
        rx_drv    = new(vif);
        resp_mon  = new(vif);
        tx_mon    = new(vif);
        ref_model = new();
        scb       = new();

        // driver -> model
        req_drv.drv2model_req     = req_in;
        ref_model.drv2model_req   = req_in;
        ref_model.drv2model_frame = rx_in;

        // model -> scoreboard
        ref_model.model2scb_resp  = expected_resp_mbx;
        ref_model.model2scb_frame = expected_tx_mbx;
        scb.model2scb_resp        = expected_resp_mbx;
        scb.model2scb_frame       = expected_tx_mbx;

        // monitors -> scoreboard
        resp_mon.mon2scb_mbx = actual_resp;
        tx_mon.mon2scb_mbx   = actual_tx;
        scb.mon2scb_resp     = actual_resp;
        scb.mon2scb_frame    = actual_tx;

        req_drv.init();
        rx_drv.init();
    endtask

    //---------------------------------------------------------------------
    // Final checks
    //---------------------------------------------------------------------

    task automatic check_results();
        repeat (2 * CLKS_PER_BIT)
            @(negedge clk);

        scb.report();
        ref_model.cov.report();

        `TEST_UTILS_CHECK_EQ(requests_sent, expected_resp);
        `TEST_UTILS_CHECK_EQ(responses_seen, expected_resp);
        `TEST_UTILS_CHECK_EQ(scb.resp_pass, expected_resp);
        `TEST_UTILS_CHECK_EQ(scb.resp_fail, 0);
        `TEST_UTILS_CHECK_EQ(scb.tx_pass, expected_tx);
        `TEST_UTILS_CHECK_EQ(scb.tx_fail, 0);

        `TEST_UTILS_CHECK_EQ(req_in.num(), 0);
        `TEST_UTILS_CHECK_EQ(rx_in.num(), 0);
        `TEST_UTILS_CHECK_EQ(expected_resp_mbx.num(), 0);
        `TEST_UTILS_CHECK_EQ(expected_tx_mbx.num(), 0);
        `TEST_UTILS_CHECK_EQ(actual_resp.num(), 0);
        `TEST_UTILS_CHECK_EQ(actual_tx.num(), 0);

        if (t.failed)
            $fatal(1, "[TB] UART test %0d FAILED", t.n);

        $display("\n[TB] UART test %0d PASSED", t.n);
    endtask

    //---------------------------------------------------------------------
    // Tests
    //---------------------------------------------------------------------

    initial begin
        build_environment();

        t.test_bench_begin();
        t.test_suite_begin("UART integration");

        case (t.n)
            0, 1: begin
                expected_resp = 8;
                expected_tx   = 1;
                t.test_case_begin(
                    "UART register and serial smoke test", 1
                );
            end

            2: begin
                expected_resp = 7;
                expected_tx   = 0;
                t.test_case_begin("UART CTRL register", 2);
            end

            3: begin
                expected_resp = 9;
                expected_tx   = 8;
                t.test_case_begin("UART TX data patterns", 3);
            end

            4: begin
                expected_resp = 26;
                expected_tx   = 0;
                t.test_case_begin("UART RX FIFO ordering", 4);
            end

            5: begin
                expected_resp = 8;
                expected_tx   = 0;
                t.test_case_begin("UART RX bad-stop recovery", 5);
            end

            6: begin
                expected_resp = 35;
                expected_tx   = 0;
                t.test_case_begin("UART STATUS register", 6);
            end

            7: begin
                expected_resp = 6;
                expected_tx   = 0;
                t.test_case_begin("UART RX false-start rejection", 7);
            end

            8: begin
                expected_resp = 10;
                expected_tx   = 0;
                t.test_case_begin("UART RX disable mid-frame", 8);
            end

            9: begin
                expected_resp = 8;
                expected_tx   = 0;
                t.test_case_begin("UART TX abort during START/DATA", 9);
            end

            10: begin
                expected_resp = 17;
                expected_tx   = 0;
                t.test_case_begin("UART TX FIFO overflow", 10);
            end
            11 : begin
                expected_resp  = 50;
                expected_tx    = 5;
                TIMEOUT_CYCLES = 500000;
                t.test_case_begin("UART baud rates", 11);
            end

            default:
                $fatal(1, "[TB] Unsupported test-case=%0d", t.n);
        endcase

        fork
            resp_mon.run();
            if (t.n != 9)
                tx_mon.run();
            ref_model.run();
            scb.run();
        join_none

        @(negedge clk);

        // disable utility bit
        if (t.n == 9 || t.n == 10)
            ref_model.predict_tx_frames = 1'b0;

        case (t.n)
            0, 1: uart_directed_smoke();
            2:    uart_directed_ctrl();
            3:    uart_directed_tx_patterns();
            4:    uart_directed_rx_fifo();
            5:    uart_directed_rx_bad_stop();
            6:    uart_directed_status();
            7:    uart_directed_rx_false_start();
            8:    uart_directed_rx_disable();
            9:    uart_directed_tx_disable();
            10:   uart_directed_tx_overflow();
            11:   uart_directed_baud_rates();
        endcase

        check_results();

        t.test_case_end();
        t.test_suite_end();
        t.test_bench_end();
    end

    //---------------------------------------------------------------------
    // Watchdog
    //---------------------------------------------------------------------

    initial begin
        #1;
        repeat (TIMEOUT_CYCLES)
            @(posedge clk);

        $fatal(1, "[TB] UART test timed out");
    end

endmodule