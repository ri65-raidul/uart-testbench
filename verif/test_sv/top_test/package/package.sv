//=========================================================================
// Package for UART
//=========================================================================

package uart_verif_pkg;

    // Localaparams for UART (copied from the rtl)
    localparam int nbits = 79; 
    localparam int DATA_W = 8; 

    // Typedefs
    typedef logic [nbits-1:0] uart_msg_t;
    typedef logic [DATA_W-1:0] uart_byte_t;

    typedef struct packed {
        logic           op;     // 1'
        logic [7:0]     opaque; // 8'
        logic [1:0]     origin; // 2'
        logic [31:0]    addr;   // 32'
        logic [3:0]     strb;   // 4'
        logic [31:0]    data;   // 32'
    } msg_t;    // 79 bit msg struct
    
    // Transaction class for the UART request
    class uart_req;

        rand uart_msg_t msg;

        // Print transaction
        function void print(string tag = "");
            $display("T=%0t [%s] req msg=0x%0h", $time, tag, msg);
        endfunction

    endclass

    // Transaction class for the UART response
    class uart_resp;

        uart_msg_t msg;

        // Print transaction
        function void print(string tag = "");
            $display("T=%0t [%s] resp msg=0x%0h", $time, tag, msg);
        endfunction

    endclass

    // Class for each UART frame
    class uart_frame;

        rand uart_byte_t data;
        rand bit          frame_err; // monitor: stop bit was bad
        
        // Print transaction
        function void print(string tag = "");
            $display("T=%0t [%s] data=0x%0h, frame_err=%0b", 
            $time, tag, data, frame_err);
        endfunction

    endclass

endpackage