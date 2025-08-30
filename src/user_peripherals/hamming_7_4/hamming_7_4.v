/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none
module hamming_74 (
    input clk,
    input rst_n,
    input [7:0] ui_in,
    output [7:0] uo_out,
    input [3:0] address,
    input data_write,
    input [7:0] data_in,
    output [7:0] data_out
);

// Registers for Hamming operations
reg [3:0] data_enc_in;  // Encoder input (4 bits)
reg [6:0] encoded;      // Encoder output (7 bits)
reg [6:0] received;     // Decoder input (7 bits)
reg [3:0] decoded;      // Decoder output (4 bits)
reg [2:0] syndrome;     // Syndrome bits

// Functions for encoder parity calculation
function [2:0] calc_parity;
    input [3:0] data_bits;
    begin
        // Hamming (7,4) encoder:
        // Bit positions: [6:0] = d3, d2, d1, p2, d0, p1, p0
        // Standard Hamming code mapping:
        // Position (1-indexed): 7  6  5  4  3  2  1
        // Bit array (0-indexed): 6  5  4  3  2  1  0
        // Content:              d3 d2 d1 p2 d0 p1 p0
        
        // p0 covers positions 1,3,5,7 (bits 0,2,4,6) = d0, d1, d3
        calc_parity[0] = data_bits[0] ^ data_bits[1] ^ data_bits[3]; 
        // p1 covers positions 2,3,6,7 (bits 1,2,5,6) = d0, d2, d3
        calc_parity[1] = data_bits[0] ^ data_bits[2] ^ data_bits[3];
        // p2 covers positions 4,5,6,7 (bits 3,4,5,6) = d1, d2, d3
        calc_parity[2] = data_bits[1] ^ data_bits[2] ^ data_bits[3];
    end
endfunction

// Functions for decoder operations
function [2:0] calc_syndrome;
    input [6:0] recv_data;
    begin
        // recv_data[6:0] = {d3, d2, d1, p2, d0, p1, p0}
        // Check each parity bit
        calc_syndrome[0] = recv_data[0] ^ recv_data[2] ^ recv_data[4] ^ recv_data[6]; // Check p0
        calc_syndrome[1] = recv_data[1] ^ recv_data[2] ^ recv_data[5] ^ recv_data[6]; // Check p1  
        calc_syndrome[2] = recv_data[3] ^ recv_data[4] ^ recv_data[5] ^ recv_data[6]; // Check p2
    end
endfunction

function [6:0] correct_errors;
    input [6:0] recv_data;
    input [2:0] syndrome_val;
    begin
        correct_errors = recv_data;
        case (syndrome_val)
            3'b001: correct_errors[0] = ~recv_data[0]; // Error at position 1 (p0)
            3'b010: correct_errors[1] = ~recv_data[1]; // Error at position 2 (p1)  
            3'b011: correct_errors[2] = ~recv_data[2]; // Error at position 3 (d0)
            3'b100: correct_errors[3] = ~recv_data[3]; // Error at position 4 (p2)
            3'b101: correct_errors[4] = ~recv_data[4]; // Error at position 5 (d1)
            3'b110: correct_errors[5] = ~recv_data[5]; // Error at position 6 (d2)
            3'b111: correct_errors[6] = ~recv_data[6]; // Error at position 7 (d3)
            default: correct_errors = recv_data;       // No error (syndrome = 000)
        endcase
    end
endfunction

function [3:0] extract_data;
    input [6:0] corrected_data;
    begin
        // Extract data bits {d3, d2, d1, d0} from corrected: {d3, d2, d1, p2, d0, p1, p0}
        extract_data = {corrected_data[6], corrected_data[5], corrected_data[4], corrected_data[2]};
    end
endfunction

// Wire declarations for combinational calculations
wire [2:0] parity_bits = calc_parity(data_in[3:0]);
wire [2:0] syndrome_calc = calc_syndrome(data_in[6:0]);
wire [6:0] corrected_data = correct_errors(data_in[6:0], syndrome_calc);
wire [3:0] extracted_data = extract_data(corrected_data);

// Register updates
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_enc_in <= 4'b0;
        encoded <= 7'b0;
        received <= 7'b0;
        decoded <= 4'b0;
        syndrome <= 3'b0;
    end else begin
        // Write to encoder input register
        if (data_write && address == 4'h0) begin
            data_enc_in <= data_in[3:0];
            // Update encoded output using new data: {d3, d2, d1, p2, d0, p1, p0}
            encoded <= {data_in[3], data_in[2], data_in[1], parity_bits[2], 
                       data_in[0], parity_bits[1], parity_bits[0]};
        end
        
        // Write to decoder input register
        if (data_write && address == 4'h3) begin
            received <= data_in[6:0];
            syndrome <= syndrome_calc;
            decoded <= extracted_data;
        end
    end
end

// Read operations
assign data_out = (address == 4'h0) ? {4'b0, data_enc_in} :     // Read encoder input
                  (address == 4'h1) ? {1'b0, encoded} :         // Read encoded
                  (address == 4'h2) ? {1'b0, received} :        // Read received
                  (address == 4'h3) ? {4'b0, decoded} :         // Read decoded
                  (address == 4'h4) ? {5'b0, syndrome} :        // Read syndrome
                  8'h0;

// Connect ui_in to uo_out (or you can modify this based on your requirements)
assign uo_out = ui_in;

endmodule