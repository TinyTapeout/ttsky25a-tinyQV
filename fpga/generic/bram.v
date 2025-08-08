// Loosely based on https://tinlethax.wordpress.com/2022/05/07/ice40-bram-101-probably-the-correct-way-to-use-ice40-block-ram/

module BRAM #(parameter ADDR_WIDTH = 10, parameter INIT_FILE="") (
	input clk,
	
	input [7:0] data_in,
	output reg [7:0] data_out,
	
	input [ADDR_WIDTH-1:0] addr,
	
	input wen,   // Write Enable
	input ren    // Read enable
);

    reg [7:0] mem [0:(1 << ADDR_WIDTH)-1];// This reg will be inferred as BRAM by Yosys.
    integer i;

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
        else
            for(i = 0; i < (1 << ADDR_WIDTH); i++)
                mem[i] <= 8'd0;
    end

    always@(posedge clk) begin
        if(ren) 
            data_out <= mem[addr];	
            
        if(wen) 
            mem[addr] <= data_in;
    end	

endmodule
