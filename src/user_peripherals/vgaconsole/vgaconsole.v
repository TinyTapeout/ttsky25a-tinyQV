/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
module tqvp_cattuto_vgaconsole #(parameter CLOCK_MHZ=64) (
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

    localparam NUM_ROWS = 3;
    localparam NUM_COLS = 10;
    localparam NUM_CHARS = NUM_ROWS * NUM_COLS;
    localparam ROWS_ADDR_WIDTH = $clog2(NUM_ROWS);
    localparam COLS_ADDR_WIDTH = $clog2(NUM_COLS);
    localparam CHARS_ADDR_WIDTH = $clog2(NUM_CHARS);

    localparam REG_BG_COLOR     = 6'h30;
    localparam REG_TEXT_COLOR1  = 6'h31;
    localparam REG_TEXT_COLOR2  = 6'h32;
    localparam REG_VGA          = 6'h3F;

    // Text buffer {1 bit color selector, 7-bit ASCII code}
    reg [7:0] text[0:NUM_CHARS-1];

    reg [5:0] text_color1;  // Text color 1
    reg [5:0] text_color2;  // Text color 2
    reg [5:0] bg_color;     // Background color

    // ----- HOST INTERFACE -----
    
    // Writes (only write lowest 8 bits)
    always @(posedge clk) begin
        if (!rst_n) begin
            bg_color <= 6'b010000;
            text_color1 <= 6'b001100;
            text_color2 <= 6'b110011;
        end else begin
            if (~&data_write_n) begin
                if (address < NUM_CHARS) begin
                    text[address[CHARS_ADDR_WIDTH-1:0]] <= data_in[7:0];
                end else if (address == REG_TEXT_COLOR1) begin
                    text_color1 <= data_in[5:0];
                end else if (address == REG_TEXT_COLOR2) begin
                    text_color2 <= data_in[5:0];
                end else if (address == REG_BG_COLOR) begin
                    bg_color <= data_in[5:0];
                end
            end
        end
    end

    // Register reads
    assign data_out = (&address) ? {29'b0, hsync, vsync, interrupt} : 32'h0;  // REG_VGA

    // All reads complete in 1 clock
    assign data_ready = 1;

    // --- Interrupt handling ---
    reg interrupt;
    assign user_interrupt = interrupt;

    always @(posedge clk) begin
        if (!rst_n) begin
            interrupt <= 0;
        end else begin
            if ((~|y_lo) & (~|y_hi)) begin
                interrupt <= 1;
            end else if ((&address) & (~&data_read_n)) begin  // read REG_VGA
                interrupt <= 0;
            end
        end
    end


    // ----- VGA INTERFACE -----

    localparam [10:0] VGA_WIDTH = 1024;
    localparam [10:0] VGA_HEIGHT = 768;
    localparam [10:0] VGA_FRAME_XMIN = 32;
    localparam [10:0] VGA_FRAME_XMAX = VGA_WIDTH - 32;
    localparam [10:0] VGA_FRAME_YMIN = 128;
    localparam [10:0] VGA_FRAME_YMAX = VGA_FRAME_YMIN + 128 * NUM_ROWS;  // 128 pixels per character row

    // VGA signals
    wire hsync;
    wire vsync;
    wire blank;
    reg [1:0] R;
    reg [1:0] G;
    reg [1:0] B;
    wire [10:0] pix_x;
    wire [10:0] pix_y;
    wire [5:0] y_lo;
    wire [4:0] y_hi;

    // TinyVGA PMOD
    assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

    vga_timing_cc hvsync_gen (
        .clk(clk),
        .rst_n(rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .blank(blank),
        .x_lo(pix_x[4:0]),
        .x_hi(pix_x[10:5]),
        .y_lo(y_lo),
        .y_hi(y_hi)
    );

    assign pix_y = ({6'b0, y_hi} << 5) + ({6'b0, y_hi} << 4) + {5'b0, y_lo};  // pix_y = y_hi * 48 + y_lo
    wire [3:0] y_blk = pix_y[10:7];

    //wire frame_active = ( pix_x >= VGA_FRAME_XMIN && pix_x < VGA_FRAME_XMAX &&
    //                        pix_y >= VGA_FRAME_YMIN && pix_y < VGA_FRAME_YMAX);
    wire valid_x = ~pix_x[10] & (|pix_x[9:5]) & ~(&pix_x[9:5]);
    wire valid_y = ~y_blk[3] & ~y_blk[2] & (y_blk[1] | y_blk[0]);
    wire frame_active = valid_x & valid_y;
 
    // Character pixels are 16x16 squares in the VGA frame.
    // Character glyphs are 5x7 and padded in a 6x8 character box.

    // x position machinery
    reg [6:0] cx96;
    reg [COLS_ADDR_WIDTH-1:0] char_x;
    wire [2:0] rel_x = cx96[6:4];
    wire rel_x_5 = (rel_x == 3'd5);
    wire x_at_reset = (~|pix_x[10:5]) & (&pix_x[4:0]);  // x == VGA_FRAME_XMIN - 1

    always @(posedge clk) begin
        if (x_at_reset) begin
            cx96 <= 0;
            char_x <= 0;
        end else begin
            if (cx96 == 95) begin
                cx96 <= 0;
                char_x <= char_x + 1;
            end else begin
                cx96 <= cx96 + 1;
            end
        end
    end

    // (x,y) character coordinates in NUM_ROWS x NUM_COLS text buffer
    wire [1:0] char_y = frame_active ? (y_blk[1:0] - 2'd1) : 2'd0;

    // Drive character ROM input
    //wire [6:0] char_index = text[char_y * NUM_COLS + char_x];
    wire [4:0] char_addr = ({3'd0, char_y} << 3) + ({3'd0, char_y} << 1) + char_x;  // we hardcode NUM_COLS = 10 to save gates
    wire color_sel;
    wire [6:0] char_index;
    assign {color_sel, char_index} = text[char_addr];

    // Character pixel coordinates relative to the 5x7 glyph padded in a 6x8 character box
    wire [2:0] rel_y = pix_y[6:4];  // remainder of division by 16

    // Character pixel index in the 35-bit wide character ROM (rel_y * 5 + rel_x)
    wire [5:0] offset = ({3'b0, rel_y} << 2) + {3'b0, rel_y} + {3'b0, rel_x};

    // Look up character pixel value in character ROM,
    // handling 1-pixel padding along x and y directions.
    wire padding = (&rel_y) || rel_x_5;
    wire char_pixel = (~padding) & char_data[(frame_active & ~padding) ? offset : 6'd0];

    // Generate RGB signals
    wire pixel_on = frame_active & char_pixel;
    wire [5:0] char_color = color_sel ? text_color2 : text_color1;

    always @(posedge clk) begin
        {B, G, R} <= blank ? 6'b000000 : (pixel_on ? char_color : bg_color);
    end

    // ----- CHARACTER ROM -----

    wire [34:0] char_data;

    char_rom_cc char_rom_inst (
        .address(char_index),
        .data(char_data) 
    );

endmodule
