/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
module tqvp_trng_kietdang (
    input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input         rst_n,        // Reset_n - low to reset.

    input  [7:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                // Note that uo_out[0] is normally used for UART TX.

    input [5:0]   address,      // Address within this peripheral's address space
    input [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    
    output [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output        data_ready,

    output        user_interrupt  // Dedicated interrupt request for this peripheral
);

    // Implement a 32-bit read/write register at address 0
    reg [31:0] r_data_addr_0; // CONTROL REGISTER[3:0] -> READ[4] | CALIB[3] | SEL_BASE[2] | EN[1] | RST[0]
    reg [31:0] r_data_addr_1; // STATUS REGISTER
    reg [31:0] r_data_addr_2; // CALIBRATION CYCLES REGISTER
    reg [31:0] r_data_addr_3; // I1 REGISTER
    reg [31:0] r_data_addr_4; // I2 REGISTER
    reg [31:0] r_data_addr_5; // TRIGGER REGISTER
    reg [31:0] r_data_addr_6; // CLK DIVISION REGISTER


    // Instantiate the dual_trng module
    wire [31:0] random_number;
    wire ready_signal;
    dual_trng trng_inst (
        .iClk(clk),
        .iRst(~rst_n | r_data_addr_0[0]),     // Reset if rst_n is low or RST bit is set
        .iEn(r_data_addr_0[1]),               // Enable controlled by EN bit
        .iClk_div_factor(r_data_addr_6),       // Clock division factor
        .iCalib(r_data_addr_0[3]),            // Calibration control
        .iCalib_cycles(r_data_addr_2),        // Calibration cycles
        .iTrigger(r_data_addr_5[23:0]),       // Trigger input
        .iI1(r_data_addr_3[23:0]),            // I1 input
        .iI2(r_data_addr_4[23:0]),            // I2 input
        .iSel_base(r_data_addr_0[2]),         // Select long base (0 for long, 1 for short)
        .iRead(r_data_addr_0[4]),             // Read request
        .oReady(ready_signal),                // Ready signal
        .oRandom(random_number)               // Random number output
    );


    // Input handling for the registers
    always @(posedge clk) begin
        if (!rst_n) begin
            r_data_addr_0 <= 0;
            r_data_addr_1 <= 0;
            r_data_addr_2 <= 0;
            r_data_addr_3 <= 0;
            r_data_addr_4 <= 0;
            r_data_addr_5 <= 0;
            r_data_addr_6 <= 1; // Default clock division factor
        end else begin
            if (address == 6'h0) begin
                if (data_write_n != 2'b11)              r_data_addr_0[7:0]   <= data_in[7:0];
                if (data_write_n[1] != data_write_n[0]) r_data_addr_0[15:8]  <= data_in[15:8];
                if (data_write_n == 2'b10)              r_data_addr_0[31:16] <= data_in[31:16];
            end
            if (address == 6'h1) begin
                if (data_write_n != 2'b11)              r_data_addr_1[7:0]   <= data_in[7:0];
                if (data_write_n[1] != data_write_n[0]) r_data_addr_1[15:8]  <= data_in[15:8];
                if (data_write_n == 2'b10)              r_data_addr_1[31:16] <= data_in[31:16];
            end
            if (address == 6'h2) begin
                if (data_write_n != 2'b11)              r_data_addr_2[7:0]   <= data_in[7:0];
                if (data_write_n[1] != data_write_n[0]) r_data_addr_2[15:8]  <= data_in[15:8];
                if (data_write_n == 2'b10)              r_data_addr_2[31:16] <= data_in[31:16];
            end
            if (address == 6'h3) begin
                if (data_write_n != 2'b11)              r_data_addr_3[7:0]   <= data_in[7:0];
                if (data_write_n[1] != data_write_n[0]) r_data_addr_3[15:8]  <= data_in[15:8];
                if (data_write_n == 2'b10)              r_data_addr_3[31:16] <= data_in[31:16];
            end
            if (address == 6'h4) begin
                if (data_write_n != 2'b11)              r_data_addr_4[7:0]   <= data_in[7:0];
                if (data_write_n[1] != data_write_n[0]) r_data_addr_4[15:8]  <= data_in[15:8];
                if (data_write_n == 2'b10)              r_data_addr_4[31:16] <= data_in[31:16];
            end
            if (address == 6'h5) begin
                if (data_write_n != 2'b11)              r_data_addr_5[7:0]   <= data_in[7:0];
                if (data_write_n[1] != data_write_n[0]) r_data_addr_5[15:8]  <= data_in[15:8];
                if (data_write_n == 2'b10)              r_data_addr_5[31:16] <= data_in[31:16];
            end
            if (address == 6'h6) begin
                if (data_write_n != 2'b11)              r_data_addr_6[7:0]   <= data_in[7:0];
                if (data_write_n[1] != data_write_n[0]) r_data_addr_6[15:8]  <= data_in[15:8];
                if (data_write_n == 2'b10)              r_data_addr_6[31:16] <= data_in[31:16];
            end
        end
    end

    // The bottom 8 bits of the stored data are added to ui_in and output to uo_out.
    assign uo_out = r_data_addr_0[7:0] + ui_in;

    // Address 0 reads the example data register.  
    // Address 4 reads ui_in
    // All other addresses read 0.
    assign data_out = (address == 6'h0) ? r_data_addr_0 :
                    (address == 6'h1) ? {r_data_addr_1[31:1], ready_signal} :
                    (address == 6'h2) ? r_data_addr_2 :
                    (address == 6'h3) ? r_data_addr_3 :
                    (address == 6'h4) ? r_data_addr_4 :
                    (address == 6'h5) ? r_data_addr_5 :
                    (address == 6'h6) ? r_data_addr_6 :
                    (address == 6'h7) ? random_number :
                    32'h0;

    // All reads complete in 1 clock
    assign data_ready = 1;
    
    // User interrupt is generated on rising edge of ui_in[6], and cleared by writing a 1 to the low bit of address 8.
    // reg example_interrupt;
    // reg last_ui_in_6;

    // always @(posedge clk) begin
    //     if (!rst_n) begin
    //         example_interrupt <= 0;
    //     end

    //     if (ui_in[6] && !last_ui_in_6) begin
    //         example_interrupt <= 1;
    //     end else if (address == 6'h8 && data_write_n != 2'b11 && data_in[0]) begin
    //         example_interrupt <= 0;
    //     end

    //     last_ui_in_6 <= ui_in[6];
    // end

    // assign user_interrupt = example_interrupt;
    assign user_interrupt = 1'b0; // Disable user interrupt for now, as this design does not use it.

    // List all unused inputs to prevent warnings
    // data_read_n is unused as none of our behaviour depends on whether
    // registers are being read.
    wire _unused = &{data_read_n, 1'b0};

endmodule
