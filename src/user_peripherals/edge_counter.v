/*
 * Copyright (c) 2025 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

(* keep_hierarchy *)
module tqvp_edge_counter #(
    parameter ADDR_RESET     = 4'h0,  // write = counter ← 0
    parameter ADDR_INCREMENT = 4'h1,  // write = counter ← counter + 1
    parameter ADDR_VALUE     = 4'h2,  // read / write = counter
    parameter ADDR_CFG       = 4'h3,  // read / write = edge-count config
    parameter ADDR_PINS      = 4'h4   // read / write = bitmask of ui_in pins to count edges on
) (
    input clk,
    input rst_n,

    input  [7:0] ui_in,  // ui_in[0] is the edge-detect pin
    output [7:0] uo_out, // 7-segment + DP (see below)

    input [3:0] address,  // peripheral address

    input       data_write,  // strobe: write request
    input [7:0] data_in,     // data bus on write

    output [7:0] data_out  // data bus on read
);

  //----------------------------------------------------------------------
  // Internal registers
  //----------------------------------------------------------------------
  reg  [7:0] counter;
  reg  [1:0] cfg;  // 0 = no count, 1 = rising, 2 = falling
  reg  [7:0] pins;  // bitmask of ui_in pins to count edges on
  reg  [7:0] input_prev;

  //----------------------------------------------------------------------
  // Edge detection (sampled synchronously)
  //----------------------------------------------------------------------
  wire [7:0] input_now = ui_in & pins;
  wire       rising_edge = |{input_now & ~input_prev};
  wire       falling_edge = |{~input_now & input_prev};

  //----------------------------------------------------------------------
  // Main sequential block
  //----------------------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) begin
      counter    <= 8'd0;
      cfg        <= 2'd0;
      pins       <= 8'd1;
      input_prev <= input_now;
    end else begin
      // ---------- register writes ----------
      if (data_write) begin
        case (address)
          ADDR_RESET:     counter <= 8'd0;  // any value ignored
          ADDR_INCREMENT: counter <= counter + 8'd1;  // any value ignored
          ADDR_VALUE:     counter <= data_in;
          ADDR_CFG:       cfg <= data_in[1:0];
          ADDR_PINS:      pins <= data_in;
          default:        ;  // no side-effect
        endcase
      end

      // ---------- edge-driven counting ----------
      if (cfg == 2'd1 && rising_edge) counter <= counter + 8'd1;
      if (cfg == 2'd2 && falling_edge) counter <= counter + 8'd1;

      // remember current input for next cycle
      input_prev <= input_now;
    end
  end

  //----------------------------------------------------------------------
  // Readback mux
  //----------------------------------------------------------------------
  assign data_out =
           (address == ADDR_VALUE) ? counter :
           (address == ADDR_CFG)   ? {6'b0, cfg} :
           (address == ADDR_PINS)  ? pins :
           8'h00;   // ADDR_RESET / ADDR_INCREMENT or undefined addrs

  //----------------------------------------------------------------------
  // 7-segment decoder (common-cathode, bit0 = segment A … bit6 = G)
  //----------------------------------------------------------------------
  reg [6:0] seg;
  always @* begin
    case (counter[3:0])
      4'h0:    seg = 7'b0111111;
      4'h1:    seg = 7'b0000110;
      4'h2:    seg = 7'b1011011;
      4'h3:    seg = 7'b1001111;
      4'h4:    seg = 7'b1100110;
      4'h5:    seg = 7'b1101101;
      4'h6:    seg = 7'b1111101;
      4'h7:    seg = 7'b0000111;
      4'h8:    seg = 7'b1111111;
      4'h9:    seg = 7'b1101111;
      4'hA:    seg = 7'b1110111;
      4'hB:    seg = 7'b1111100;
      4'hC:    seg = 7'b0111001;
      4'hD:    seg = 7'b1011110;
      4'hE:    seg = 7'b1111001;
      default: seg = 7'b1110001;  // 0xF
    endcase
  end

  // DP (uo_out[7]) lights when counter > 0x0F
  assign uo_out = {counter > 8'h0F, seg};  // {DP, G…A}

endmodule
