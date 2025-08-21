/*
 * Copyright (c) 2025 Alessandro Vargiu
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tqvp_crc32(
    input wire          clk,
    input wire          rst_n,

    input  wire [7:0]   ui_in,        // unused
    output reg [7:0]    uo_out,       // unused

    input [3:0]         address,      // Address within this peripheral's address space

    input wire          data_write,   // Data write request from the TinyQV core.
    input wire [7:0]    data_in,      // Data in to the peripheral, valid when data_write is high.
    
    output reg [7:0]    data_out      // Data out from the peripheral, set this in accordance with the supplied address
);

    localparam CRC_WIDTH = 32;  
    localparam POLY = 32'hEDB88320; // Standard CRC-32 polynomial, reflected version
    //localparam POLY = 32'h04C11DB7; 

    // Address map
    localparam ADDR_CLEAR           = 4'h0;    // reset computation
    localparam ADDR_COMPUTE         = 4'h1;    // compute CRC on data_in
    localparam ADDR_CRC_BYTE0       = 4'h2;    
    localparam ADDR_CRC_BYTE1       = 4'h3;    
    localparam ADDR_CRC_BYTE2       = 4'h4;    
    localparam ADDR_CRC_BYTE3       = 4'h5;    // Read CRC result bytes

    // Internal registers
    reg [CRC_WIDTH-1:0] crc_buf;
    reg [CRC_WIDTH-1:0] crc_result;

    function [31:0] crc_step(input [31:0] current_crc, input [7:0] data_byte_in);
        integer i;
        reg [31:0] crc;
        begin
            crc = current_crc ^ {24'h0, data_byte_in};
            for (i = 0; i < 8; i = i + 1) begin
                if (crc[0]) begin
                    crc = (crc >> 1) ^ POLY;
                end else begin
                    crc = crc >> 1;
                end
            end
            crc_step = crc;
        end
    endfunction

    // Write transactions
    always @(posedge clk) begin
        if(!rst_n) begin
            crc_buf <= 32'hFFFFFFFF;
        end else begin
            if (data_write) begin
                case (address)
                    ADDR_CLEAR: begin
                        crc_buf <= 32'hFFFFFFFF;
                    end
                    ADDR_COMPUTE: begin
                        crc_buf <= crc_step(crc_buf, data_in);
                    end
                    default: ;
                endcase
            end
        end
    end

    // Read transactions
    always @(*) begin
        case (address)
            ADDR_CRC_BYTE0: data_out = crc_result[7:0];
            ADDR_CRC_BYTE1: data_out = crc_result[15:8];
            ADDR_CRC_BYTE2: data_out = crc_result[23:16];
            ADDR_CRC_BYTE3: data_out = crc_result[31:24];
            default: data_out = 8'h0;
        endcase
    end

    assign crc_result = ~crc_buf;

    // All output pins must be assigned. If not used, assign to 0.
    assign uo_out = 0;

    // List all unused inputs to prevent warnings
    wire _unused = &{ui_in, 1'b0};

endmodule