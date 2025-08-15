module entropy_cell(
input T,
input I1,
input I2,
output oEntropy
);

/* Implementation of XOR-latch cell */
wire xor_top;
wire xor_bottom;
wire and_top;
wire and_bottom;

assign xor_top = I1 ^ and_bottom;
assign and_top = T & xor_top;
assign xor_bottom = I2 ^ and_top;
assign and_bottom = T & xor_bottom;

assign oEntropy = and_top;
/* ----------------------------------*/



/* Use the code below to run the test.py */
// wire iEn = T & I1 & ~I2; // Enable signal for the entropy cell
// assign oEntropy = (iEn)? 1'b1 : 1'b0; // Output is high when enabled

endmodule