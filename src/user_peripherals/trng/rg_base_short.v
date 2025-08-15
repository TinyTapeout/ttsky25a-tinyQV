//-----Ring Generator Base primitive polynomial-----
// x^16 + x^10 + x^7 + x^4 + 1

module rg_base_short(
  input         iClk,
  input         iRst,
  input         iEn,
  input  [7:0]  iEntropy,
  output        oSerial
);

reg [15:0] state;
wire [15:0] next_state;

assign oSerial = state[0];

// Compute next state combinationally
assign next_state[0] = state[1] ^ iEntropy[0];
assign next_state[1] = state[2] ^ iEntropy[1];
assign next_state[2] = state[3];
assign next_state[3] = state[4];
assign next_state[4] = state[5] ^ iEntropy[2];
assign next_state[5] = state[6];
assign next_state[6] = state[7] ^ iEntropy[3];
assign next_state[7] = state[8];                   
assign next_state[8] = state[9] ^ iEntropy[4];
assign next_state[9] = state[10] ^ state[6];
assign next_state[10] = state[11] ^ state[4];
assign next_state[11] = state[12] ^ iEntropy[5];                  
assign next_state[12] = state[13] ^ state[3];
assign next_state[13] = state[14] ^ iEntropy[6];
assign next_state[14] = state[15] ^ iEntropy[7];                  
assign next_state[15] = state[0];

// Single clocked process for state update
always @(posedge iClk) begin
    if (iRst) begin
        state <= 16'h0; // Reset state to zero - iEntropy will break the non-zero state
    end 
    else if (iEn) begin
        state <= next_state;
    end
end
    
endmodule
