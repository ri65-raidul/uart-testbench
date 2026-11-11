
/*
==========================================================================
baud_rate_gen.v
==========================================================================
 - RTL code for the Baud Rate Generator
*/

`ifndef uart_BAUD_RATE_GENERATOR
`define uart_BAUD_RATE_GENERATOR

module uart_BaudRateGenerator #(
    parameter int DIV_W = 16        //divisor width
)
(
    input  logic                clk,    //system clk, 125MHz
    input  logic                reset,  
    input  logic                en,
    input  logic [DIV_W -1 : 0] div,   //clk cycles per tick = f_clk / (16*baud)
    output logic                tick   // 1-cycle strobe at 16x the baud rate

);
    logic [DIV_W -1 : 0] count;
    always_ff @(posedge clk)begin
        if( reset || ~en)begin
            tick  <= 1'b0;
            count <= '0; // so the first reload uses the new div
        end
        else if ( count == '0)begin
            tick  <= 1'b1;
            count <= div - 1'b1;
        end
        else begin
            tick  <= 1'b0;
            count <= count - 1'b1;
        end
    end

endmodule
`endif