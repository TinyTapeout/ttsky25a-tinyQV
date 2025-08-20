/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 38 and change tqvp_example to your chosen module name.
(* keep_hierarchy *)
module tqvp_matt_pwm (
    input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input         rst_n,        // Reset_n - low to reset.

    input  [7:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                // Note that uo_out[0] is normally used for UART TX.

    input [3:0]   address,      // Address within this peripheral's address space

    input         data_write,   // Data write request from the TinyQV core.
    input [7:0]   data_in,      // Data in to the peripheral, valid when data_write is high.
    
    output [7:0]  data_out      // Data out from the peripheral, set this in accordance with the supplied address
);

    reg [7:0] pwm_0;
    reg [7:0] pwm_1;
    reg [7:0] strobe_period;
    wire pwm_out_0, pwm_out_1, pwm_strobe;
    wire reset = ! rst_n;

    // Implement an 8-bit read/write register at address 0->2
    always @(posedge clk) begin
        if (!rst_n) begin
            pwm_0 <= 0;
            pwm_1 <= 0;
	    strobe_period <= 0;
        end else begin
            if (address == 4'h0) begin
                if (data_write) pwm_0 <= data_in;
	    end else if (address == 4'h1) begin
                if (data_write) pwm_1 <= data_in;
	    end else if (address == 4'h2) begin
                if (data_write) strobe_period <= data_in;
            end
        end
    end

    // All output pins must be assigned. Assign them all for greater
    // flexibility with the TinyQV mux.
    assign uo_out  = {pwm_out_0, pwm_out_1, pwm_out_0, pwm_out_1, pwm_out_0, pwm_out_1, pwm_out_0, pwm_out_1};

    // Address 0 reads the pwm0 data register.  
    // Address 1 reads the pwm1 data register.
    // Address 2 reads the strobe period
    // All other addresses read 0.
    assign data_out = (address == 4'h0) ? pwm_0 :
                      (address == 4'h1) ? pwm_1 :
                      (address == 4'h2) ? strobe_period :
                      8'h0;    
    // strobe gen, generates a strobe every strobe_period + 1 clock cycles
    pwm_strobe_gen #(.WIDTH(16))  pwm_strobe_gen(.clk(clk), .cmp(strobe_period), .reset(reset), .out(pwm_strobe));

    // pwm gen
    pwm        #(.WIDTH(8))   pwm_gen_0(.clk(clk), .reset(reset), .strobe(pwm_strobe), .level(pwm_0), .out(pwm_out_0));
    pwm        #(.WIDTH(8))   pwm_gen_1(.clk(clk), .reset(reset), .strobe(pwm_strobe), .level(pwm_1), .out(pwm_out_1));

endmodule

