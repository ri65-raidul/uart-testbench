/*
==========================================================================
receiver.sv
==========================================================================
 - RTL code for the Receiver
*/

`ifndef uart_RECEIVER
`define uart_RECEIVER


`include "ip/uart/rtl/helpers/synchronizer.sv"

module uart_Receiver 
#(
    parameter int DATA_W = 8
)
(
    input logic                 clk,    // System clk
    input logic                 reset, 
    input logic                 en,     // enable
    input logic                 tick,   // From baud rate gen, oversample strobe
    input logic                 rx,     // raw signal from pin

    output logic [DATA_W - 1:0] rx_data,   // assembled byte(read when rx_val high)
    output logic                rx_val, //1-cycle strobe 
    output logic                frame_err
);

    logic rx_start;
    logic rx_sync_d;
    logic [3:0] tick_count;
    logic [$clog2(DATA_W)- 1 : 0] bit_count;
    logic [DATA_W - 1:0] shreg;

    logic [1:0] current_state;
    logic [1:0] next_state;

    //FSM parameters
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    localparam int FULL = 16;
    localparam int HALF = 8;


    uart_Synchronizer #(1) synchronizer 
    (
        .clk      (clk),
        .reset    (reset),
        .in_      (rx),
        .posedge_ (),
        .negedge_ (rx_start),
        .out      (rx_sync_d)
    );

    // Counters
    always_ff @(posedge clk) begin
        if (reset) begin

            tick_count <= '0;
            bit_count  <= '0;

        end else if (current_state != next_state) begin

            tick_count <= '0; // reset tick count for state transitions
            if (next_state == DATA ) 
                bit_count <= '0; // start bit count

        end else if ( tick && tick_count == FULL - 1) begin

            tick_count <= '0; //reset tick count within phase
            if (current_state == DATA ) 
                bit_count <= bit_count + 1'b1;

        end else if (tick) begin
            tick_count <= tick_count + 1'b1; 
        end
    end

    //  --- FSM logic ---
    
    // Output logic
    always_ff @(posedge clk) begin
        if (reset) begin
            shreg     <= '0;
            rx_data   <= '0;
            rx_val    <= 1'b0;
            frame_err <= 1'b0;
        end else begin
            rx_val <= 1'b0; 
            
            unique case (current_state)
                IDLE : begin  
                end
                START : begin
                end
                DATA : begin
                    // at each bit center, shift the sampled bit in LSB-first
                    if ( tick && tick_count == FULL -1)
                        shreg <= {rx_sync_d, shreg[DATA_W-1:1]};
                end
                STOP : begin
                    if ( tick && tick_count == FULL - 1) begin
                        rx_data   <= shreg;
                        rx_val    <= 1'b1;
                        frame_err <= ~rx_sync_d; //stop bit should be high
                    end
                end
                default : begin
                end
            endcase
        end
    end

    // Next state logic 
    always_comb begin
        next_state = current_state; //default hold
        if (!en) 
            next_state = IDLE;
        else begin 
            unique case (current_state)
                IDLE    : next_state = (rx_start) ? START : IDLE;
                START   : begin
                    if ( tick && (tick_count == HALF - 1) )
                        next_state = (rx_sync_d) ? IDLE : DATA; //Abort if line goes high
                end
                DATA    : begin
                    if ( tick && (tick_count == FULL - 1) 
                            && (bit_count == DATA_W -1))
                        next_state = STOP;
                end     
                STOP    : begin
                    if ( tick && (tick_count == FULL - 1))
                        next_state = IDLE;
                end
                default : next_state = IDLE;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
endmodule

`endif