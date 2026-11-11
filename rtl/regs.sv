/*
==========================================================================
regs.sv
==========================================================================
 - RTL code for the registers needed for UART communication
 - Essentially a wrapper for tx and rx
*/


`include "ip/cmn/rtl/queues.sv"

`ifndef UART_REGS
`define UART_REGS

module uart_regs #(
    parameter int nbits     = 79,
    parameter int DATA_W    = 8,
    parameter int BUS_W     = 32,
    parameter int DIV_W     = 16,
    parameter int Q_SIZE    = 8
)
(
    input  logic             clk,
    input  logic             reset,
        
    
    input  logic             recv_val,
    output logic             recv_rdy,
    input  logic [nbits-1:0] recv_msg,

    output logic             resp_val,
    input  logic             resp_rdy,
    output logic [nbits-1:0] resp_msg,

    // Receiver side
    input logic               rx_val,
    input logic [DATA_W-1:0]  rx_data,
    input logic               frame_err,

    // Tranceiver side
    output logic              tx_start,
    output logic [DATA_W-1:0] tx_data,
    input  logic              tx_busy,

    // Baud gen
    output logic              uart_en,
    output logic [DIV_W-1:0]  baud_div


);

    // Register offsets

    localparam logic [1:0] TXDATA = 2'd0; // 0x0 W
    localparam logic [1:0] RXDATA = 2'd1; // 0x4 R: Peek head bye, W: pop (data ignored)
    localparam logic [1:0] STATUS = 2'd2; // 0x8 R,
    localparam logic [1:0] CTRL = 2'd3; // 0xC R/W, write with sw (strb is ignored), what turns it ON

    typedef struct packed {
        logic                    op;
        logic [nbits-BUS_W-40:0] opaque;
        logic [1:0]              origin;
        logic [31:0]             addr;
        logic [3:0]              strb;
        logic [BUS_W-1:0]        data;
    } mem_msg_t;

    mem_msg_t req_msg;
    assign req_msg = recv_msg;

    logic [1:0] reg_sel;
    assign reg_sel = req_msg.addr[3:2];

    // TODO: tx/rx interrupt enables (CTRL bits 1-2) once BLIMP supports interrupts-- can do polling for now..?

    // queues

    logic tx_enq_val, tx_enq_rdy;
    logic tx_deq_val, tx_deq_rdy;
    logic [DATA_W-1:0] tx_deq_msg;

    // tx queue
    cmn_Queue #(.p_msg_nbits(DATA_W), .p_num_msgs(Q_SIZE)) tx_queue
    (
        .clk(clk),
        .reset(reset),
        .enq_val(tx_enq_val),
        .enq_rdy(tx_enq_rdy),
        .enq_msg(req_msg.data[DATA_W-1:0]), // TXDATA byte is the low byte of the write data

        .deq_val(tx_deq_val),
        .deq_rdy(tx_deq_rdy),
        .deq_msg(tx_deq_msg),

        .num_free_entries()
    );

    logic rx_enq_val, rx_enq_rdy;
    logic rx_deq_val, rx_deq_rdy;
    logic [DATA_W-1:0] rx_deq_msg;

    // rx queue
    cmn_Queue #(.p_msg_nbits(DATA_W), .p_num_msgs(Q_SIZE)) rx_queue
    (
        .clk(clk),
        .reset(reset),
        
        .enq_val(rx_enq_val),
        .enq_rdy(rx_enq_rdy),
        .enq_msg(rx_data),

        .deq_val(rx_deq_val),
        .deq_rdy(rx_deq_rdy),
        .deq_msg(rx_deq_msg),

        .num_free_entries()
    );

    // logic
    assign recv_rdy = !resp_val || resp_rdy;
    logic do_req;
    assign do_req = recv_val && recv_rdy;

    // tx path-- moving bytes
    assign tx_enq_val = do_req && req_msg.op && (reg_sel == TXDATA);
    assign tx_start   = tx_deq_val && !tx_busy && uart_en;
    assign tx_deq_rdy = !tx_busy && uart_en;
    assign tx_data    = tx_deq_msg;

    // rx path-- moving bytes
    assign rx_enq_val = rx_val && !frame_err;
    assign rx_deq_rdy = do_req && req_msg.op && (reg_sel == RXDATA);

    // what the CPU can see and set
    // ctrl
    always_ff @(posedge clk) begin
        if (reset) begin
            uart_en   <= 1'b0;
            baud_div  <= '0;
        end else if (do_req && req_msg.op && (reg_sel == CTRL)) begin
            uart_en   <= req_msg.data[0] && (req_msg.data[16 +: DIV_W] != '0);
            baud_div  <= req_msg.data[16 +: DIV_W];
        end
    end

    // status sticky flags
    logic frame_error_flag, rx_overrun_flag, tx_overflow_flag;

    always_ff @(posedge clk) begin
        if (reset) begin
            frame_error_flag <= 1'b0;
            rx_overrun_flag  <= 1'b0;
            tx_overflow_flag <= 1'b0;
        end else begin
            // write 1 to clear
            if (do_req && req_msg.op && (reg_sel == STATUS)) begin
                if (req_msg.data[5]) frame_error_flag <= 1'b0;
                if (req_msg.data[6]) rx_overrun_flag  <= 1'b0;
                if (req_msg.data[7]) tx_overflow_flag <= 1'b0;
            end

            // a new event in the same cycle wins over the clear
            if (rx_val && frame_err)        frame_error_flag <= 1'b1;
            if (rx_enq_val && !rx_enq_rdy)  rx_overrun_flag  <= 1'b1;
            if (tx_enq_val && !tx_enq_rdy)  tx_overflow_flag <= 1'b1;
        end
    end

    // read data

    logic [BUS_W-1:0] read_data;

    always_comb begin
        read_data = '0;
        case (reg_sel)
            TXDATA: read_data = '0; // write only
            RXDATA: read_data[DATA_W-1:0] = rx_deq_val ? rx_deq_msg : '0;
            STATUS: begin
                read_data[0] = rx_deq_val;
                read_data[1] = !rx_enq_rdy;
                read_data[2] = !tx_deq_val;
                read_data[3] = !tx_enq_rdy;
                read_data[4] = tx_busy;
                read_data[5] = frame_error_flag;
                read_data[6] = rx_overrun_flag;
                read_data[7] = tx_overflow_flag;
            end
            CTRL: begin
                read_data[0]           = uart_en;
                read_data[16 +: DIV_W] = baud_div;
            end
        endcase
    end

    // response, answer

    // echo the request fields back (the router matches responses on opaque)
    always_ff @(posedge clk) begin
        if (reset) begin
            resp_val <= 1'b0;
            resp_msg <= '0;
        end else if (do_req) begin
            resp_val <= 1'b1;
            resp_msg <= {req_msg.op, req_msg.opaque, req_msg.origin,
                         req_msg.addr, req_msg.strb, read_data};
        end else if (resp_rdy) begin
            resp_val <= 1'b0;
        end
    end

endmodule

`endif 