/*
 * Copyright (c) 2025 Riya and Anoushka
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

(* keep_hierarchy *)
module tqvp_spike (
  input wire clk,
  input wire rst_n,

  input wire [7:0] ui_in,      // Pixel intensity input
  output reg [7:0] uo_out,     // Spike output + spike count MSBs

  input wire [3:0] address,    // Peripheral register address
  input wire data_write,       // Write strobe
  input wire [7:0] data_in,    // Data to write
  output reg [7:0] data_out    // Data to read
);

  // Registers
  reg [7:0] pixel_reg;        // Current pixel value
  reg [7:0] prev_pixel_reg;   // Previous pixel value
  reg [7:0] threshold_reg;    // Edge detection threshold
  reg spike_reg;              // Spike flag
  reg [7:0] spike_count;      // Count of detected spikes

  // Address map
  localparam ADDR_PIXEL     = 4'h0;
  localparam ADDR_THRESHOLD = 4'h1;
  localparam ADDR_SPIKE     = 4'h2;
  localparam ADDR_COUNT     = 4'h3;

  // Compute absolute difference
  wire [7:0] diff = (pixel_reg > prev_pixel_reg) ?
                    (pixel_reg - prev_pixel_reg) :
                    (prev_pixel_reg - pixel_reg);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pixel_reg      <= 8'd0;
      prev_pixel_reg <= 8'd0;
      threshold_reg  <= 8'd20; // Default threshold
      spike_reg      <= 1'b0;
      spike_count    <= 8'd0;
      uo_out         <= 8'd0;
    end else begin
      // Write to registers
      if (data_write) begin
        case (address)
          ADDR_PIXEL:     pixel_reg <= data_in;      // Input pixel
          ADDR_THRESHOLD: threshold_reg <= data_in;  // Set threshold
          default: ;
        endcase
      end

      // Save previous pixel
      prev_pixel_reg <= pixel_reg;

      // Edge detection: compare difference to threshold
      if (diff >= threshold_reg)
        spike_reg <= 1'b1;
      else
        spike_reg <= 1'b0;

      // Count spikes
      if (spike_reg)
        spike_count <= spike_count + 1;

      // Output: spike on bit 0, spike count on bits [7:1]
      uo_out[0]   <= spike_reg;
      uo_out[7:1] <= spike_count[7:1];
    end
  end

  // Readback logic
  always @(*) begin
    case (address)
      ADDR_PIXEL:     data_out = pixel_reg;
      ADDR_THRESHOLD: data_out = threshold_reg;
      ADDR_SPIKE:     data_out = {7'd0, spike_reg};
      ADDR_COUNT:     data_out = spike_count;
      default:        data_out = 8'd0;
    endcase
  end

endmodule
