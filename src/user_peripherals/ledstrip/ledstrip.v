/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 38 and change tqvp_example to your chosen module name.
(* keep_hierarchy *)
module tqvp_cattuto_ws2812b_driver #(parameter CLOCK_MHZ=64) (
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

    localparam REG_CTRL=4'h0, REG_R=4'h1, REG_G=4'h2, REG_B=4'h3, REG_CHAR=4'h4;
    localparam CHAR_LEDS = 5 * 7; // 5x7 char matrix

    reg valid;
    reg will_latch;
    reg clear;
    reg use_rom;
    reg ready;
    reg [23:0] color;
    reg [5:0] counter; 

    wire pixel_val;
    assign pixel_val = char_data[counter - 1];
    assign ledstrip_data = ((~use_rom & ~clear) | (use_rom & pixel_val)) ? color : 24'h0;

    wire latch;
    assign latch = (counter == 1) ? will_latch : 0;

    assign ledstrip_valid = valid;
    assign ledstrip_latch = latch;

    // write to peripheral
    always @(posedge clk) begin
        if (!rst_n) begin
            ready <= 1;
            will_latch <= 0;
            counter <= 0;
            valid <= 0;
            color <= 24'h002000;
            clear <= 0;
            use_rom <= 0;
            char_index <= 0;
        end else begin
            if (ready & data_write) begin
                case (address)
                    REG_CTRL: begin
                        will_latch <= data_in[7];
                        clear <= data_in[6];
                        counter <= data_in[5:0];
                        use_rom <= 0;
                        ready <= 0;
                    end
                    
                    REG_R: begin
                        color[15:8] <= data_in;
                    end

                    REG_G: begin
                        color[23:16] <= data_in;
                    end

                    REG_B: begin
                        color[7:0] <= data_in;
                    end

                    REG_CHAR: begin
                        will_latch <= data_in[7];
                        counter <= CHAR_LEDS;
                        char_index <= data_in[6:0];
                        use_rom <= 1;
                        ready <= 0;
                    end

                    default: begin
                    end
                endcase
            end else begin
                if (!ledstrip_ready) begin
                    valid <= 0;
                    if (valid) begin
                        counter <= counter - 1;
                    end
                end else begin
                    valid <= (counter > 0);
                    ready <= (counter == 0);
                end
            end
        end
    end

    // All output pins must be assigned. If not used, assign to 0.
    assign uo_out[0] = 0;
    assign uo_out[7:2] = 0;
    assign uo_out[1] = ledstrip;

    // read from peripheral
    assign data_out = {7'b0, ready};
    
    // -------------- WS2812B LED STRIP ---------------------------

    wire [23:0] ledstrip_data;
    wire ledstrip_valid;
    wire ledstrip_latch;
    wire ledstrip_ready;
    wire ledstrip;

    ws2812b #(.CLOCK_MHZ(CLOCK_MHZ)) ws2812b_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(ledstrip_data),
        .valid(ledstrip_valid),
        .latch(ledstrip_latch),
        .ready(ledstrip_ready),
        .led(ledstrip)  // output signal to the LED strip
    );

    // -------------- CHARACTER ROM ---------------------------

    reg [6:0] char_index;
    wire [34:0] char_data;

    char_rom #(.DATA_WIDTH(CHAR_LEDS), .ADDR_WIDTH(7)) char_rom_inst (
        .address(char_index),
        .data(char_data) 
    );

endmodule
