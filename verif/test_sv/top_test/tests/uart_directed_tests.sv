//=========================================================================
// UART directed tests
//=========================================================================

//-------------------------------------------------------------------------
// Shared stimulus helpers
//-------------------------------------------------------------------------

task automatic directed_enable();
    logic [31:0] ctrl_data;

    ctrl_data = (BAUD_DIV << 16) | 32'h1;
    access_reg(1'b1, 32'h0000_000C, ctrl_data);
endtask

task automatic directed_receive(
    input uart_byte_t data,
    input bit         bad_stop = 1'b0
);
    uart_frame frame;
    uart_frame model_frame;

    frame = new();
    frame.data      = data;
    frame.frame_err = bad_stop;

    rx_drv.send(frame, BAUD_DIV);

    model_frame = new();
    model_frame.data      = data;
    model_frame.frame_err = bad_stop;
    rx_in.put(model_frame);

    // settle
    repeat (CLKS_PER_BIT)
        @(negedge clk);
endtask

task automatic status_read();
    access_reg(1'b0, 32'h0000_0008, '0);
endtask

task automatic status_write(input logic [31:0] data);
    access_reg(1'b1, 32'h0000_0008, data);
endtask

task automatic directed_wait_tx(input int target);
    wait ((scb.tx_pass + scb.tx_fail) >= target);

    if (scb.tx_fail != 0)
        $fatal(1, "[TB] TX frame comparison failed");

    // complete stop bit
    repeat (2 * CLKS_PER_BIT)
        @(negedge clk);
endtask

task automatic directed_abort_tx(
    input int unsigned cycles_after_start,
    input string       phase
);
    logic [31:0] ctrl_data;

    $display("[TB] Aborting TX during %s", phase);

    // Issue TXDATA write and detect the physical start bit
    // The fork avoids missing the falling edge while access_reg waits for the bus response
    fork
        begin
            @(negedge vif.tx);
            repeat (cycles_after_start)
                @(negedge clk);
        end

        begin
            access_reg(1'b1, 32'h0000_0000, 32'h0000_0000);
        end
    join

    // Disable UART (keep baud div)
    ctrl_data = BAUD_DIV << 16; // lsb (en) = 0
    access_reg(1'b1, 32'h0000_000C, ctrl_data);

    repeat (4)
        @(negedge clk);

    // TX must stay high after the abort
    repeat (2 * CLKS_PER_BIT) begin
        @(negedge clk);

        if (vif.tx !== 1'b1)
            $fatal(1,
                "[TB] TX did not remain idle after %s abort",
                phase
            );
    end

    // Verify CTRL readback after disabling.
    access_reg(1'b0, 32'h0000_000C, '0);
endtask

// just a quick workaround to adding model status predictions
// (manually calculate expected status values)
task automatic status_expect(
    input logic [7:0] expected
);
    int unsigned previous_count;

    previous_count = scb.status_read_count;

    // Read STATUS
    status_read();

    // Confirm a new STATUS read was observed
    if (scb.status_read_count != previous_count + 1)
        $fatal(1, "[TB] STATUS response not captured");

    // Check STATUS bits
    if (scb.last_status_rdata[7:0] !== expected)
        $fatal(1,
            "[TB] STATUS mismatch: expected=0x%02h actual=0x%02h",
            expected,
            scb.last_status_rdata[7:0]
        );
endtask

//-------------------------------------------------------------------------
// Test 1: Register and serial smoke test
// Expected: 8 responses, 1 TX frame
//-------------------------------------------------------------------------

task automatic uart_directed_smoke();
    directed_enable();

    // TXDATA reads should return zero
    access_reg(1'b0, 32'h0000_0000, 32'h0);

    // CTRL readback
    access_reg(1'b0, 32'h0000_000C, '0);

    // transmit one byte
    access_reg(1'b1, 32'h0000_0000, 32'h0000_00A5);
    directed_wait_tx(1);

    // receive one byte
    directed_receive(8'h3C);

    // RXDATA read (peek) should be same response
    access_reg(1'b0, 32'h0000_0004, '0);
    access_reg(1'b0, 32'h0000_0004, '0);

    // RXDATA write (pop)
    access_reg(1'b1, 32'h0000_0004, '0);

    // queue is empty, return 0
    access_reg(1'b0, 32'h0000_0004, '0);
endtask

//-------------------------------------------------------------------------
// Test 2: CTRL reset, zero divisor, enable, and disable
// Expected: 7 responses, 0 TX frames
//-------------------------------------------------------------------------

task automatic uart_directed_ctrl();
    logic [31:0] ctrl_data;

    // reset state
    access_reg(1'b0, 32'h0000_000C, '0);

    // zero divisor must prevent enabling
    access_reg(1'b1, 32'h0000_000C, 32'h0000_0001);
    access_reg(1'b0, 32'h0000_000C, '0);

    // enable with a valid divisor
    ctrl_data = (BAUD_DIV << 16) | 32'h1;
    access_reg(1'b1, 32'h0000_000C, ctrl_data);
    access_reg(1'b0, 32'h0000_000C, '0);

    // disable while retaining the divisor
    ctrl_data = BAUD_DIV << 16;
    access_reg(1'b1, 32'h0000_000C, ctrl_data);
    access_reg(1'b0, 32'h0000_000C, '0);
endtask

//-------------------------------------------------------------------------
// Test 3: Serialized TX data patterns
// Expected: 9 responses, 8 TX frames
//-------------------------------------------------------------------------

task automatic uart_directed_tx_patterns();
    uart_byte_t patterns[8];

    patterns = '{
        8'h00, 8'hFF, 8'h55, 8'hAA,
        8'h01, 8'h80, 8'h3C, 8'hC3
    };

    directed_enable();

    foreach (patterns[i]) begin
        $display("[TB] TX pattern %0d: 0x%02h", i, patterns[i]);

        access_reg(
            1'b1,
            32'h0000_0000,
            {24'b0, patterns[i]}
        );

        directed_wait_tx(i + 1);
    end
endtask

//-------------------------------------------------------------------------
// Test 4: Fill RX FIFO, check ordering -> (peek twice, then pop) each
// Expected: 26 responses, 0 TX frames
//-------------------------------------------------------------------------

task automatic uart_directed_rx_fifo();
    uart_byte_t patterns[8];

    patterns = '{
        8'h00, 8'hFF, 8'h55, 8'hAA,
        8'h01, 8'h80, 8'h3C, 8'hC3
    };

    directed_enable();

        foreach (patterns[i]) begin
        directed_receive(patterns[i]);

        // Bad frame with a partially full queue: must be dropped
        // without disturbing the bytes already queued
        if (i == 3)
            directed_receive(8'hEE, 1'b1);
    end

    foreach (patterns[i]) begin
        $display("[TB] RX FIFO entry %0d: 0x%02h", i, patterns[i]);

        access_reg(1'b0, 32'h0000_0004, '0);
        access_reg(1'b0, 32'h0000_0004, '0);
        access_reg(1'b1, 32'h0000_0004, '0);
    end

    access_reg(1'b0, 32'h0000_0004, '0);
endtask

//-------------------------------------------------------------------------
// Test 5: Receive a bad-stop frame, then a valid-stop frame
// Expected: 5 responses, 0 TX frames
//-------------------------------------------------------------------------

task automatic uart_directed_rx_bad_stop();
    directed_enable();

    directed_receive(8'hA5, 1'b1);

    // Bad frame must not enter RX FIFO
    access_reg(1'b0, 32'h0000_0004, '0);

    // Receiver must recover for the next valid frame
    directed_receive(8'h3C);

    access_reg(1'b0, 32'h0000_0004, '0);
    access_reg(1'b1, 32'h0000_0004, '0);
    access_reg(1'b0, 32'h0000_0004, '0);
        
    // Pop on an empty queue: must be a no-op (no underflow)
    access_reg(1'b1, 32'h0000_0004, '0);

    // Queue must still work normally afterward
    directed_receive(8'h5A);
    access_reg(1'b0, 32'h0000_0004, '0);   // peek: 0x5A
    access_reg(1'b1, 32'h0000_0004, '0);   // pop
endtask

//-------------------------------------------------------------------------
// Test 6: STATUS register -- RX level bits, sticky flags, write-1-to-clear
// Expected: 32 responses, 0 TX frames
//-------------------------------------------------------------------------

task automatic uart_directed_status();
    uart_byte_t patterns[8];

    patterns = '{
        8'h00, 8'hFF, 8'h55, 8'hAA,
        8'h01, 8'h80, 8'h3C, 8'hC3
    };

    // After reset: nothing received, no flags                       (1)
    status_read();

    directed_enable();                                             // (2)

    // One byte in: RX available = 1                                 (3)
    directed_receive(8'h11);
    status_read();

    // Peek byte (does not consume)
    access_reg(1'b0, 32'h0000_0004, '0);

    // Dequeue the received byte (pop)
    access_reg(1'b1, 32'h0000_0004, '0);

    // RX FIFO should now be empty
    status_read();

    // Bad stop bit: frame error flag (bit 5) set, byte dropped      (6)
    directed_receive(8'h22, 1'b1);
    status_read();

    // Writing 0 must NOT clear it                                   (7, 8)
    status_write(32'h0000_0000);
    status_read();

    // Writing 1 to bit 5 clears it                                  (9, 10)
    status_write(32'h0000_0020);
    status_read();

    // Fill the RX queue: available = 1, full = 1                    (11)
    foreach (patterns[i])
        directed_receive(patterns[i]);
    status_read();

    // 9th byte while full: dropped, overrun flag (bit 6) set        (12)
    directed_receive(8'h99);
    status_read();

    // Writing 1 to bit 6 clears overrun                             (13, 14)
    status_write(32'h0000_0040);
    status_read();
    
    // Queue is still full: a bad frame sets frame error,
    // a good frame sets overrun again
    directed_receive(8'h33, 1'b1);   // frame error (also bad frame x full queue)
    directed_receive(8'h44);         // overrun

    // Both sticky flags set, queue still full
    status_read();

    // One write clears both (multiple bin)
    status_write(32'h0000_0060);
    status_read();

    // Drain: 8 bytes in order, the dropped 0x99 must not appear     (15-22)
    foreach (patterns[i]) begin
        // Verify front byte
        access_reg(1'b0, 32'h0000_0004, '0);

        // Dequeue front byte
        access_reg(1'b1, 32'h0000_0004, '0);
    end

    // Empty again: available = 0, full = 0                          (23)
    status_read();
endtask


//-------------------------------------------------------------------------
// Test 7: RX false-start rejection and recovery
// Expected: 6 responses, 0 TX frames
//-------------------------------------------------------------------------

task automatic uart_directed_rx_false_start();
    directed_enable();

    // Short low pulse must be rejected as an invalid start bit
    rx_drv.send_false_start(BAUD_DIV);

    // RX FIFO must remain empty
    access_reg(1'b0, 32'h0000_0004, '0);

    // No receive activity or sticky error should be reported
    status_read();

    // Receiver must recover and accept a subsequent valid frame
    directed_receive(8'hA6);

    // Verify the received byte
    access_reg(1'b0, 32'h0000_0004, '0);

    // Pop the received byte
    access_reg(1'b1, 32'h0000_0004, '0);

    // FIFO empty again
    access_reg(1'b0, 32'h0000_0004, '0);
endtask


//-------------------------------------------------------------------------
// Test 8: Disable UART during RX DATA, then recover
// Expected: 8 responses, 0 TX frames
//-------------------------------------------------------------------------

task automatic uart_directed_rx_disable();
    logic [31:0] ctrl_data;

    directed_enable();

    // Begin a valid start bit and enter the DATA state
    rx_drv.drive_bit(
        1'b0,
        CLKS_PER_BIT + (4 * BAUD_DIV)
    );

    // Disable UART while the receiver is processing DATA
    ctrl_data = BAUD_DIV << 16; // keep baud divisor
    access_reg(1'b1, 32'h0000_000C, ctrl_data); // en bit (lsb) is 0

    // Return RX to idle and allow the receiver to settle
    rx_drv.drive_bit(1'b1, 2 * CLKS_PER_BIT);

    // Aborted frame must not enter RX FIFO
    access_reg(1'b0, 32'h0000_0004, '0);
    status_read();

    // Re-enable UART and verify normal operation
    directed_enable();
    directed_receive(8'h5A);

    // Peek while enabled
    access_reg(1'b0, 32'h0000_0004, '0);           // 0x5A

    // Disable with the byte still queued
    ctrl_data = BAUD_DIV << 16;
    access_reg(1'b1, 32'h0000_000C, ctrl_data);

    // Queue must still be drainable while disabled
    access_reg(1'b1, 32'h0000_0004, '0);           // pop while disabled (new bin)
    access_reg(1'b0, 32'h0000_0004, '0);           // empty: 0

    // TXDATA read while disabled returns 0 (new bin)
    access_reg(1'b0, 32'h0000_0000, '0);
endtask


//-------------------------------------------------------------------------
// Test 9: TX abort during START and DATA
// Expected: 8 responses, 0 completed TX frames
//-------------------------------------------------------------------------

task automatic uart_directed_tx_disable();

    // Abort during START
    directed_enable();

    directed_abort_tx(
        2 * BAUD_DIV,
        "START"
    );

    // Abort during DATA
    directed_enable();

    directed_abort_tx(
        CLKS_PER_BIT + 2 * BAUD_DIV,
        "DATA"
    );

endtask


//-------------------------------------------------------------------------
// Test 10: TX FIFO saturation, overflow, and write-1-to-clear
// Expected: 17 responses, 0 TX frames
//-------------------------------------------------------------------------

task automatic uart_directed_tx_overflow();
    logic [31:0] ctrl_data;

    // Keep UART disabled, but configure a valid baud divisor
    // TX FIFO can accept writes, but cannot dequeue
    ctrl_data = BAUD_DIV << 16;
    access_reg(1'b1, 32'h0000_000C, ctrl_data);

    // Initial state: TX FIFO empty, no sticky flags
    status_expect(8'h04);

    // Fill TX FIFO
    for (int i = 0; i < 8; i++) begin
        $display("[TB] TX FIFO enqueue %0d", i);
        access_reg(
            1'b1,
            32'h0000_0000,
            i + 1
        );
    end

    // TX FIFO should now be full
    status_expect(8'h08);

    // Ninth write must overflow the full FIFO
    access_reg(1'b1, 32'h0000_0000, 32'h0000_0099);

    // Full bit and sticky overflow bit must both be set
    status_expect(8'h88);

    // Writing zero must not clear the overflow flag
    status_write(32'h0000_0000);
    status_expect(8'h88);

    // Writing one to bit 7 clears TX overflow
    status_write(32'h0000_0080);

    // FIFO remains full after clearing the overflow flag
    status_expect(8'h08);

endtask

//-------------------------------------------------------------------------
// Test 11: Baud rates -- enable/disable at every cg_ctrl divisor bin
//
// Covers every bin of cg_ctrl (cp_ctrl_en x cp_baud_div):
//   divisors 1, 7, 27, 54, 651 : configured AND exercised (TX + RX frame)
//   divisors 0, 16'hFFFF       : configured only (no serial traffic;
//                                a 0xFFFF frame is ~10M cycles)
//
// Expected: 50 responses, 5 TX frames
//   functional rates: 5 x 8 = 40
//   config-only rates: 2 x 5 = 10
//-------------------------------------------------------------------------

// Write CTRL with an explicit divisor and enable
task automatic ctrl_write(input logic [15:0] div, input bit en);
    access_reg(1'b1, 32'h0000_000C, {div, 15'b0, en});
endtask

task automatic ctrl_read();
    access_reg(1'b0, 32'h0000_000C, '0);
endtask

// directed_receive, but at an arbitrary divisor
task automatic directed_receive_div(
    input uart_byte_t  data,
    input logic [15:0] div
);
    uart_frame frame;
    uart_frame model_frame;

    frame = new();
    frame.data      = data;
    frame.frame_err = 1'b0;
    rx_drv.send(frame, div);

    model_frame = new();
    model_frame.data      = data;
    model_frame.frame_err = 1'b0;
    rx_in.put(model_frame);

    // settle one bit period at this rate
    repeat (16 * div)
        @(negedge clk);
endtask

task automatic uart_directed_baud_rates();
    logic [15:0] func_divs[5];
    uart_byte_t  tx_bytes[5];
    uart_byte_t  rx_bytes[5];
    int          tx_count = 0;

    // 1 = fastest, then 921600 / 230400 / 115200 / 9600 baud @ 100 MHz
    func_divs = '{16'd1, 16'd7, 16'd27, 16'd54, 16'd651};
    tx_bytes  = '{8'h81, 8'h5A, 8'hC3, 8'h0F, 8'hA5};
    rx_bytes  = '{8'h7E, 8'h18, 8'hE7, 8'h3C, 8'h66};

    // ---- Config-only divisors (5 responses each) ----

    // Zero divisor
    ctrl_write(16'd0, 1'b0);
    ctrl_read();
    ctrl_write(16'd0, 1'b1);
    ctrl_read();
    ctrl_write(16'd0, 1'b0);

    // Maximum divisor
    ctrl_write(16'hFFFF, 1'b0);
    ctrl_read();
    ctrl_write(16'hFFFF, 1'b1);
    ctrl_read();
    ctrl_write(16'hFFFF, 1'b0);

    // ---- Functional divisors (8 responses each) ----
    foreach (func_divs[i]) begin
        $display("[TB] Baud test: div=%0d", func_divs[i]);

        // Configure while disabled, then enable
        ctrl_write(func_divs[i], 1'b0);
        ctrl_read();
        ctrl_write(func_divs[i], 1'b1);
        ctrl_read();

        // TX one byte at this rate (monitor_tx follows the CTRL write)
        access_reg(1'b1, 32'h0000_0000, {24'b0, tx_bytes[i]});
        tx_count++;
        directed_wait_tx(tx_count);

        // Let the stop bit finish at this rate before anything else
        repeat (16 * func_divs[i])
            @(negedge clk);

        // RX one byte at this rate
        directed_receive_div(rx_bytes[i], func_divs[i]);

        access_reg(1'b0, 32'h0000_0004, '0);   // peek
        access_reg(1'b1, 32'h0000_0004, '0);   // pop
        access_reg(1'b0, 32'h0000_0004, '0);   // empty
    end
endtask