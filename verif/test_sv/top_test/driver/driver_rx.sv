import uart_verif_pkg::*;

class driver_rx;

    virtual uart_if vif;

    function new(virtual uart_if vif_i);
        vif = vif_i;
    endfunction

    task init();
        vif.rx = 1'b1; // rx idle
    endtask

    task drive_bit(
        input bit value,
        input int unsigned cycles_per_bit
    );
        vif.rx = value;
        repeat(cycles_per_bit) begin
            @(negedge vif.clk);
        end
    endtask

    task send(
        input uart_frame frame,
        input int unsigned baud_div
    );
        int unsigned cycles_per_bit;
        uart_byte_t data;
        bit bad_stop;

        if (frame == null)
            $fatal(1, "[driver_rx] send() received a null frame");

        if (baud_div == 0 || baud_div > 65535)
            $fatal(1, "[driver_rx] baud_div must be between 1 and 65535");

        cycles_per_bit = 16 * baud_div;

        data = frame.data;
        bad_stop = frame.frame_err;

        do begin
            @(negedge vif.clk);
        end while (vif.rst !== 1'b0);
    
        // start bit
        drive_bit(1'b0, cycles_per_bit);

        // data bits, LSB first
        for (int i = 0; i < DATA_W; i++) begin
            drive_bit(data[i], cycles_per_bit);
        end

        // stop bit, optional frame error
        drive_bit(~bad_stop, cycles_per_bit);

        if (bad_stop)
            drive_bit(1'b1, cycles_per_bit); // return to IDLE
    endtask

    task send_false_start(input int unsigned baud_div);
        int unsigned pulse_cycles;

        if (baud_div == 0 || baud_div > 65535)
            $fatal(1, "[driver_rx] baud_div must be between 1 and 65535");

        // Three ticks, shorter than half a bit period
        pulse_cycles = 3 * baud_div;
    
        do begin
            @(negedge vif.clk);
        end while (vif.rst !== 1'b0);

        // Drive short false start pulse
        drive_bit(1'b0, pulse_cycles);

        // Return to idle for two bit periods
        drive_bit(1'b1, 32*baud_div);
    endtask

endclass
