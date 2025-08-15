// -----------------------------------------------------------------------------
// dual_trng.v  -  Simple sampler for 32-bit words from one of two TRNG bases
// Behavior:
//   1) Select base with iSel_base (0=long, 1=short)
//   2) Pulse iCalib -> enable selected base for iCalib_cycles clocks
//   3) After calibration, oReady=1
//   4) On rising edge of iRead while READY:
//        - oReady deasserts
//        - enable selected base
//        - shift 32 serial bits into a word
//        - latch to oRandom, oReady=1
// Ring bases are enabled ONLY during CALIBRATION or COLLECTING.
// -----------------------------------------------------------------------------
module dual_trng(
  input  wire        iClk,
  input  wire        iRst,
  input  wire        iEn,
  // Clock division option
  input  wire [31:0] iClk_div_factor, // Adjust this value to set the clock division factor

  // Calibration control
  input  wire        iCalib,          // start calibration for selected base
  input  wire [31:0] iCalib_cycles,   // how many clocks to keep the base enabled

  // Entropy cell controls
  input  wire [23:0] iTrigger,
  input  wire [23:0] iI1,
  input  wire [23:0] iI2,

  // Readout control
  input  wire        iSel_base,       // 0=long, 1=short (latched at calib start)
  input  wire        iRead,           // read request (pulse while READY)

  output wire        oReady,          // READY level (1 when a new read can start)
  output wire [31:0] oRandom          // last completed 32-bit word
);

  // --------------------------
  // Wires / regs
  // --------------------------
  wire [23:0] w_entropy;
  wire        w_oSerial_long;
  wire        w_oSerial_short;

  reg         en_rg_long;
  reg         en_rg_short;

  reg  [31:0] r_random_number;
  reg         r_ready;

  // FSM states
  localparam [1:0] S_IDLE   = 2'b00;
  localparam [1:0] S_CALIB  = 2'b01;
  localparam [1:0] S_READY  = 2'b10;
  localparam [1:0] S_COLLECT= 2'b11;

  reg  [1:0]  state, next_state;

  // Calibration, selection, and sampling
  reg  [31:0] calib_counter;
  reg  [5:0]  bit_counter;
  reg  [31:0] shift_reg;
  reg         selected_base;          // latched when calibration starts

  // --------------------------
  // Internal clock domain
  // --------------------------

  // An option to reduce the clock frequency for the ring generators
  reg [31:0] r_counter;
  reg clk_div;
  
  always @(posedge iClk) begin
    if (iRst || !iEn) begin
      r_counter <= 32'd0;
      clk_div <= 1'b0;
    end else if (r_counter == iClk_div_factor - 1) begin
      r_counter <= 32'd0;
      clk_div <= ~clk_div;
    end else begin
      r_counter <= r_counter + 32'd1;
    end
  end

  // --------------------------
  // Clock domain crossing synchronizers
  // --------------------------
  
  // Reset synchronizer to clk_div domain
  reg [1:0] rst_sync;
  wire rst_internal;
  
  always @(posedge clk_div or posedge iRst) begin
    if (iRst || !iEn) begin
      rst_sync <= 2'b11;
    end else begin
      rst_sync <= {rst_sync[0], 1'b0};
    end
  end
  assign rst_internal = rst_sync[1] || !iEn;

  // Control signal synchronizers
  reg [1:0] calib_sync, read_sync;
  wire w_calib_internal, w_read_internal;
  
  always @(posedge clk_div or posedge iRst) begin
    if (iRst || !iEn) begin
      calib_sync <= 2'b00;
      read_sync <= 2'b00;
    end else begin
      calib_sync <= {calib_sync[0], iCalib & iEn};
      read_sync <= {read_sync[0], iRead & iEn};
    end
  end
  
  assign w_calib_internal = calib_sync[1];
  assign w_read_internal = read_sync[1];

  // Edge detection for iRead
  reg r_read_prev;
  wire w_iRead_rise = w_read_internal & ~r_read_prev;

  // --------------------------
  // Entropy fabric (24 cells)
  // --------------------------
  genvar i;
  generate
    for (i = 0; i < 24; i = i + 1) begin : gen_entropy_cells
      entropy_cell ec (
        .T(iTrigger[i]),
        .I1(iI1[i]),
        .I2(iI2[i]),
        .oEntropy(w_entropy[i])
      );
    end
  endgenerate

  // --------------------------
  // Ring generators
  // --------------------------
  rg_base_long u_rg_long (
    .iClk(clk_div),
    .iRst(rst_internal),
    .iEn (en_rg_long),
    .iEntropy(w_entropy[23:0]),
    .oSerial(w_oSerial_long)
  );

  rg_base_short u_rg_short (
    .iClk(clk_div),
    .iRst(rst_internal),
    .iEn (en_rg_short),
    .iEntropy(w_entropy[7:0]),
    .oSerial(w_oSerial_short)
  );

  // --------------------------
  // Sequential: state & datapath
  // --------------------------
  always @(posedge clk_div) begin
    if (rst_internal) begin
      state           <= S_IDLE;
      calib_counter   <= 32'd0;
      bit_counter     <= 6'd0;
      shift_reg       <= 32'd0;
      r_random_number <= 32'd0;
      selected_base   <= 1'b0;
      r_read_prev     <= 1'b0;
    end else begin
      state <= next_state;
      r_read_prev <= w_read_internal;

      // Latch base selection at the moment calibration begins
      if (state == S_IDLE && w_calib_internal) begin
        selected_base <= iSel_base;
      end

      // Calibration counter: run only in S_CALIB
      calib_counter <= (state == S_CALIB) ? calib_counter + 32'd1 : 32'd0;

      // Collection: shift exactly 32 bits while enabled
      if (state == S_COLLECT && bit_counter < 6'd32) begin
        shift_reg <= selected_base ? {shift_reg[30:0], w_oSerial_short}
                                   : {shift_reg[30:0], w_oSerial_long};
        bit_counter <= bit_counter + 6'd1;

        // Latch completed word on the 32nd shift
        if (bit_counter == 6'd31) begin
          r_random_number <= selected_base ? {shift_reg[30:0], w_oSerial_short}
                                           : {shift_reg[30:0], w_oSerial_long};
        end
      end else if (state != S_COLLECT) begin
        bit_counter <= 6'd0;
      end
    end
  end

  // --------------------------
  // Combinational: next state
  // --------------------------
  always @(*) begin
    next_state = state;
    case (state)
      S_IDLE: begin
        if (w_calib_internal) next_state = S_CALIB;
      end

      S_CALIB: begin
        // Complete after iCalib_cycles clocks (0 means immediate)
        if ((calib_counter + 32'd1) >= iCalib_cycles)
          next_state = S_READY;
      end

      S_READY: begin
        // Start a new sample only on a rising edge of iRead
        if (w_iRead_rise)
          next_state = S_COLLECT;
      end

      S_COLLECT: begin
        if (bit_counter == 6'd32)
          next_state = S_READY;
      end

      default: next_state = S_IDLE;
    endcase
  end

  // --------------------------
  // Combinational: outputs/enables
  // --------------------------
  always @(*) begin
    // Defaults
    en_rg_long = 1'b0;
    en_rg_short = 1'b0;
    r_ready = 1'b0;

    case (state)
      S_IDLE: begin
        // All outputs at default values
      end

      S_CALIB, S_COLLECT: begin
        // Enable selected ring generator during calibration and collection
        if (selected_base) begin
          en_rg_short = 1'b1;
        end else begin
          en_rg_long = 1'b1;
        end
      end

      S_READY: begin
        // Ready to accept read requests
        r_ready = 1'b1;
      end

      default: begin
        // All outputs at default values
      end
    endcase
  end

  assign oRandom = iEn ? r_random_number : 32'h0;
  assign oReady  = iEn ? r_ready : 1'b0;

endmodule