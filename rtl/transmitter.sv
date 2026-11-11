/*
==========================================================================
transmitter.sv
==========================================================================
 - RTL code for the UART transmitter module.
*/

// idle high, start bit low, 8 bits of data, stop bit high, idle high again
// ticks = how long each bit of data lasts, from baud rate

`ifndef uart_TRANSMITTER
`define uart_TRANSMITTER

module uart_Transmitter #(
    parameter int DATA_W = 8
)(
    input  logic clk,
    input  logic reset,
    input  logic en,   // enable, drops back to IDLE when low
    input  logic tick, // bump counter for 16 ticks

    input  logic [DATA_W-1:0]    tx_data,
    input  logic                 tx_val,
    output logic                 tx_rdy,

    output logic tx,
    output logic tx_busy
);

  localparam IDLE  = 2'b00;
  localparam START = 2'b01;
  localparam DATA  = 2'b10;
  localparam STOP  = 2'b11;

  logic [1:0]                  state;
  logic [1:0]                  next_state;
  logic [3:0]                  tick_count;
  logic [$clog2(DATA_W)-1:0]   bit_count;
  logic [DATA_W-1:0]           data_reg;
  logic                        tx_next;

  assign tx_rdy   = (state == IDLE) && en;
  assign tx_busy  = (state != IDLE);

  // tick counter
  always_ff @(posedge clk) begin
    if (reset) tick_count <= 0;
    else if (state == IDLE) begin
      tick_count <= 0;
    end
    else if (tick) begin
      if (tick_count == 15) begin
        tick_count <= 0;
      end
      else begin
        tick_count <= tick_count + 1;
    end
    end
  end

  // state register
  always_ff @(posedge clk) begin
    if (reset) state <= IDLE;
    else       state <= next_state;
  end

  // latch the byte and determine bit_count
  always_ff @(posedge clk) begin
    if (reset) begin
      data_reg  <= 0;
      bit_count <= 0;
    end
    else if (tx_val && tx_rdy) begin
      data_reg  <= tx_data;
      bit_count <= 0;
    end 
    else if (state == DATA && tick && tick_count == 15) begin //actively sending data bits
      bit_count <= bit_count + 1;
    end
  end

  // next state logic
  always_comb begin
    next_state = state;
    if (!en)
      next_state = IDLE;
    else begin
      case (state)
        IDLE:  if (tx_val && tx_rdy) next_state = START;
        START: if (tick && tick_count == 15) next_state = DATA;
        DATA:  if (tick && tick_count == 15 && bit_count == DATA_W - 1) next_state = STOP;
        STOP:  if (tick && tick_count == 15) next_state = IDLE;
        default: next_state = IDLE;
      endcase
    end
  end

  // output logic
  always_comb begin
    case (state)
      IDLE:    tx_next = 1'b1;
      START:   tx_next = 1'b0;
      DATA:    tx_next = data_reg[bit_count]; //bit_count calculated on clock edge
      STOP:    tx_next = 1'b1;
      default: tx_next = 1'b1;
    endcase
  end

  // registered so the pin can't glitch low on state changes
  // (e.g. STOP -> IDLE passing through START looks like a start bit)
  always_ff @(posedge clk) begin
    if (reset) tx <= 1'b1;
    else       tx <= tx_next;
  end

endmodule

`endif
