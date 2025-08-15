//-----Ring Generator Base primitive polynomial-----
// x^32 + x^25 + x^15 + x^7 + 1
module rg_base_long(
  input         iClk,
  input         iRst,
  input         iEn,
  input  [23:0] iEntropy,
  output        oSerial
);
  reg [31:0] state;
  wire [31:0] next_state;

  assign oSerial = state[0];

  // Compute next state combinationally
  assign next_state[0]  = state[1] ^ iEntropy[23];
  assign next_state[1]  = state[2] ^ iEntropy[22];
  assign next_state[2]  = state[3];
  assign next_state[3]  = state[4] ^ iEntropy[21];
  assign next_state[4]  = state[5] ^ iEntropy[20];
  assign next_state[5]  = state[6] ^ iEntropy[19];
  assign next_state[6]  = state[7] ^ iEntropy[18];
  assign next_state[7]  = state[8];                    // Polynomial tap at position 7
  assign next_state[8]  = state[9] ^ iEntropy[17];
  assign next_state[9]  = state[10] ^ iEntropy[16];
  assign next_state[10] = state[11] ^ iEntropy[15];
  assign next_state[11] = state[12];
  assign next_state[12] = state[13] ^ iEntropy[14];
  assign next_state[13] = state[14] ^ iEntropy[13];
  assign next_state[14] = state[15] ^ iEntropy[12];
  assign next_state[15] = state[16];                   // Polynomial tap at position 15
  assign next_state[16] = state[17] ^ iEntropy[11];
  assign next_state[17] = state[18] ^ iEntropy[10];
  assign next_state[18] = state[19] ^ state[12];       // Feedback from tap 12
  assign next_state[19] = state[20] ^ iEntropy[9];
  assign next_state[20] = state[21] ^ iEntropy[8];
  assign next_state[21] = state[22] ^ iEntropy[7];
  assign next_state[22] = state[23] ^ state[8];        // Feedback from tap 8
  assign next_state[23] = state[24] ^ iEntropy[6];
  assign next_state[24] = state[25] ^ iEntropy[5];
  assign next_state[25] = state[26] ^ iEntropy[4];     // Polynomial tap at position 25
  assign next_state[26] = state[27] ^ iEntropy[3];
  assign next_state[27] = state[28] ^ state[3];        // Feedback from tap 3
  assign next_state[28] = state[29] ^ iEntropy[2];
  assign next_state[29] = state[30] ^ iEntropy[1];
  assign next_state[30] = state[31] ^ iEntropy[0];
  assign next_state[31] = state[0];                    // Shift register feedback

  // Single clocked process for state update
  always @(posedge iClk) begin
    if (iRst) begin
      state <= 32'h0; // Reset state to zero - iEntropy will break the non-zero state
    end 
    else if (iEn) begin
      state <= next_state;
    end
  end

endmodule