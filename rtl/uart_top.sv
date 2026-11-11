/*
==========================================================================
uart_top.sv
==========================================================================
 - Top level for the UART
 - Baud rate gen + transmitter + receiver, with regs as the bus interface
*/

`ifndef UART_TOP
`define UART_TOP

`include "ip/uart/rtl/transmitter.sv"
`include "ip/uart/rtl/receiver.sv"
`include "ip/uart/rtl/helpers/baud_rate_gen.sv"
`include "ip/uart/rtl/regs.sv"

module uart_Top#(
    parameter int nbits     = 79,
    parameter int DATA_W    = 8,
    parameter int DIV_W     = 16,
    parameter int Q_SIZE    = 8
)(
    input  logic             clk,
    input  logic             reset,

    // wrapper interface
    input  logic             wrapper_recv_val,
    output logic             wrapper_recv_rdy,
    input  logic [nbits-1:0] wrapper_recv_msg,

    output logic             wrapper_send_val,
    input  logic             wrapper_send_rdy,
    output logic [nbits-1:0] wrapper_send_msg,

    // pins
    output logic             tx,
    input  logic             rx
);

    // regs to baud gen, tx, rx
    logic              uart_en;
    logic [DIV_W-1:0]  baud_div;

    // baud gen to tx, rx
    logic              tick;

    // regs & transmitter
    logic              tx_start;
    logic [DATA_W-1:0] tx_data;
    logic              tx_busy;

    // receiver -& regs
    logic              rx_val;
    logic [DATA_W-1:0] rx_data;
    logic              frame_err;

    uart_BaudRateGenerator #(
        .DIV_W     (DIV_W)
    ) baud_gen (
        .clk       (clk),
        .reset     (reset),
        .en        (uart_en),
        .div       (baud_div),
        .tick      (tick)
    );

    uart_Transmitter #(
        .DATA_W    (DATA_W)
    ) transmitter (
        .clk       (clk),
        .reset     (reset),
        .en        (uart_en),
        .tick      (tick),
        .tx_data   (tx_data),
        .tx_val    (tx_start),
        .tx_rdy    (),          // regs uses tx_busy instead
        .tx        (tx),
        .tx_busy   (tx_busy)
    );

    uart_Receiver #(
        .DATA_W    (DATA_W)
    ) receiver (
        .clk       (clk),
        .reset     (reset),
        .en        (uart_en),
        .tick      (tick),
        .rx        (rx),
        .rx_data   (rx_data),
        .rx_val    (rx_val),
        .frame_err (frame_err)
    );

    uart_regs #(
        .nbits     (nbits),
        .DATA_W    (DATA_W),
        .DIV_W     (DIV_W),
        .Q_SIZE    (Q_SIZE)
    ) regs (
        .clk       (clk),
        .reset     (reset),

        .recv_val  (wrapper_recv_val),
        .recv_rdy  (wrapper_recv_rdy),
        .recv_msg  (wrapper_recv_msg),

        .resp_val  (wrapper_send_val),
        .resp_rdy  (wrapper_send_rdy),
        .resp_msg  (wrapper_send_msg),

        .rx_val    (rx_val),
        .rx_data   (rx_data),
        .frame_err (frame_err),

        .tx_start  (tx_start),
        .tx_data   (tx_data),
        .tx_busy   (tx_busy),

        .uart_en   (uart_en),
        .baud_div  (baud_div)
    );

endmodule

`endif
