// Copyright (c) 2025 Meinhard Kissich
// SPDX-License-Identifier: MIT
// -----------------------------------------------------------------------------
// File  :  peripheral.sv
// Usage :  SSD1306 OLED logic analyzer / waveform plotter
//
// -----------------------------------------------------------------------------

`default_nettype none

(* keep_hierarchy *)
module tqvp_meiniKi_waveforms (
    input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input         rst_n,        // Reset_n - low to reset.

    /* verilator lint_off UNUSEDSIGNAL */
    input  [7:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.
    /* verilator lint_on UNUSEDSIGNAL */
    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                // Note that uo_out[0] is normally used for UART TX.

    input [3:0]   address,      // Address within this peripheral's address space

    input         data_write,   // Data write request from the TinyQV core.
    input [7:0]   data_in,      // Data in to the peripheral, valid when data_write is high.
    
    output [7:0]  data_out      // Data out from the peripheral, set this in accordance with the supplied address
);

  localparam CPOL = 0;

  // See documentation
  localparam CMD_DATA     = 5'b1_0000;
  localparam CMD_SPI      = 5'b1_0001;
  localparam CMD_DC_PRESC = 5'b1_0010;
  localparam CMD_SEL      = 5'b1_1000;
  //

  enum int unsigned { IDLE, SPI_TX, SEL, SEL_DONE, PIXEL, HEADER, PULL_DC } state_r, state_n, state_cont_r, state_cont_n;

  logic sck_r;
  logic tick;
  logic done;

  logic cs_r, cs_n;
  logic conf_gnd_r, conf_gnd_n;
  logic conf_header_r, conf_header_n;

  logic oled_dc_r, oled_dc_n;

  logic [7:0] tx_r, tx_n;

  logic [3:0] presc_r, presc_n;
  logic [3:0] cnt_presc_r, cnt_presc_n;
  logic [4:0] cnt_hbit_r, cnt_hbit_n;
  logic [7:0] bfr_r, bfr_n;
  logic [3:0] cnt_px_r, cnt_px_n;
  logic [2:0] header_cnt_r, header_cnt_n;

  assign uo_out[0]    = 1'b0;
  assign uo_out[1]    = sck_r;
  assign uo_out[2]    = tx_r[7];
  assign uo_out[3]    = cs_r & (state_r != SPI_TX) & (state_n != SPI_TX);
  assign uo_out[4]    = oled_dc_r;
  assign uo_out[7:5]  = 'b0;

  assign tick         = (~|cnt_presc_r);
  assign done         = (state_r == SPI_TX) & (state_n != SPI_TX);
  assign data_out     = {7'b0, state_r == IDLE};

  logic [7:0] rom_data;

  font_rom i_font_rom (
    .digit  ( bfr_r[2:0]    ), 
    .column ( header_cnt_r  ),
    .data   ( rom_data  )
  );

  always_comb begin
    tx_n          = tx_r;
    state_n       = state_r;
    cnt_presc_n   = cnt_presc_r - 'b1;
    presc_n       = presc_r;
    cnt_hbit_n    = cnt_hbit_r;
    oled_dc_n     = oled_dc_r;
    cs_n          = cs_r;
    state_cont_n  = state_cont_r;
    bfr_n         = bfr_r;
    header_cnt_n  = header_cnt_r;
    cnt_px_n      = cnt_px_r;
    conf_gnd_n    = conf_gnd_r;
    conf_header_n = conf_header_r;

    case(state_r)
      IDLE: begin
        bfr_n       = data_in;
        cnt_presc_n = presc_r;
        cnt_hbit_n  = 'd16;

        casez({data_write, address})
          CMD_DC_PRESC: begin
            presc_n       = data_in[3:0];
            oled_dc_n     = data_in[4];
            cs_n          = data_in[5];
            conf_gnd_n    = data_in[6];
            conf_header_n = data_in[7];
          end

          CMD_SPI: begin
            tx_n          = data_in;
            state_n       = SPI_TX;
            state_cont_n  = IDLE;
          end

          CMD_SEL: begin
            state_n = SEL;
            cnt_presc_n = presc_r;
          end

          CMD_DATA: begin
            cnt_px_n = 'd8;
            state_n = PIXEL;
          end
          default: begin end
        endcase

      end
      // ---
      SEL: begin
        oled_dc_n     = 1'b0;
        tx_n          = {5'b10110, bfr_r[2:0]};
        cnt_hbit_n    = 'd16;
        header_cnt_n  = 'b0;
        state_cont_n  = SEL_DONE;
        cnt_px_n = 'd8;
        if (tick) begin
          state_n = SPI_TX;
          cnt_presc_n = presc_r;
        end

      end
      // ---
      SEL_DONE: begin
        oled_dc_n    = 1'b1;
        state_cont_n = IDLE;
        if (conf_header_r)  state_n = HEADER;
        else                state_n = IDLE;
      end
      // ---
      HEADER: begin
        cnt_presc_n = presc_r;
        cnt_hbit_n  = 'd16;
        cnt_px_n = 'd8;
        header_cnt_n = header_cnt_r + 'b1;

        if (~&header_cnt_r) begin
          state_n       = SPI_TX;
          state_cont_n  = HEADER;
          tx_n          = rom_data | {conf_gnd_r, 7'b0};
        end else begin
          state_n       = IDLE;
          state_cont_n  = IDLE;
        end
      end
      // ---
      PIXEL: begin
        cnt_presc_n = presc_r;
        cnt_hbit_n  = 'd16;
        cnt_px_n = cnt_px_r - 'b1;

        if (|cnt_px_r) begin
          state_n       = SPI_TX;
          state_cont_n  = PIXEL;
          bfr_n         = bfr_r << 1;
          if (bfr_r[7]) tx_n = {conf_gnd_r, 7'h02};
          else          tx_n = {conf_gnd_r, 7'h20};
        end else begin
          state_cont_n  = IDLE;
          state_n       = IDLE;
        end

      end
      // ---
      SPI_TX: begin
        if (tick) begin
          cnt_presc_n = presc_r;
          cnt_hbit_n = cnt_hbit_r - 'b1;

          if (~|(cnt_hbit_r - 'b1)) begin
            state_n = state_cont_r;
          end

          if (cnt_hbit_r[0]) begin
            tx_n        = tx_r << 1;
          end
        end
      end
      // ---
      PULL_DC: begin
        oled_dc_n     = 1'b1;
        state_cont_n  = IDLE;
        state_n       = IDLE;
      end

    endcase
  end



always_ff @(posedge clk) begin
  presc_r       <= presc_n;
  cnt_presc_r   <= cnt_presc_n;
  cnt_hbit_r    <= cnt_hbit_n;
  oled_dc_r     <= oled_dc_n;
  cs_r          <= cs_n;
  state_cont_r  <= state_cont_n;
  bfr_r         <= bfr_n;
  cnt_px_r      <= cnt_px_n;
  tx_r          <= tx_n;
  conf_gnd_r    <= conf_gnd_n;
  conf_header_r <= conf_header_n;
  header_cnt_r  <= header_cnt_n;

  if (~rst_n) begin
    state_r       <= IDLE;
    sck_r         <= CPOL;
    presc_r       <= 4'b100;
    cnt_hbit_r    <= 'b0;
    cs_r          <= 'b1;
    oled_dc_r     <= 'b0;
    state_cont_r  <= IDLE;
    bfr_r         <= 'b0;
    conf_gnd_r    <= 'b0;
    conf_header_r <= 'b0;
  end else begin
    state_r     <= state_n;
    // SCK
    if (state_r == IDLE)  sck_r <= CPOL;
    else if (tick)        sck_r <= done ? CPOL : ~sck_r;
    else                  sck_r <= sck_r;
  end
end


endmodule

