/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 38 and change tqvp_example to your chosen module name.
(* keep_hierarchy *)
module tqvp_matt_encoder(
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

    // assign the pins
    wire enc0_a = ui_in[0];
    wire enc0_b = ui_in[1];
    wire enc1_a = ui_in[2];
    wire enc1_b = ui_in[3];
    wire enc2_a = ui_in[4];
    wire enc2_b = ui_in[5];
    wire enc3_a = ui_in[6];
    wire enc3_b = ui_in[7];
    wire reset = ! rst_n;

    // internal wires
    wire [7:0] enc0, enc1, enc2, enc3;
    wire enc0_a_db, enc0_b_db, enc1_a_db, enc1_b_db, enc2_a_db, enc2_b_db, enc3_a_db, enc3_b_db;
    wire deb_strobe;

    // Strobe frequency set by first address
    reg [7:0] debounce_cmp;
    always @(posedge clk) begin
        if (!rst_n) begin
            debounce_cmp <= 128;
        end else begin
            if (address == 4'h4) begin
                if (data_write) debounce_cmp <= data_in[7:0];
            end
        end
    end

    // All output pins must be assigned. If not used, assign to 0.
    assign uo_out  = 0;

    // Address 0 to 3 reads encoder 0 to 3
    // All other addresses read 0.
    assign data_out = (address == 4'h0) ? enc0 :
	              (address == 4'h1) ? enc1 :
	              (address == 4'h2) ? enc2 :
	              (address == 4'h3) ? enc3 :
	              (address == 4'h4) ? debounce_cmp :
                      8'h0;  
    // strobe gen
    strobe_gen #(.WIDTH(16))  deb_strobe_gen(.clk(clk), .cmp(debounce_cmp), .reset(reset), .out(deb_strobe));

    // debouncers
    debounce #(.HIST_LEN(8)) debounce0_a(.clk(clk), .strobe(deb_strobe), .reset(reset), .button(enc0_a), .debounced(enc0_a_db));
    debounce #(.HIST_LEN(8)) debounce0_b(.clk(clk), .strobe(deb_strobe), .reset(reset), .button(enc0_b), .debounced(enc0_b_db));
    debounce #(.HIST_LEN(8)) debounce1_a(.clk(clk), .strobe(deb_strobe), .reset(reset), .button(enc1_a), .debounced(enc1_a_db));
    debounce #(.HIST_LEN(8)) debounce1_b(.clk(clk), .strobe(deb_strobe), .reset(reset), .button(enc1_b), .debounced(enc1_b_db));
    debounce #(.HIST_LEN(8)) debounce2_a(.clk(clk), .strobe(deb_strobe), .reset(reset), .button(enc2_a), .debounced(enc2_a_db));
    debounce #(.HIST_LEN(8)) debounce2_b(.clk(clk), .strobe(deb_strobe), .reset(reset), .button(enc2_b), .debounced(enc2_b_db));
    debounce #(.HIST_LEN(8)) debounce3_a(.clk(clk), .strobe(deb_strobe), .reset(reset), .button(enc3_a), .debounced(enc3_a_db));
    debounce #(.HIST_LEN(8)) debounce3_b(.clk(clk), .strobe(deb_strobe), .reset(reset), .button(enc3_b), .debounced(enc3_b_db));

    // encoders
    encoder #(.WIDTH(8)) encoder0(.clk(clk), .reset(reset), .a(enc0_a_db), .b(enc0_b_db), .value(enc0));
    encoder #(.WIDTH(8)) encoder1(.clk(clk), .reset(reset), .a(enc1_a_db), .b(enc1_b_db), .value(enc1));
    encoder #(.WIDTH(8)) encoder2(.clk(clk), .reset(reset), .a(enc2_a_db), .b(enc2_b_db), .value(enc2));
    encoder #(.WIDTH(8)) encoder3(.clk(clk), .reset(reset), .a(enc3_a_db), .b(enc3_b_db), .value(enc3));
endmodule

