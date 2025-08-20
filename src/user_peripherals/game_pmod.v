/*
 * Copyright (c) 2025 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 *
 * Based on the reference design https://github.com/TinyTapeout/vga-playground/blob/main/src/examples/common/gamepad_pmod.v
 * Copyright (c) 2025 Pat Deegan, https://psychogenic.com
 */

`default_nettype none

/**
 * gamepad_pmod_driver -- Serial interface for the Gamepad Pmod.
 *
 * This module reads raw data from the Gamepad Pmod *serially*
 * and stores it in a shift register. When the latch signal is received, 
 * the data is transferred into `data_reg` for further processing.
 *
 * Functionality:
 *   - Synchronizes the `pmod_data`, `pmod_clk`, and `pmod_latch` signals 
 *     to the system clock domain.
 *   - Captures serial data on each falling edge of `pmod_clk`.
 *   - Transfers the shifted data into `data_reg` when `pmod_latch` goes low.
 *
 * Parameters:
 *   - `BIT_WIDTH`: Defines the width of `data_reg` (default: 24 bits).
 *
 * Inputs:
 *   - `rst_n`: Active-low reset.
 *   - `clk`: System clock.
 *   - `pmod_data`: Serial data input from the Pmod.
 *   - `pmod_clk`: Serial clock from the Pmod.
 *   - `pmod_latch`: Latch signal indicating the end of data transmission.
 *
 * Outputs:
 *   - `data_reg`: Captured parallel data after shifting is complete.
 */
module gamepad_pmod_driver #(
    parameter BIT_WIDTH = 24
) (
    input wire rst_n,
    input wire clk,
    input wire pmod_data,
    input wire pmod_clk,
    input wire pmod_latch,
    output reg [BIT_WIDTH-1:0] data_reg
);

  reg pmod_clk_prev;
  reg pmod_latch_prev;
  reg [BIT_WIDTH-1:0] shift_reg;

  // Sync Pmod signals to the clk domain:
  reg [1:0] pmod_data_sync;
  reg [1:0] pmod_clk_sync;
  reg [1:0] pmod_latch_sync;

  always @(posedge clk) begin
    if (~rst_n) begin
      pmod_data_sync  <= 2'b0;
      pmod_clk_sync   <= 2'b0;
      pmod_latch_sync <= 2'b0;
    end else begin
      pmod_data_sync  <= {pmod_data_sync[0], pmod_data};
      pmod_clk_sync   <= {pmod_clk_sync[0], pmod_clk};
      pmod_latch_sync <= {pmod_latch_sync[0], pmod_latch};
    end
  end

  always @(posedge clk) begin
    if (~rst_n) begin
      /* Initialize data and shift registers to all 1s so they're detected as "not present".
       * This accounts for cases where we have:
       *  - setup for 2 controllers;
       *  - only a single controller is connected; and
       *  - the driver in those cases only sends bits for a single controller.
       */
      data_reg <= {BIT_WIDTH{1'b1}};
      shift_reg <= {BIT_WIDTH{1'b1}};
      pmod_clk_prev <= 1'b0;
      pmod_latch_prev <= 1'b0;
    end
    begin
      pmod_clk_prev   <= pmod_clk_sync[1];
      pmod_latch_prev <= pmod_latch_sync[1];

      // Capture data on rising edge of pmod_latch:
      if (pmod_latch_sync[1] & ~pmod_latch_prev) begin
        data_reg <= shift_reg;
      end

      // Sample data on rising edge of pmod_clk:
      if (pmod_clk_sync[1] & ~pmod_clk_prev) begin
        shift_reg <= {shift_reg[BIT_WIDTH-2:0], pmod_data_sync[1]};
      end
    end
  end

endmodule

// Peripheral for interfacing with the TT Game PMOD
(* keep_hierarchy *)
module tqvp_game_pmod (
    input         clk,
    input         rst_n,

    input  [7:0]  ui_in,        // The input PMOD, always available
    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected

    input [5:0]   address,      // Address within this peripheral's address space
    input [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    
    output [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output        data_ready
);

    reg enable;
    wire [23:0] game_pmod_data;

    gamepad_pmod_driver i_driver(
        .rst_n(rst_n),
        .clk(clk),
        .pmod_data(ui_in[6]),
        .pmod_clk(ui_in[5]),
        .pmod_latch(ui_in[4] & enable),
        .data_reg(game_pmod_data)
    );

    // Enable register at address 0
    always @(posedge clk) begin
        if (!rst_n) begin
            enable <= 0;
        end else begin
            if (address == 6'h0) begin
                if (data_write_n != 2'b11) enable <= data_in[0];
            end
        end
    end

    // All reads complete in 1 clock
    assign data_ready = 1;
    
    // Address 0 reads the enable register.
    // Address 2 reads controller 1 present.
    // Address 3 reads controller 2 present.
    // Address 4 reads controller 1 (half word) or both controllers (word).
    // Address 6 reads controller 2.
    // Address 20-37 reads controller state, one byte per bit (byte reads only).
    // All other addresses read 0.
    wire ctrl1_present = game_pmod_data[11:0] != 12'hfff;
    wire ctrl2_present = game_pmod_data[23:12] != 12'hfff;
    assign data_out = (address == 6'h0) ? {7'h0, ctrl2_present, 7'h0, ctrl1_present, 15'h0, enable} :
                      (address == 6'h2) ? {23'h0, ctrl2_present, 7'h0, ctrl1_present} :
                      (address == 6'h3) ? {31'h0, ctrl2_present} :
                      (address == 6'h4) ? {4'h0, game_pmod_data[23:12], 4'h0, game_pmod_data[11:0]} :
                      (address == 6'h6) ? {20'h0, game_pmod_data[23:12]} :
                      (address[5] == 1'b1) ? {31'h0, game_pmod_data[address[4:0]]} :
                      32'h0;

    // Outputs are unused but must be driven
    assign uo_out = 0;

    // List all unused inputs to prevent warnings
    // data_read_n is unused as none of our behaviour depends on whether
    // registers are being read.
    wire _unused = &{data_read_n, data_in[31:1], ui_in[7], ui_in[3:0], 1'b0};

endmodule
