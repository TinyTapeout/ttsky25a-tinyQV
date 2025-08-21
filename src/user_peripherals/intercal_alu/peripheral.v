/*
 * Copyright (c) 2025 Rebecca G. Bettencourt
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tqvp_rebeccargb_intercal_alu (
    input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input         rst_n,        // Reset_n - low to reset.
    input  [7:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
    output [7:0]  uo_out,       // The output PMOD.  Note that uo_out[0] is normally used for UART TX.
    input [5:0]   address,      // Address within this peripheral's address space
    input [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.
    input [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    output [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output        data_ready
);

    reg [31:0] a;
    reg [31:0] b;
    wire [31:0] f;

    intercal_alu ayayayayayaya(address[5:2], a, b, f);

    always @(posedge clk) begin
        if (!rst_n) begin
            a <= 0;
            b <= 0;
        end else begin
            if (address == 6'h0) begin
                if (data_write_n[1] != data_write_n[0]) a[15:0]  <= data_in[15:0];  // 16-bit or 32-bit access
                if (data_write_n == 2'b10)              a[31:16] <= data_in[31:16]; // 32-bit access
            end else if (address == 6'h2) begin
                if (data_write_n == 2'b01)              a[31:16] <= data_in[15:0];  // 16-bit access
            end else if (address == 6'h4) begin
                if (data_write_n[1] != data_write_n[0]) b[15:0]  <= data_in[15:0];  // 16-bit or 32-bit access
                if (data_write_n == 2'b10)              b[31:16] <= data_in[31:16]; // 32-bit access
            end else if (address == 6'h6) begin
                if (data_write_n == 2'b01)              b[31:16] <= data_in[15:0];  // 16-bit access
            end
        end
    end

    assign uo_out = 0;

    assign data_out = (
        (address[1:0] == 2'b00 && data_read_n[1] != data_read_n[0]) ? f :           // 16-bit or 32-bit access
        (address[1:0] == 2'b10 && data_read_n == 2'b01) ? {16'h0000, f[31:16]} :    // 16-bit access
        32'h0
    );

    assign data_ready = (
        (address[1:0] == 2'b00 && data_read_n[1] != data_read_n[0]) ||              // 16-bit or 32-bit access
        (address[1:0] == 2'b10 && data_read_n == 2'b01)                             // 16-bit access
    );

    // List all unused inputs to prevent warnings
    wire _unused = &{ui_in, 1'b0};

endmodule
