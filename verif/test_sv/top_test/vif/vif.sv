//=========================================================================
// Virtual Interface for UART
//=========================================================================

interface uart_if
    import uart_verif_pkg::*;
(
    input logic clk,
    input logic rst
);

    // Request channel
    logic             wrapper_recv_val;
    logic             wrapper_recv_rdy;
    uart_msg_t        wrapper_recv_msg;

    // Response channel
    logic             wrapper_send_val;
    logic             wrapper_send_rdy;
    uart_msg_t        wrapper_send_msg;

    // UART pins
    logic             tx;
    logic             rx;

endinterface