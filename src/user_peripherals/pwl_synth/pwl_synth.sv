/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "pwl_synth.vh"

(* keep_hierarchy *)
module tqvp_toivoh_pwl_synth #(parameter BITS=12, OCT_BITS=3, DETUNE_EXP_BITS=3, SLOPE_EXP_BITS=4, NUM_CHANNELS=4) (
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

`ifdef USE_TEST_INTERFACE
		input wire en_external,
		input wire state_override_en,
		input int state_override, // (term_index << 8) | state
		input wire [2:0] step_part_enables, // {post_en, main_en, pre_en}
		// interface for internal registers
		input int ireg_raddr, ireg_waddr,
		output int ireg_rdata,
		input int ireg_wdata,
		// expose internal register writes
		output wire reg_we_internal_out,
		output int reg_waddr_internal_out,
		output int reg_wdata_internal_out,
`endif

		output        user_interrupt  // Dedicated interrupt request for this peripheral
	);

	wire reset = !rst_n;

`ifndef USE_TEST_INTERFACE
		wire en_external = 1;
`endif

/*
	// Temporary cfg register for shared parameters
	reg [31:0] cfg;
	always @(posedge clk) begin
		if (data_write_n == 2'b10 && address == 60) cfg <= data_in;
	end
*/

	// Not used anymore
	wire [DETUNE_EXP_BITS-1:0] detune_exp = 0;
	wire [BITS-1:0] tri_offset = 0;
	wire [SLOPE_EXP_BITS-1:0] slope_exp = 0;
	wire [BITS-3-1:0] slope_offset = 0;
	wire [BITS-2-1:0] amp = 0;

/*
	assign {detune_exp, tri_offset[BITS-1 -: 10], slope_exp, slope_offset[BITS-3-1 -: 5], amp[BITS-2-1 -: 6]} = cfg;
	assign tri_offset[BITS-10-1:0] = '0;
	assign slope_offset[BITS-3-5-1:0] = '0;
	assign amp[BITS-2-6-1:0] = '0;
*/

	// Remap the registers to gather the fields for each channel together
	wire [5:0] address2 = {address[3:1], address[5:4], address[0]};

	// Read / write interface to pwls_multichannel_ALU_unit
	wire [`REG_ADDR_BITS-1:0] reg_addr = address2[5:1];
	//wire read_en = (data_read_n != 2'b11);


	wire reg_raddr_valid = (data_read_n != 2'b11);

`ifdef USE_NEW_READ
	wire en = en_external;
	wire next_en = 1; // TODO: take en_external into account if we want to use the reg_raddr_p interface.

	wire [`REG_ADDR_BITS-1:0] reg_raddr = reg_addr;
	wire reg_rdata_valid_next;

	reg reg_rdata_valid;
	always_ff @(posedge clk) reg_rdata_valid <= !reset && reg_rdata_valid_next;
	assign data_ready = reg_rdata_valid;
`else
	reg read_en;
	//reg [`REG_ADDR_BITS-1:0] reg_addr_last;
	//wire [`REG_ADDR_BITS-1:0] reg_raddr_p = reg_addr;
	wire next_read_en = reg_raddr_valid;
	always_ff @(posedge clk) begin
		if (reset) read_en <= 0;
		else read_en <= next_read_en;
		//reg_addr_last <= reg_addr;
	end

	wire [`REG_ADDR_BITS-1:0] reg_raddr_p = reg_addr;
	//wire [`REG_ADDR_BITS-1:0] reg_raddr_p = reg_addr_last;
	//wire [`REG_ADDR_BITS-1:0] reg_raddr_p = {reg_addr[4:2], reg_addr_last[1:0]}; // register the channel bits, most timing critical?

	wire en = !read_en && en_external;
	wire next_en = !next_read_en;
	assign data_ready = read_en;
`endif


`ifdef USE_NEW_REGMAP_A
	wire reg_we = (data_write_n[1] != data_write_n[0]); // Accept 16 or 32 bit writes for now
`else
	wire reg_we = (data_write_n == 2'b01); // Accept only 16 bit writes for now
`endif
	wire [`REG_BITS-1:0] reg_wdata = data_in;



	wire [BITS-1:0] out_acc;
	wire [`REG_BITS-1:0] reg_rdata;
	wire pwm_out;
	pwls_multichannel_ALU_unit #(.BITS(BITS), .OCT_BITS(OCT_BITS), .DETUNE_EXP_BITS(DETUNE_EXP_BITS), .SLOPE_EXP_BITS(SLOPE_EXP_BITS), .NUM_CHANNELS(NUM_CHANNELS)) mc_alu_unit(
		.clk(clk), .reset(reset), .en(en), .next_en(next_en),
		.reg_waddr(reg_addr), .reg_wdata(reg_wdata), .reg_we(reg_we),
`ifdef USE_NEW_REGMAP_A
		.control_reg_write(1), .state_reg_write(!address2[0]),
`else
		.control_reg_write(1), .state_reg_write(1),
`endif

`ifdef USE_NEW_READ
		.reg_raddr(reg_raddr), .reg_raddr_valid(reg_raddr_valid), .reg_rdata(reg_rdata), .reg_rdata_valid_next(reg_rdata_valid_next),
`else
		.reg_raddr_p(reg_raddr_p), .next_reg_raddr_p(reg_addr), .reg_rdata_p(reg_rdata),
`endif

		//.detune_exp(detune_exp),
		.tri_offset(tri_offset), .slope_exp (slope_exp), .slope_offset(slope_offset), //.amp(amp),

`ifdef USE_TEST_INTERFACE
	.state_override_en(state_override_en), .state_override(state_override), .step_part_enables(step_part_enables),
	.ireg_raddr(ireg_raddr), .ireg_waddr(ireg_waddr), .ireg_rdata(ireg_rdata), .ireg_wdata(ireg_wdata),
	.reg_we_internal_out(reg_we_internal_out), .reg_waddr_internal_out(reg_waddr_internal_out), .reg_wdata_internal_out(reg_wdata_internal_out),
`endif

		.out_acc_out(out_acc), .pwm_out(pwm_out)
	);

	//assign uo_out = out_acc >> (BITS-8);
	assign uo_out = pwm_out ? '1 : 0;

	assign data_out = reg_rdata;
	assign user_interrupt = 1'b0;
endmodule


module named_buffer #(parameter BITS=1) (
		input wire [BITS-1:0] in,
		output wire [BITS-1:0] out
	);
`ifdef NAMED_BUF_EN
	genvar i;
	generate
		for (i = 0; i < BITS; i++) begin : bits
			(* keep *) (* dont_touch *) sky130_fd_sc_hd__buf_1 named_buf(.A(in[i]), .X(out[i]));
			//(* keep *) (* dont_touch *) buf named_buf(out[i], in[i]);
		end
	endgenerate
`else
	assign out = in;
`endif
endmodule


module pwls_shifter(
		input wire [15:0] shifter_in,
		input wire [3:0] shl_count,
		input wire do_shl, // mask out bits rotated into the bottom?

		output wire [15:0] shl_mask,
		output wire [15:0] shifter_out
	);

/*
	// CONSIDER: better with mux4? Does this become mux4?
	wire [15:0] x0 = shifter_in;
	wire [15:0] x1 = shl_count[3] ? {x0[ 7:0], x0[15: 8]} : x0;
	wire [15:0] x2 = shl_count[2] ? {x1[11:0], x1[15:12]} : x1;
	wire [15:0] x3 = shl_count[1] ? {x2[13:0], x2[15:14]} : x2;
	wire [15:0] x4 = shl_count[0] ? {x3[14:0], x3[15:15]} : x3;
	wire [15:0] x = x4;
*/
	wire [15:0] x = {{shifter_in, shifter_in} << shl_count} >> 16;

	assign shl_mask = '1 << shl_count;
	wire [15:0] mask = do_shl ? shl_mask : '1;

	assign shifter_out = x & mask;
endmodule : pwls_shifter


module pwls_ALU #(parameter BITS=12, BITS_E=13, SHIFT_COUNT_BITS=4, OUT_RSHIFT=3, REV_PHASE_SHR=1, AMP_BITS=6) (
		input wire clk, reset,

		input wire signed [BITS_E-1:0] src1_in,
		input wire signed [15:0] src2_in,
		input wire src2_rot, // rotate src2 instead of left shifting?
		input wire src2_forward_extra_bit, // for limited BITS_E ALU functionality. src2_sext, src2_mask_msbs, inv_src2 not supported.
		input wire [SHIFT_COUNT_BITS-1:0] src2_lshift,
		input wire src2_sext,
		input wire inv_src1, inv_src2, src2_mask_msbs, carry_in,
		input wire sat_en,

		output wire signed [BITS_E-1:0] result,
		output wire cmp_result, delayed, equal
	);

	genvar i;

	wire signed [BITS_E-1:0] src2_shifted_0;
	wire signed [15:0] shl_mask;
	pwls_shifter src2_shifter(
		.shifter_in(src2_in), .shl_count(src2_lshift), .do_shl(!src2_rot),
		.shifter_out(src2_shifted_0), .shl_mask(shl_mask)
	);

	// not a register
	reg signed [BITS-1:0] src2_shifted;
	always_comb begin
		src2_shifted = src2_shifted_0;
		if (src2_sext) src2_shifted[BITS-1 -: OUT_RSHIFT] = src2_in[BITS-1] ? '1 : '0;
	end

	wire [15:0] rev_shl_mask;
	generate
		for (i = 0; i < 16; i++) assign rev_shl_mask[i] = shl_mask[15-i];
	endgenerate
	wire [BITS-1-1:0] shl_sat_mask = ~rev_shl_mask >> (15 - (BITS-2));

	wire do_sat_shl_minus_corner = BITS == 12 ? (src2_lshift[3:2] == '1) : (src2_lshift >= BITS);

	wire do_sat_shl_plus  = (src2_in[BITS-1] == 0) && |( src2_in & shl_sat_mask);
	wire do_sat_shl_minus = (src2_in[BITS-1] == 1) && (|(~src2_in & shl_sat_mask) | do_sat_shl_minus_corner);
	wire do_sat_shl = do_sat_shl_plus || do_sat_shl_minus;
	wire sat_shl_sign = src2_in[BITS-1];


	wire signed [BITS-1:0] src2_1 = src2_shifted & {{(1+REV_PHASE_SHR){!src2_mask_msbs}}, {(BITS-1-REV_PHASE_SHR){1'b1}}};
	// forward extra bit or sign extend
	wire signed [BITS_E-1:0] src2_2 = {(src2_forward_extra_bit ? src2_shifted_0[BITS_E-1] : src2_1[BITS-1]), src2_1};

	wire signed [BITS_E-1:0] src1 = src1_in ^ (inv_src1 ? '1 : 0);
	wire signed [BITS_E-1:0] src2 = src2_2 ^ (inv_src2 ? '1 : 0);

	//wire signed [BITS-1:0] sum = src1 + src2 + $signed({1'b0, carry_in});
	// An additional result bit seems to be needed to saturate correctly, at least for the combined slope step
	wire signed [BITS+1-1:0] sum = src1 + src2 + $signed({1'b0, carry_in});

	// Saturate to one bit less than BITS if saturation enabled; only phases need the full bit width
	/*
	wire sat_sum_sign = sum[BITS-1];
	wire do_sat_sum = sum[BITS-2] != sat_sum_sign;
	*/
	wire sat_sum_sign = sum[BITS];
	wire do_sat_sum = sum[BITS-1 -: 2] != {2{sat_sum_sign}};

	// not registers
	reg sat_sign, do_sat;
	always_comb begin
		if (do_sat_shl) begin
			do_sat = 1;
			sat_sign = sat_shl_sign ^ inv_src2;
		end else if (do_sat_sum) begin
			do_sat = 1;
			sat_sign = sat_sum_sign;
		end else begin
			do_sat = 0;
			sat_sign = 'X;
		end
	end

	wire signed [BITS-1:0] sat_sum = (sat_en && do_sat) ? (sat_sign ? -1 << (BITS - 2) : (1 << (BITS - 2)) - 1) : sum;

	//assign result = sat_sum;
	assign result = {sum[BITS_E-1:BITS], sat_sum}; // The top bits are not used with saturation for now

	assign cmp_result = sum[BITS-1];
	assign delayed = src2_shifted[BITS-REV_PHASE_SHR-1];
	assign equal = (sum[AMP_BITS-1:0] == '0);
endmodule : pwls_ALU


module pwls_state_decoder #(parameter SHIFT_COUNT_BITS=4, DETUNE_EXP_BITS=3, SLOPE_EXP_BITS=4, OUT_RSHIFT=3, BITS=12) (
		input wire [`STATE_BITS-1:0] state,
		input wire extra_term,

		input wire [SHIFT_COUNT_BITS-1:0] osc_shift,
		input wire oct_enable, acc_sign, pred, part, first_term, sub_channel,
		input wire [DETUNE_EXP_BITS-1:0] detune_exp,
		input wire [SLOPE_EXP_BITS-1:0] slope_exp,
		input wire [`CHANNEL_MODE_BITS-1:0] channel_mode,
		input wire [`SWEEP_DIR_BITS-1:0] sweep_dir,
		input wire [`SWEEP_INDEX_BITS-1:0] sweep_index,
`ifdef USE_NEW_READ
		input wire [`SWEEP_INDEX_BITS-1:0] reg_read_index,
`endif

`ifdef USE_TEST_INTERFACE
		input wire [2:0] step_part_enables, // {post_en, main_en, pre_en}
`endif

		output wire [`SRC1_SEL_BITS-1:0] src1_sel_out,
		output wire keep_exp_on_top_out,
		output wire [`SRC2_SEL_BITS-1:0] src2_sel_out,
		output wire [SHIFT_COUNT_BITS-1:0] src2_lshift_out,
		output wire src2_lshift_extra_out, src2_rot_out, src2_forward_extra_bit_out, src2_mask_msb_out, mask_out_acc_top_out, src1_en_out, inv_src1_out, inv_src2_out, carry_in_out, sat_en_out,
		output wire pred_we_out, part_we_out,
		output wire [`PART_SEL_BITS-1:0] part_sel_out,
		output wire [`DEST_SEL_BITS-1:0] dest_sel_out,
		output wire pred_next_use_cmp_out, pred_next_use_lfsr_out,
		output wire replace_src2_with_amp_out,
		output wire src2_sext_out,
		output wire reg_we_out,
		output wire sweep_sign_out
	);

	wire pre_en, main_en, post_en;
`ifdef USE_TEST_INTERFACE
	assign {post_en, main_en, pre_en} = step_part_enables;
`else
	assign pre_en = 1;
	assign main_en = 1;
	assign post_en = 1;
`endif

	//wire sweep_sign = sweep_dir[0];
	// Decode sweep_dir
	wire [1:0] sdir = sweep_dir[2:1];
	wire sweep_en = (sweep_index[0] == 0) ? (sdir != 2'b10) : (sdir != 2'b01);
	wire sweep_sign = sweep_dir[0] ^ ((sweep_index[0] == 1) && sdir == 2'b00);



	// not registers
	reg [`SRC1_SEL_BITS-1:0] src1_sel;
	reg keep_exp_on_top;
	reg [`SRC2_SEL_BITS-1:0] src2_sel;
	reg [SHIFT_COUNT_BITS-1:0] src2_lshift;
	reg src2_lshift_extra, src2_rot, src2_forward_extra_bit, src2_mask_msbs, mask_out_acc_top, src1_en, inv_src1, inv_src2, carry_in, sat_en;
	reg pred_we, part_we;
	reg [`DEST_SEL_BITS-1:0] dest_sel;
	reg dest_we_only_if_oct_en;
	reg pred_next_use_cmp, pred_next_use_lfsr;
	reg [`PART_SEL_BITS-1:0] part_sel;
	reg replace_src2_with_amp;
	reg src2_sext;
	reg reg_we_if_oct_en, reg_we_only_if_part;

	always_comb begin
		keep_exp_on_top = 0;
		pred_next_use_cmp = 0;
		pred_next_use_lfsr = 0;
		part_we = 0;
		pred_we = 0;
		src2_rot = 0;
		src2_forward_extra_bit = 0;
		src2_mask_msbs = 0;
		replace_src2_with_amp = 0;
		src2_sext = 0;
		mask_out_acc_top = 0;
		src1_en = 1;
		src2_lshift_extra = 0;
		dest_sel = `DEST_SEL_NOTHING;
		dest_we_only_if_oct_en = 0;
		reg_we_if_oct_en = 0;
		part_sel = `PART_SEL_ACC_MSB;
		reg_we_only_if_part = 0;

		if (extra_term) begin
			sat_en = 0;
			src2_lshift = 0;
			inv_src1 = 0; inv_src2 = 0; carry_in = 0;

			src1_sel = 'X;
			src2_sel = 'X;
			pred_next_use_cmp = 'X;
			//pred_we = 'X;
			//part_we = 'X;
			//dest_sel = 'X;

			case (state)
/*
				0: begin
					// Calculate period +- 1, store in acc
					src1_sel = `SRC1_SEL_MANTISSA;
					keep_exp_on_top = 1;
					src2_sel = `SRC2_SEL_PHASE_STEP;
					sat_en = 0; // TODO?
					inv_src1 = 0; inv_src2 = sweep_sign; carry_in = inv_src2;
					src2_lshift = 0;
					dest_sel = `DEST_SEL_ACC;
				end
				1: begin
					// Write back updated period if oct_enable
					reg_we_if_oct_en = 1;
				end
*/
				0: begin
					// Read in current value of parameter to be swept, store into acc.
					// For slope0 and slope1, relies on that part was set based on sweep_index in the last cycle.
					src1_sel = (sweep_index == `SWEEP_INDEX_SLOPE1) ? `SRC1_SEL_SLOPE_OFFSET : sweep_index;
					keep_exp_on_top = 1;
					src2_sel = `SRC2_SEL_ZERO;
					dest_sel = `DEST_SEL_ACC;
				end
				1: begin
					// Shift/rotate current parameter value right
					src1_sel = `SRC1_SEL_ZERO;
					src2_sel = `SRC2_SEL_ACC;
					src2_rot = 1;
					src2_forward_extra_bit = 1; // Needed to get 13 bits through src2, limited functionality
					case (sweep_index)
						`SWEEP_INDEX_PERIOD: src2_lshift = 0;
						`SWEEP_INDEX_AMP: src2_lshift = -(BITS-2-6);
						`SWEEP_INDEX_SLOPE0, `SWEEP_INDEX_SLOPE1: src2_lshift = -(BITS+1-8);
						`SWEEP_INDEX_PWM_OFFSET: src2_lshift = -(BITS-2-8);
						default: src2_lshift = 'X;
					endcase
					dest_sel = `DEST_SEL_ACC;
				end
				2: begin
					// Compare acc to amp_target if amp sweep
					src1_sel = `SRC1_SEL_AMP_TARGET;
					src2_sel = `SRC2_SEL_ACC;
					inv_src2 = 1; carry_in = 1;
					pred_we = 1; pred_next_use_cmp = 1; // save comparison sign
					part_we = main_en; part_sel = (sweep_index == `SWEEP_INDEX_AMP) ? `PART_SEL_NEQ : `PART_SEL_NOSAT; // save equality
				end
				3: begin
					// Increase/decrease parameter in acc
					src1_sel = `SRC1_SEL_ZERO;
					src2_sel = `SRC2_SEL_ACC;
					src2_forward_extra_bit = 1; // Needed to get 13 bits through src2, limited functionality
					// Add or subtract one using src1 = 0, inv_src1 and carry_in.
					inv_src1 = (sweep_index == `SWEEP_INDEX_AMP) ? pred : sweep_sign; inv_src2 = 0; carry_in = !inv_src1;
					dest_sel = `DEST_SEL_ACC;
				end
				4: begin
					// Write back updated period if oct_enable
					reg_we_if_oct_en = sweep_en;
					reg_we_only_if_part = 1; //(sweep_index == `SWEEP_INDEX_AMP);
				end
				default: begin
					src1_sel = 'X;
					keep_exp_on_top = 'X;
					src2_sel = 'X;
					src2_rot = 'X; sat_en = 'X;
					src2_forward_extra_bit = 'X;
					inv_src1 = 'X; inv_src2 = 'X; carry_in = 'X;
					src2_lshift = 'X;
					src2_mask_msbs = 'X;
					//pred_we = 'X;
					//part_we = 'X;
					pred_next_use_cmp = 'X;
					//dest_sel = 'X;
					replace_src2_with_amp = 'X;
					src2_sext = 'X;
					src1_en = 'X;
					src2_lshift_extra = 'X;
				end
			endcase
		end else case (state)
			`STATE_CMP_REV_PHASE: begin
				src1_sel = `SRC1_SEL_MANTISSA;
				src2_sel = `SRC2_SEL_REV_PHASE;
				sat_en = 0;
				inv_src1 = 1; inv_src2 = 0; carry_in = 1;
				src2_lshift = channel_mode[`CHANNEL_MODE_BIT_NOISE] ? 0 : osc_shift;
				src2_mask_msbs = 1;
				pred_we = 1;
				pred_next_use_lfsr = channel_mode[`CHANNEL_MODE_BIT_NOISE];
				dest_sel = `DEST_SEL_NOTHING;
			end
			`STATE_UPDATE_PHASE: begin
				if (channel_mode[`CHANNEL_MODE_BIT_NOISE]) begin
					// Update of lfsr_extra_bits is matched with this update
					if (pred) begin // small_step, just increase by one
						src1_sel = `SRC1_SEL_PHASE;
						src2_sel = `SRC2_SEL_PHASE_STEP;
						sat_en = 0;
						inv_src1 = 0; inv_src2 = 0; carry_in = 0;
						src2_lshift = 0;
						src2_lshift_extra = 0;
					end else begin // LFSR step
						src1_sel = `SRC1_SEL_ZERO;
						src2_sel = `SRC2_SEL_PHASE_MODIFIED;
						sat_en = 0;
						inv_src1 = 0; inv_src2 = 0; carry_in = 0;
						src2_lshift = 1;
						src2_lshift_extra = 0;
					end
				end else begin
					src1_sel = `SRC1_SEL_PHASE;
					src2_sel = `SRC2_SEL_PHASE_STEP;
					sat_en = 0;
					inv_src1 = 0; inv_src2 = 0; carry_in = 0;
					src2_lshift = osc_shift;
					src2_lshift_extra = !pred;
				end
`ifdef USE_PHASE_LATCHES
				dest_sel = `DEST_SEL_ACC; // write the phase to acc
`else
				dest_sel = `DEST_SEL_PHASE; dest_we_only_if_oct_en = 1;
`endif
			end
			`STATE_DETUNE: begin
				src1_sel = `SRC1_SEL_PHASE;
				src2_sel = (detune_exp == 0) ? `SRC2_SEL_ZERO : `SRC2_SEL_DETUNE;
				src2_rot = 1; sat_en = 0;
				inv_src1 = 0; inv_src2 = sub_channel; carry_in = 0;
				src2_lshift = detune_exp;
				dest_sel = `DEST_SEL_ACC;

`ifdef USE_PHASE_LATCHES
				// Write the phase from acc to phase, if we are in the first subchannel so that the new phase is stored in acc
				reg_we_if_oct_en = (sub_channel == 0);
`endif
			end
			`STATE_TRI: begin
				src1_sel = `SRC1_SEL_TRI_OFFSET;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = 0; inv_src2 = acc_sign; carry_in = 0;
				src2_lshift = 0;
				part_we = main_en;
				dest_sel = `DEST_SEL_ACC;
			end
/*
			`STATE_SLOPE: begin
				src1_sel = `SRC1_SEL_ZERO;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = 0; inv_src2 = 0; carry_in = 0;
				src2_lshift = slope_exp;
				dest_sel = `DEST_SEL_ACC;
			end
			`STATE_FINE_SLOPE_CMP: begin
				src1_sel = `SRC1_SEL_SLOPE_OFFSET;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = !acc_sign; inv_src2 = 0; carry_in = inv_src1;
				src2_lshift = 0;
				pred_we = 1;
				pred_next_use_cmp = 1;
				dest_sel = `DEST_SEL_NOTHING;
			end
			`STATE_FINE_SLOPE_ADD: begin
				src1_sel = pred ? `SRC1_SEL_ZERO : `SRC1_SEL_SLOPE_OFFSET; // TODO zero out later
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = acc_sign; inv_src2 = 0; carry_in = inv_src1;
				src2_lshift = pred; // TODO: modify src2_lshift later
				dest_sel = `DEST_SEL_ACC;
			end
*/
			`STATE_COMBINED_SLOPE_CMP: begin
				src1_sel = `SRC1_SEL_SLOPE_OFFSET;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = !acc_sign; inv_src2 = 0; carry_in = inv_src1;
				src2_lshift = slope_exp;
				pred_we = 1; pred_next_use_cmp = 1;
				dest_sel = `DEST_SEL_NOTHING;
			end
			`STATE_COMBINED_SLOPE_ADD: begin
				//src1_sel = pred ? `SRC1_SEL_ZERO : `SRC1_SEL_SLOPE_OFFSET; // TODO zero out later
				src1_sel = `SRC1_SEL_SLOPE_OFFSET;
				src1_en = !pred;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = acc_sign; inv_src2 = 0; carry_in = inv_src1;
				//src2_lshift = slope_exp + pred; // TODO: modify src2_lshift later
				src2_lshift = slope_exp;
				src2_lshift_extra = pred;
				dest_sel = `DEST_SEL_ACC;
			end
			`STATE_AMP_CMP: begin
				src1_sel = `SRC1_SEL_AMP;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = !acc_sign; inv_src2 = 0; carry_in = inv_src1;
				src2_lshift = 0;
				pred_we = 1;
				pred_next_use_cmp = 1;
				dest_sel = `DEST_SEL_NOTHING;
			end
/*
			`STATE_AMP_CLAMP: begin
				//src1_sel = !pred ? `SRC1_SEL_AMP : `SRC1_SEL_ZERO;
				//src2_sel =  pred ? `SRC2_SEL_ACC : `SRC2_SEL_ZERO;

				src1_sel = `SRC1_SEL_ZERO;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;

				inv_src1 = 0; inv_src2 = 0;
				if (!pred) begin
					replace_src2_with_amp = 1;
					inv_src2 = acc_sign;
				end
				carry_in = inv_src1;

				src2_lshift = 16 - OUT_RSHIFT;
				src2_rot = 1;
				src2_sext = 1;
				dest_sel = `DEST_SEL_ACC;
			end
*/
			`STATE_OUT_ACC: begin
				//src1_sel = first_term ? `SRC1_SEL_ZERO : `SRC1_SEL_OUT_ACC; // TODO: mask out only the top bits
				src1_sel = `SRC1_SEL_OUT_ACC;
				mask_out_acc_top = first_term;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 0; // Saturation doesn't seem to play well with the right shift; would at least have to disable shl saturation to make it work.

				inv_src1 = 0; inv_src2 = 0;
				if (!pred) begin
					replace_src2_with_amp = 1;
					inv_src2 = acc_sign;
				end
				carry_in = inv_src2;

				src2_lshift = 16 - OUT_RSHIFT;
				src2_rot = 1;
				src2_sext = 1;
				dest_sel = `DEST_SEL_OUT_ACC;

				// Prepare for first step of sweep program, if it comes next
				part_we = pre_en; part_sel = `PART_SEL_SWEEP;
			end

			default: begin
				src1_sel = 'X;
				keep_exp_on_top = 'X;
				src2_sel = 'X;
				src2_rot = 'X; sat_en = 'X;
				src2_forward_extra_bit = 'X;
				inv_src1 = 'X; inv_src2 = 'X; carry_in = 'X;
				src2_lshift = 'X;
				src2_mask_msbs = 'X;
				pred_we = 'X;
				part_we = 'X;
				pred_next_use_cmp = 'X;
				dest_sel = 'X;
				replace_src2_with_amp = 'X;
				src2_sext = 'X;
				src1_en = 'X;
				src2_lshift_extra = 'X;
				reg_we_if_oct_en = 'X;
				part_sel = 'X;
			end
		endcase

		if (!main_en) begin
			dest_sel = `DEST_SEL_NOTHING;
			pred_we = 0;
		end
	end

	wire [`DEST_SEL_BITS-1:0] dest_sel_eff = (dest_we_only_if_oct_en && !oct_enable) ? `DEST_SEL_NOTHING : dest_sel;
	wire reg_we = (reg_we_if_oct_en && oct_enable) && (!reg_we_only_if_part || part) && post_en;


	named_buffer #(.BITS(`SRC1_SEL_BITS)) nb_src1_sel(.in(src1_sel), .out(src1_sel_out));
	named_buffer #(.BITS(`SRC2_SEL_BITS)) nb_src2_sel(.in(src2_sel), .out(src2_sel_out));
	named_buffer #(.BITS(`DEST_SEL_BITS)) nb_dest_sel(.in(dest_sel_eff), .out(dest_sel_out));
	named_buffer #(.BITS(SHIFT_COUNT_BITS)) nb_src2_lshift(.in(src2_lshift), .out(src2_lshift_out));
	named_buffer #(.BITS(`PART_SEL_BITS)) nb_part_sel(.in(part_sel), .out(part_sel_out));

	named_buffer nb_keep_exp_on_top(.in(keep_exp_on_top), .out(keep_exp_on_top_out));
	named_buffer nb_src2_lshift_extra(.in(src2_lshift_extra), .out(src2_lshift_extra_out));
	named_buffer nb_src2_rot(.in(src2_rot), .out(src2_rot_out));
	named_buffer nb_src2_forward_extra_bit(.in(src2_forward_extra_bit), .out(src2_forward_extra_bit_out));
	named_buffer nb_src2_mask_msb(.in(src2_mask_msbs), .out(src2_mask_msb_out));
	named_buffer nb_src1_en(.in(src1_en), .out(src1_en_out));
	named_buffer nb_mask_out_acc_top(.in(mask_out_acc_top), .out(mask_out_acc_top_out));
	named_buffer nb_inv_src1(.in(inv_src1), .out(inv_src1_out));
	named_buffer nb_inv_src2(.in(inv_src2), .out(inv_src2_out));
	named_buffer nb_carry_in(.in(carry_in), .out(carry_in_out));
	named_buffer nb_sat_en(.in(sat_en), .out(sat_en_out));
	named_buffer nb_pred_we(.in(pred_we), .out(pred_we_out));
	named_buffer nb_part_we(.in(part_we), .out(part_we_out));
	named_buffer nb_pred_next_use_cmp(.in(pred_next_use_cmp), .out(pred_next_use_cmp_out));
	named_buffer nb_pred_next_use_lfsr(.in(pred_next_use_lfsr), .out(pred_next_use_lfsr_out));
	named_buffer nb_replace_src2_with_amp(.in(replace_src2_with_amp), .out(replace_src2_with_amp_out));
	named_buffer nb_src2_sext(.in(src2_sext), .out(src2_sext_out));
	named_buffer nb_reg_we(.in(reg_we), .out(reg_we_out));
	named_buffer nb_sweep_sign(.in(sweep_sign), .out(sweep_sign_out));
endmodule


module pwls_ALU_unit #(parameter BITS=12, BITS_E=13, SHIFT_COUNT_BITS=4, OCT_BITS=3, DETUNE_EXP_BITS=3, SLOPE_EXP_BITS=4, OUT_RSHIFT=4, OUT_ACC_FRAC_BITS=4, LFSR_HIGHEST_OCT=3, LFSR_STATE_BITS=18, OUT_ACC_INITIAL_TOP=0, REV_PHASE_SHR=1, AMP_BITS=6) (
		input wire clk, reset, en,

		input wire [`STATE_BITS-1:0] state,
		input wire extra_term,
		input wire first_term, sub_channel, oct_counter_we,
		input wire [`SWEEP_DIR_BITS-1:0] sweep_dir,
		input wire [`SWEEP_INDEX_BITS-1:0] sweep_index,
`ifdef USE_NEW_READ
		input wire [`SWEEP_INDEX_BITS-1:0] reg_read_index,
`endif

		input wire [OCT_BITS-1:0] octave,
		input wire [DETUNE_EXP_BITS-1:0] detune_exp,
		input wire [SLOPE_EXP_BITS-1:0] slope_exp,
		input wire [`CHANNEL_MODE_BITS-1:0] channel_mode,

		output wire [`SRC1_SEL_BITS-1:0] src1_sel_out,
		output wire keep_exp_on_top,
		output wire [`DEST_SEL_BITS-1:0] dest_sel_out,
		output wire reg_we,
		output wire part_out,
		output wire [BITS_E-1:0] result,
		input wire signed [BITS_E-1:0] src1_external,
		input wire [BITS-1:0] phase_external, // Only used for rev_phase, must be valid when src2 reads rev_phase (or delayed is used, which depends on it)
		input wire [BITS-2-1:0] amp_external,

		input wire oct_enable_index_override_en,
		input wire hard_oct_enable_override_en, hard_oct_enable_override, // only apply if oct_enable_index_override_en
		input wire [3:0] oct_enable_index_override,
		input wire [`DIVIDER_BITS-1:0] oct_counter_term,

		output wire [`DIVIDER_BITS-1:0] sample_counter,

`ifdef USE_TEST_INTERFACE
		input wire [2:0] step_part_enables, // {post_en, main_en, pre_en}
		// interface for internal registers
		input int ireg_raddr, ireg_waddr,
		output int ireg_rdata,
		input int ireg_wdata,
`endif

		output wire [BITS_E-1:0] acc_out,
		output wire [BITS-1:0] out_acc_out
	);

	localparam HIGH_OCTAVES = 4;

	localparam PHASE_BITS = BITS;
	localparam STATE_LAST = `STATE_LAST;

	localparam LFSR_EXTRA_BITS = LFSR_STATE_BITS - (PHASE_BITS - 1);

`ifdef PIPELINE
	localparam PIPELINE = 1;
`else
	localparam PIPELINE = 0;
`endif

`ifdef PIPELINE_SRC2
	localparam ACC_BITS = 16;
`else
	localparam ACC_BITS = BITS_E;
`endif

`ifndef USE_TEST_INTERFACE
	int ireg_waddr, ireg_wdata;
	assign ireg_waddr = `TST_ADDR_NOTHING;
	assign ireg_wdata = 0;
`endif


	genvar i;

	reg pred, part;

	reg [ACC_BITS-1:0] acc;
	reg [BITS-1:0] out_acc;

	reg [LFSR_EXTRA_BITS-1:0] lfsr_extra_bits;

`ifdef PIPELINE
	reg [`STATE_BITS-1:0] state_late;
	always_ff @(posedge clk) if (en) state_late <= state; // TODO: do we need a reset value?
`else
	wire [`STATE_BITS-1:0] state_late = state;
	wire extra_term_late = extra_term;
`endif


	// Octave divider
	// ==============
	//localparam DIVIDER_BITS = 2**OCT_BITS - HIGH_OCTAVES;
	localparam DIVIDER_BITS = `DIVIDER_BITS;

	reg [DIVIDER_BITS-1:0] oct_counter;
	wire [DIVIDER_BITS-1:0] next_oct_counter = oct_counter + oct_counter_term; // CONSIDER: Can we use the ALU's adder for this?

	wire [DIVIDER_BITS-1:0] all_oct_enables = next_oct_counter & ~oct_counter;

/*
	wire [2**OCT_BITS-1:0] oct_enables = {all_oct_enables, {HIGH_OCTAVES{1'b1}}};
	//wire [2**OCT_BITS-1:0] oct_enables = {all_oct_enables, {HIGH_OCTAVES{1'b1}}} & 8'b01111111; // Disable octave 7

	wire [2**OCT_BITS-1:0] oct_enables_lfsr = all_oct_enables[2**OCT_BITS-1+LFSR_HIGHEST_OCT -: 2**OCT_BITS];

	wire oct_enable = channel_mode[`CHANNEL_MODE_BIT_NOISE] ? oct_enables_lfsr[octave] : oct_enables[octave];
*/

	// not registers
	reg [3:0] oct_enable_index_offset;
	reg force_oct_enable;
	always_comb begin
		if (channel_mode[`CHANNEL_MODE_BIT_NOISE]) begin
			oct_enable_index_offset = LFSR_HIGHEST_OCT;
			force_oct_enable = 0;
		end else begin
			oct_enable_index_offset = -HIGH_OCTAVES;
			if (HIGH_OCTAVES == 4) force_oct_enable = !octave[2];
			else force_oct_enable = octave < HIGH_OCTAVES;
		end
	end

	//wire [3:0] oct_enable_index = octave + oct_enable_index_offset;
	wire [3:0] oct_enable_index = oct_enable_index_override_en ? oct_enable_index_override : (octave + oct_enable_index_offset);

	reg oct_enable; // not a register
	always_comb begin
		oct_enable = all_oct_enables[oct_enable_index];
		if (oct_enable_index_override_en) begin
			if (hard_oct_enable_override_en) oct_enable = hard_oct_enable_override;
		end else begin
			if (force_oct_enable) oct_enable = 1;
		end
	end



	always_ff @(posedge clk) begin
		if (reset) oct_counter <= 0;
		else if (oct_counter_we) oct_counter <= next_oct_counter;
`ifdef USE_TEST_INTERFACE
		if (ireg_waddr == `TST_ADDR_OCT_COUNTER) oct_counter <= ireg_wdata;
`endif
	end


	// ===================

	wire [PHASE_BITS-1:0] rev_phase0;
	generate
		for (i = 0; i < PHASE_BITS; i++) assign rev_phase0[i] = phase_external[PHASE_BITS-1 - i];
	endgenerate
	wire [PHASE_BITS-1:0] rev_phase = rev_phase0 >> REV_PHASE_SHR;


	reg [SHIFT_COUNT_BITS-1:0] osc_shift; // not a register
	always_comb begin
		case (octave)
			0: osc_shift = 3;
			1: osc_shift = 2;
			2: osc_shift = 1;
			default: osc_shift = 0;
		endcase
	end


	// wire [BITS-1:0] osc_step = pred ? 1 : 2;
	wire [BITS-1:0] osc_step = 1; // handle using src2_lshift_extra instead

	wire cmp_result, delayed;


	wire [`SRC1_SEL_BITS-1:0] src1_sel;
	wire [`SRC2_SEL_BITS-1:0] src2_sel;
	wire [SHIFT_COUNT_BITS-1:0] src2_lshift_early;
	wire src2_lshift_extra, src2_rot, src2_forward_extra_bit, src2_mask_msbs, mask_out_acc_top, src1_en, inv_src1, inv_src2, carry_in, sat_en;
	wire pred_we, part_we;
	wire [`DEST_SEL_BITS-1:0] dest_sel;
	wire pred_next_use_cmp, pred_next_use_lfsr, replace_src2_with_amp, src2_sext;
	wire [`PART_SEL_BITS-1:0] part_sel;
	wire sweep_sign;

`ifdef PIPELINE
	pwls_state_decoder #(.SHIFT_COUNT_BITS(SHIFT_COUNT_BITS), .DETUNE_EXP_BITS(DETUNE_EXP_BITS), .SLOPE_EXP_BITS(SLOPE_EXP_BITS), .OUT_RSHIFT(OUT_RSHIFT), .BITS(BITS)) state_decoder_early(
		.state(state), .extra_term(extra_term),
		TODO: step_part_enables

		.src1_sel_out(src1_sel),
		.keep_exp_on_top_out(keep_exp_on_top),
`ifdef PIPELINE_SRC2
		.src2_sel_out(src2_sel),
`endif
`ifdef PIPELINE_SRC2_LSHIFT
		.src2_lshift_out(src2_lshift_early),
`endif
/*
		.src2_lshift_extra(src2_lshift_extra), .src2_rot(src2_rot), .src2_forward_extra_bit_out(src2_forward_extra_bit), .src2_mask_msbs(src2_mask_msbs), .src1_en(src1_en), .inv_src1(inv_src1), .inv_src2(inv_src2), .carry_in(carry_in), .sat_en(sat_en),
		.pred_we(pred_we), .part_we(part_we),
		.dest_sel(dest_sel),
		.pred_next_use_cmp(pred_next_use_cmp),
		.replace_src2_with_amp(replace_src2_with_amp), .src2_sext(src2_sext)
*/

		.osc_shift(osc_shift), .oct_enable(oct_enable), .acc_sign(acc[BITS-1]), .pred(pred), .part(part), .first_term(first_term), .sub_channel(sub_channel),
		.detune_exp(detune_exp), .slope_exp(slope_exp), .channel_mode(channel_mode), .sweep_dir(sweep_dir), .sweep_index(sweep_index)
	);
`endif

	pwls_state_decoder #(.SHIFT_COUNT_BITS(SHIFT_COUNT_BITS), .DETUNE_EXP_BITS(DETUNE_EXP_BITS), .SLOPE_EXP_BITS(SLOPE_EXP_BITS), .OUT_RSHIFT(OUT_RSHIFT), .BITS(BITS)) state_decoder_late(
		.state(state_late), .extra_term(extra_term_late),
`ifdef USE_TEST_INTERFACE
		.step_part_enables(step_part_enables),
`endif

		.osc_shift(osc_shift), .oct_enable(oct_enable), .acc_sign(acc[BITS-1]), .pred(pred), .part(part), .first_term(first_term), .sub_channel(sub_channel),
		.detune_exp(detune_exp), .slope_exp(slope_exp), .channel_mode(channel_mode), .sweep_dir(sweep_dir), .sweep_index(sweep_index),

`ifndef PIPELINE
		.src1_sel_out(src1_sel),
		.keep_exp_on_top_out(keep_exp_on_top),
`endif
`ifndef PIPELINE_SRC2
		.src2_sel_out(src2_sel),
`endif
`ifndef PIPELINE_SRC2_LSHIFT
		.src2_lshift_out(src2_lshift_early),
`endif

		.src2_lshift_extra_out(src2_lshift_extra), .src2_rot_out(src2_rot), .src2_forward_extra_bit_out(src2_forward_extra_bit),
		.src2_mask_msb_out(src2_mask_msbs), .mask_out_acc_top_out(mask_out_acc_top),
		.src1_en_out(src1_en), .inv_src1_out(inv_src1), .inv_src2_out(inv_src2), .carry_in_out(carry_in), .sat_en_out(sat_en),
		.pred_we_out(pred_we), .part_we_out(part_we),
		.dest_sel_out(dest_sel),
		.pred_next_use_cmp_out(pred_next_use_cmp), .pred_next_use_lfsr_out(pred_next_use_lfsr), .part_sel_out(part_sel),
		.replace_src2_with_amp_out(replace_src2_with_amp), .src2_sext_out(src2_sext), .reg_we_out(reg_we), .sweep_sign_out(sweep_sign)
	);


	wire [17:0] detune_src_full = oct_counter >> 6;
	wire [15:0] detune_src_16;
	assign detune_src_16[13:0] = detune_src_full >> 2;
	assign detune_src_16[15:14] = detune_exp[2] ? detune_src_full[1:0] : detune_src_full[17:16];
	wire [15:0] detune_src = {detune_src_16[4:0], detune_src_16[15:5]};

	wire [LFSR_STATE_BITS-1:0] lfsr_state = {lfsr_extra_bits, phase_external[BITS-1:1]};
	// left shift by one, just like the phase
	wire [LFSR_EXTRA_BITS-1:0] lfsr_extra_bits_next = lfsr_state[LFSR_STATE_BITS-1-1 -: LFSR_EXTRA_BITS];

	always_ff @(posedge clk) begin
		if (reset) begin
			lfsr_extra_bits <= 0; // Needed?
		end else begin
			// Update condition is matched with update condition for phase for LFSR
			if (en && dest_sel == `DEST_SEL_PHASE && !pred && channel_mode[`CHANNEL_MODE_BIT_NOISE]) lfsr_extra_bits <= lfsr_extra_bits_next;
		end
`ifdef USE_TEST_INTERFACE
		if (ireg_waddr == `TST_ADDR_LFSR_EXTRA_BITS) lfsr_extra_bits <= ireg_wdata;
`endif
	end

	// 11 bit LFSR
	//wire lfsr_bit = lfsr_state[10] ^ lfsr_state[8];
	//wire lfsr_bit = lfsr_state[10] ^ lfsr_state[8] ^ !lfsr_state[9:0]; // include zero state
	//wire lfsr_bit = lfsr_state[10] ^ (lfsr_state[8] | !lfsr_state[9:0]); // include zero state

	// 3 bit LFSR
	//wire lfsr_bit = lfsr_state[2] ^ (lfsr_state[0] | !lfsr_state[1:0]); // include zero state

	// 15 bit LFSR
	//wire lfsr_bit = lfsr_state[14] ^ (lfsr_state[0] | !lfsr_state[13:0]); // include zero state

	// 18 bit LFSR
	wire lfsr_bit = lfsr_state[17] ^ (lfsr_state[6] | !lfsr_state[16:0]); // include zero state

	// Not registers
	reg signed [BITS_E-1:0] src1;
	reg signed [15:0] src2;
	always_comb begin
		case (src1_sel)
			//`SRC1_SEL_PHASE: src1 = phase;
			`SRC1_SEL_PHASE: src1 = src1_external;
			`SRC1_SEL_OUT_ACC: src1 = out_acc;
			
			/*
			`SRC1_SEL_MANTISSA: src1 = mantissa;
			`SRC1_SEL_TRI_OFFSET: src1 = tri_offset;
			`SRC1_SEL_SLOPE_OFFSET: src1 = slope_offset;
			`SRC1_SEL_AMP: src1 = amp;
			*/

			`SRC1_SEL_ZERO: src1 = 0;
			default: src1 = src1_external;
		endcase
		case (src2_sel)
			//`SRC2_SEL_ACC: src2 = {{(16-BITS){1'bX}}, acc};
			`SRC2_SEL_ACC: begin
				src2 = {{(16-BITS_E){1'b0}}, acc};
/*
`ifdef PIPELINE_SRC2
				// Forward result
				// Note: This is the only way to write result into acc with src2 pipelining enabled, make sure to use src2_sel = `SRC2_SEL_ACC as default!
				if (dest_sel == `DEST_SEL_ACC) src2 = {{(16-BITS){1'bX}}, result};
`endif
*/
			end
			`SRC2_SEL_REV_PHASE: src2 = {{(16-BITS){1'bX}}, rev_phase};
			`SRC2_SEL_PHASE_STEP: src2 = {{(16-BITS){1'bX}}, osc_step};
			`SRC2_SEL_DETUNE: src2 = detune_src;
			`SRC2_SEL_PHASE_MODIFIED: src2 = {{(16-BITS){1'bX}}, 1'b0, phase_external[BITS-1-1:1], lfsr_bit};
			`SRC2_SEL_ZERO: src2 = 0;
			default: src2 = 'X;
		endcase

`ifdef PIPELINE_SRC2
		// Forward result
		// Note: This is the only way to write result into acc with src2 pipelining enabled, make sure to use src2_sel = `SRC2_SEL_ACC as default!
		if (dest_sel == `DEST_SEL_ACC && src2_sel == `SRC2_SEL_ACC) src2 = {{(16-BITS){1'bX}}, result};
`endif
	end

`ifdef PIPELINE
	// pipelining
	reg signed [BITS_E-1:0] src1_in0;
	always_ff @(posedge clk) if (en) src1_in0 <= src1;
`else
	wire signed [BITS_E-1:0] src1_in0 = src1;
`endif

`ifdef PIPELINE_SRC2
	wire signed [15:0] src2_in0 = acc;
`else
	wire signed [15:0] src2_in0 = src2;
`endif

`ifdef PIPELINE_SRC2_LSHIFT
	reg [SHIFT_COUNT_BITS-1:0] src2_lshift;
	always_ff @(posedge clk) if (en) src2_lshift <= src2_lshift_early;
`else
	wire [SHIFT_COUNT_BITS-1:0] src2_lshift = src2_lshift_early;
`endif

	//wire signed [BITS-1:0] src1_in = (src1_en && !mask_out_acc_top) ? src1_in0 : '0;
	reg signed [BITS_E-1:0] src1_in; // not a register
	always_comb begin
		src1_in = src1_in0;
		if (!src1_en) src1_in = '0;
		if (mask_out_acc_top) src1_in[BITS_E-1:OUT_ACC_FRAC_BITS] = OUT_ACC_INITIAL_TOP;
	end

	// wire [BITS-1:0] src2_in = replace_src2_with_amp ? amp : src2_in0;
	//wire [BITS-1:0] src2_in = replace_src2_with_amp ? src1_external : src2_in0; // Feed in amp through src1_external in this case
	wire [15:0] src2_in = replace_src2_with_amp ? amp_external : src2_in0;

	wire equal;
	pwls_ALU #(.BITS(BITS), .BITS_E(BITS_E), .SHIFT_COUNT_BITS(SHIFT_COUNT_BITS), .OUT_RSHIFT(OUT_RSHIFT), .REV_PHASE_SHR(REV_PHASE_SHR), .AMP_BITS(AMP_BITS)) alu(
		.clk(clk), .reset(reset),
		.src1_in(src1_in), .src2_in(src2_in), .src2_rot(src2_rot), .src2_forward_extra_bit(src2_forward_extra_bit), .src2_lshift(src2_lshift + src2_lshift_extra), .src2_sext(src2_sext),
		.src2_mask_msbs(src2_mask_msbs), .inv_src1(inv_src1), .inv_src2(inv_src2), .carry_in(carry_in), .sat_en(sat_en),
		.result(result), .cmp_result(cmp_result), .delayed(delayed), .equal(equal)
	);

	// delayed is based on rev_phase, which is based on phase_external
	wire pred_next_osc = cmp_result || delayed; // small_step
	wire pred_next_lfsr = cmp_result && !phase_external[0]; // small_step for LFSR
	wire pred_next_cmp = result[BITS-1] ^ acc[BITS-1]; // slope_out = pred_next_cmp ? 2*acc : acc +- slope_offset
	wire pred_next = pred_next_use_cmp ? pred_next_cmp : (pred_next_use_lfsr ? pred_next_lfsr : pred_next_osc);


	wire is_period_sweep = (sweep_index == `SWEEP_INDEX_PERIOD); // CONSIDER: = !pre_sweep_index[0]
	wire all_zeros = (acc[7:0] ==  0) && (!is_period_sweep || (acc[12:8] ==  0));
	wire all_ones  = (acc[7:0] == '1) && (!is_period_sweep || (acc[12:8] == '1));
	wire sweep_sat = sweep_sign == 0 ? all_ones : all_zeros;

	//wire part_next = part_next_use_neq ? !equal : acc[BITS-1];
	reg part_next; // not a register
	always_comb begin
		case (part_sel)
			`PART_SEL_ACC_MSB: part_next = acc[BITS-1];
			`PART_SEL_SWEEP: part_next = sweep_index[0];
			`PART_SEL_NEQ: part_next = !equal;
			`PART_SEL_NOSAT: part_next = !sweep_sat;
			default: part_next = 'X;
		endcase
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			//phase <= 0;

			// TODO: needed?
			acc <= 0;
			pred <= 0;
			part <= 0;
			out_acc <= 0;
		end else if (en) begin
`ifdef PIPELINE_SRC2
			acc <= src2; // Use acc as pipeline register for src2
`endif
			case (dest_sel)
				//`DEST_SEL_PHASE: phase <= result;
`ifndef PIPELINE_SRC2
				`DEST_SEL_ACC: acc <= result;
`endif
				`DEST_SEL_OUT_ACC: out_acc <= result;
				default: ;
			endcase
			if (pred_we) pred <= pred_next;
			if (part_we) part <= part_next;
		end

`ifdef USE_TEST_INTERFACE
		if (ireg_waddr == `TST_ADDR_ACC) acc <= ireg_wdata;
		if (ireg_waddr == `TST_ADDR_OUT_ACC) out_acc <= ireg_wdata;
		if (ireg_waddr == `TST_ADDR_PRED) pred <= ireg_wdata;
		if (ireg_waddr == `TST_ADDR_PART) part <= ireg_wdata;
`endif
	end

	assign src1_sel_out = src1_sel;
	assign dest_sel_out = dest_sel;

	assign acc_out = acc;
	
	//assign out_acc_out = out_acc;
	reg [BITS-1:0] out_acc_out0; // not a register
	always_comb begin
		out_acc_out0 = out_acc;
		if (OUT_ACC_FRAC_BITS > 0) out_acc_out0[OUT_ACC_FRAC_BITS-1:0] = '0;
	end
	assign out_acc_out = out_acc_out0;
	assign part_out = part;
	assign sample_counter = oct_counter;


`ifdef USE_TEST_INTERFACE
	always_comb begin
		ireg_rdata = -1;
		case (ireg_raddr)
			`TST_ADDR_ACC: ireg_rdata = acc;
			`TST_ADDR_OUT_ACC: ireg_rdata = out_acc;
			`TST_ADDR_PRED: ireg_rdata = pred;
			`TST_ADDR_PART: ireg_rdata = part;
			`TST_ADDR_LFSR_EXTRA_BITS: ireg_rdata = lfsr_extra_bits;
			`TST_ADDR_OCT_COUNTER: ireg_rdata = oct_counter;
		endcase
	end
`endif
endmodule : pwls_ALU_unit


// pwls_ALU_unit wrapped for multichannel use
module pwls_multichannel_ALU_unit #(parameter BITS=12, BITS_E=13, SHIFT_COUNT_BITS=4, OCT_BITS=3, MANTISSA_BITS=10, DETUNE_EXP_BITS=3, SLOPE_EXP_BITS=4, NUM_CHANNELS=4, DETUNE_ON=1, OUT_ACC_FRAC_BITS=4, LFSR_HIGHEST_OCT=2) (
		input wire clk, reset,
		// Usage of en and next_en:
		// - en = 0 pauses the synth's updates
		// - If en = 1, the cycle before must have next_en = 1 (or be the first cycle after reset)
		// - To make a read, through reg_raddr_p,
		//   - Set next_en = 0, next_reg_raddr_p = read address the cycle before
		//   - Set en = 0, reg_raddr_p = read address on the cycle of the read
		en, next_en,

		input wire [`REG_ADDR_BITS-1:0] reg_waddr,
		input wire [`REG_BITS-1:0] reg_wdata,
		input wire reg_we,
		input wire control_reg_write, state_reg_write, // Which part of registers to update?

		input wire [`REG_ADDR_BITS-1:0] reg_raddr_p, next_reg_raddr_p, // next_reg_raddr_p must be one cycle ahead of reg_raddr_p when reading
		output wire [`REG_BITS-1:0] reg_rdata_p, // valid when `en` is low

`ifdef USE_NEW_READ
		input wire [`REG_ADDR_BITS-1:0] reg_raddr,
		input wire reg_raddr_valid,
		output wire [`REG_BITS] reg_rdata,
		output wire reg_rdata_valid_next,
`endif

		// temporary global controls
		//input wire [DETUNE_EXP_BITS-1:0] detune_exp,
		input wire signed [BITS-1:0] tri_offset, // includes offset to convert to signed
		input wire [SLOPE_EXP_BITS-1:0] slope_exp,
		input wire [BITS-3-1:0] slope_offset,
		//input wire [BITS-2-1:0] amp,

`ifdef USE_TEST_INTERFACE
		input wire state_override_en,
		input int state_override, // (term_index << 8) || state
		input wire [1:0] step_part_enables, // {post_en, main_en}
		// interface for internal registers
		input int ireg_raddr, ireg_waddr,
		output int ireg_rdata,
		input int ireg_wdata,
		// expose internal register writes
		output wire reg_we_internal_out,
		output int reg_waddr_internal_out,
		output int reg_wdata_internal_out,
`endif

		// for debug
		output int term_index_out,
		output wire [`STATE_BITS-1:0] state_out,
		output wire [BITS-1:0] tri_offset_eff_out,
		output wire [15:0] curr_params_out,

		output wire new_out_acc,
		output wire [BITS-1:0] phase_out, out_acc_out,
		output wire [BITS_E-1:0] acc_out,
		output wire pwm_out,
		output int pwm_out_offset
	);

	localparam AMP_BITS = 6;

	localparam OUT_ACC_INITIAL_TOP = 512 >> OUT_ACC_FRAC_BITS;
	assign pwm_out_offset = OUT_ACC_INITIAL_TOP;

	localparam CHANNEL_TIMES = DETUNE_ON ? 2 : 1;
	localparam OUT_RSHIFT = DETUNE_ON ? 4: 3;

	localparam LOG2_CHANNELS = $clog2(NUM_CHANNELS);
	localparam NUM_WF_TERMS = NUM_CHANNELS * CHANNEL_TIMES;
	localparam NUM_TERMS = NUM_WF_TERMS + 1;
	localparam LOG2_TERMS = $clog2(NUM_TERMS);

	// Number of states for the non-wf updates, not more than 2**`STATE_BITS
	localparam NUM_EXTRA_STATES = 8;

	localparam PERIOD_BITS = OCT_BITS + MANTISSA_BITS;

	localparam PHASE_BITS = BITS;
	localparam REV_PHASE_SHR = (PHASE_BITS-1) - MANTISSA_BITS;


	genvar i;


	wire curr_sub_channel;
	wire [`SRC1_SEL_BITS-1:0] src1_sel;
	wire keep_exp_on_top;
	wire part;
	wire [`DIVIDER_BITS-1:0] sample_counter;


	reg [LOG2_TERMS-1:0] term_index;
	reg [`STATE_BITS-1:0] state;
	reg write_collision;

	// not registers
	reg [LOG2_TERMS-1:0] term_index_eff;
	reg [`STATE_BITS-1:0] state_eff;
	always_comb begin
		term_index_eff = term_index;
		state_eff = state;
`ifdef USE_TEST_INTERFACE
		if (state_override_en) begin
			term_index_eff = state_override[15:8];
			state_eff = state_override[7:0];
		end
`endif
	end

	// High if this is a waveform term
	//wire wf_term = (term_index_eff != NUM_WF_TERMS);
	wire wf_term = !term_index_eff[LOG2_TERMS-1]; // special case for NUM_CHANNELS = power of 2
	wire last_term = !wf_term; // is this the last term?
	wire extra_term = !wf_term; // is this a term for extra updates? (no actual term...)


	// Internal register write interface
	wire reg_we_internal;
	wire [`REG_ADDR_BITS-1:0] reg_waddr_internal;
	wire [`REG_BITS-1:0] reg_wdata_internal = acc_out; // always write from acc


	// Check if an external write comes to the register that a sweep is currently trying to update
	always_ff @(posedge clk) write_collision <= extra_term && (write_collision || (reg_we && (reg_waddr == reg_waddr_internal)));

	// Prioritize external writes, pause if we get one and it collides with an internal write
	wire en_eff = en && !(reg_we && reg_we_internal);
	wire reg_we_eff = (reg_we && control_reg_write) || (reg_we_internal && !write_collision);
	wire reg_cfg_we = reg_we && state_reg_write;

	wire [`REG_ADDR_BITS-1:0] reg_waddr_eff = reg_we ? reg_waddr : reg_waddr_internal;
	wire [`REG_BITS-1:0]      reg_wdata_eff = reg_we ? reg_wdata : reg_wdata_internal;


`ifdef USE_PHASE_LATCHES
	localparam PHASE_INDEX = 4'd8;
	wire [BITS-1:0] phases[NUM_CHANNELS];
`else
	(* mem2reg *) reg [BITS-1:0] phases[NUM_CHANNELS];
`endif


/*
	(* mem2reg *) reg [PERIOD_BITS-1:0] periods[NUM_CHANNELS];
	(* mem2reg *) reg [AMP_BITS-1:0] amps[NUM_CHANNELS];
	(* mem2reg *) reg [`CHANNEL_MODE_BITS-1:0] modes[NUM_CHANNELS];
`ifdef USE_PARAMS_REGS
	(* mem2reg *) reg [15:0] params[NUM_CHANNELS];
`endif
*/

	wire [PERIOD_BITS-1:0] periods[NUM_CHANNELS];
	wire [AMP_BITS-1:0] amps[NUM_CHANNELS];
	wire [`CHANNEL_MODE_BITS-1:0] modes[NUM_CHANNELS];

`ifdef USE_NEW_REGMAP
	// Both slope and pwm_offset are limited to 8 bits; seems to sound fine
	wire [7:0] slopes0[NUM_CHANNELS];
	wire [7:0] slopes1[NUM_CHANNELS];
	wire [7:0] pwm_offsets[NUM_CHANNELS]; // tri_offset register

	wire [4:0] sweep_periods[NUM_CHANNELS];
	wire [6:0] sweep_amps[NUM_CHANNELS];
	wire [6:0] sweep_slopes[NUM_CHANNELS];
	wire [4:0] sweep_pwm_offsets[NUM_CHANNELS];
`ifdef USE_NEW_REGMAP_B
	wire [15:0] sweeps0[NUM_CHANNELS];
	wire [15:0] sweeps1[NUM_CHANNELS];
`endif

`else

`ifdef USE_PARAMS_REGS
	wire [15:0] params[NUM_CHANNELS];
`endif
`ifdef USE_SWEEP_REGS
	wire [11:0] sweeps[NUM_CHANNELS];
`endif

`endif


	wire [`REG_BITS-1:0] reg_wdata2;
	pwls_shared_data #(.BITS(`REG_BITS)) shared_data(.clk(clk), .reset(reset), .in(reg_wdata_eff), .out(reg_wdata2));
	generate
		for (i = 0; i < NUM_CHANNELS; i++) begin
`ifdef USE_NEW_REGMAP

			// Register parts that can be changed by the synth and the user
			pwls_register #(.BITS(PERIOD_BITS))        periods_reg(.clk(clk), .reset(reset), .we( 0+i == reg_waddr_eff && reg_we_eff), .wdata(reg_wdata2), .rdata(periods[i]));
			pwls_register #(.BITS(AMP_BITS))           amps_reg(   .clk(clk), .reset(reset), .we( 4+i == reg_waddr_eff && reg_we_eff), .wdata(reg_wdata2), .rdata(amps[i]));
			pwls_register #(.BITS(8))                  slope0_reg( .clk(clk), .reset(reset), .we( 8+i == reg_waddr_eff && reg_we_eff), .wdata(reg_wdata2), .rdata(slopes0[i]));
			pwls_register #(.BITS(8))                  slope1_reg( .clk(clk), .reset(reset), .we(12+i == reg_waddr_eff && reg_we_eff), .wdata(reg_wdata2), .rdata(slopes1[i]));
			pwls_register #(.BITS(8))                  pwmoffs_reg(.clk(clk), .reset(reset), .we(16+i == reg_waddr_eff && reg_we_eff), .wdata(reg_wdata2), .rdata(pwm_offsets[i]));


			pwls_register #(.BITS(`CHANNEL_MODE_BITS)) modes_reg(  .clk(clk), .reset(reset), .we(20+i == reg_waddr_eff && reg_cfg_we), .wdata(reg_wdata2), .rdata(modes[i]));

`ifdef USE_NEW_REGMAP_B
			pwls_register #(.BITS(16))                 sweep0_reg( .clk(clk), .reset(reset), .we(24+i == reg_waddr_eff && reg_cfg_we), .wdata(reg_wdata2), .rdata(sweeps0[i]));
			pwls_register #(.BITS(16))                 sweep1_reg( .clk(clk), .reset(reset), .we(28+i == reg_waddr_eff && reg_cfg_we), .wdata(reg_wdata2), .rdata(sweeps1[i]));

			assign sweep_periods[i]     = sweeps0[i][15:8];
			assign sweep_amps[i]        = sweeps0[i][7:0];
			assign sweep_pwm_offsets[i] = sweeps1[i][15:8];
			assign sweep_slopes[i]      = sweeps1[i][7:0];
`else
			// Register parts that can only be changed by the user
			pwls_register #(.BITS(5))               sw_periods_reg(.clk(clk), .reset(reset), .we( 0+i == reg_waddr_eff && reg_cfg_we), .wdata(reg_wdata2[17:13]), .rdata(sweep_periods[i]));
			pwls_register #(.BITS(7))               sw_amps_reg(   .clk(clk), .reset(reset), .we( 4+i == reg_waddr_eff && reg_cfg_we), .wdata(reg_wdata2[15:8]),  .rdata(sweep_amps[i]));
			pwls_register #(.BITS(7))               sw_slope0_reg( .clk(clk), .reset(reset), .we( 8+i == reg_waddr_eff && reg_cfg_we), .wdata(reg_wdata2[15:8]),  .rdata(sweep_slopes[i]));
//			pwls_register #(.BITS(5))               sw_slope1_reg( .clk(clk), .reset(reset), .we(12+i == reg_waddr_eff && reg_cfg_we), .wdata(reg_wdata2[15:8]),  .rdata(sweep_slope1[i]));
			pwls_register #(.BITS(5))               sw_pwmoffs_reg(.clk(clk), .reset(reset), .we(16+i == reg_waddr_eff && reg_cfg_we), .wdata(reg_wdata2[15:8]),  .rdata(sweep_pwm_offsets[i]));
`endif

`else
			// Allow register writes even when en is low
			pwls_register #(.BITS(PERIOD_BITS))        periods_reg(.clk(clk), .reset(reset), .we( 0+i == reg_waddr_eff && reg_we_eff), .wdata(reg_wdata2), .rdata(periods[i]));
			pwls_register #(.BITS(AMP_BITS))           amps_reg(   .clk(clk), .reset(reset), .we( 4+i == reg_waddr_eff && reg_we_eff), .wdata(reg_wdata2), .rdata(amps[i]));
			pwls_register #(.BITS(`CHANNEL_MODE_BITS)) modes_reg(  .clk(clk), .reset(reset), .we( 8+i == reg_waddr_eff && reg_we_eff), .wdata(reg_wdata2), .rdata(modes[i]));
`ifdef USE_PARAMS_REGS
			pwls_register #(.BITS(16))                 params_reg( .clk(clk), .reset(reset), .we(12+i == reg_waddr_eff && reg_we_eff), .wdata(reg_wdata2), .rdata(params[i]));
`endif
`ifdef USE_SWEEP_REGS
			pwls_register #(.BITS(12))                 sweep_reg(  .clk(clk), .reset(reset), .we(16+i == reg_waddr_eff && reg_we_eff), .wdata(reg_wdata2), .rdata(sweeps[i]));
`endif
`endif

`ifdef USE_PHASE_LATCHES
			pwls_register #(.BITS(PHASE_BITS))        phases_reg( .clk(clk), .reset(reset), .we( 4*PHASE_INDEX+i == reg_waddr_eff && reg_we_eff), .wdata(reg_wdata2), .rdata(phases[i]));
`endif
		end
	endgenerate

	// Sample out_acc on the first cycle of the new sample, then it should just have been update. CONSIDER: better time/condition to use?
	wire sample_out_acc = (state_eff == '0 && term_index_eff == '0) && en_eff;


	wire [`STATE_BITS+1-1:0] state_inc = state_eff + en_eff;
	wire next_term_if_en = (state_eff == (wf_term ? `STATE_LAST : NUM_EXTRA_STATES-1));
	wire next_term = next_term_if_en && en_eff;
	wire [LOG2_TERMS-1:0] next_term_index = term_index_eff + next_term;
	wire next_sample = next_term && last_term; // also gated by en_eff
	wire oct_counter_we = next_sample;
	always_ff @(posedge clk) begin
		// Skip oscillator update second time. NOTE: Be careful not to change initial state going into extra_term!
		if (reset || next_term) state <= !reset && DETUNE_ON && (wf_term && curr_sub_channel == 0) ? `STATE_DETUNE : 0;
		else                    state <= state_inc;

		if (reset || next_sample) term_index <= 0;
		else                      term_index <= next_term_index;
	end

	wire next_extra_term = next_term ? (term_index_eff == NUM_WF_TERMS-1) : extra_term;


	/*
	wire [LOG2_CHANNELS-1:0] sweep_channel = sample_counter[LOG2_CHANNELS-1:0];
	assign reg_waddr_internal = sweep_channel;
	*/

	wire [LOG2_CHANNELS-1:0] sweep_channel;
	//wire [`SWEEP_INDEX_BITS-1:0] sweep_index;
	//assign {sweep_index, sweep_channel} = sample_counter[LOG2_CHANNELS+`SWEEP_INDEX_BITS-1:0];
	//assign sweep_channel = sample_counter[LOG2_CHANNELS-1:0];
	//assign sweep_index = 0;
	//assign sweep_index = sample_counter[LOG2_CHANNELS];
	wire [2:0] pre_sweep_index;
	assign {pre_sweep_index, sweep_channel} = sample_counter[LOG2_CHANNELS+3-1:0];

	// Not a register
	reg [`SWEEP_INDEX_BITS-1:0] sweep_index;
	always_comb begin
		sweep_index = pre_sweep_index[2:1];
		if (sweep_index == 0) sweep_index = 4;
		if (pre_sweep_index[0] == 0) sweep_index = 0;
	end


	//wire [`DIVIDER_BITS-1:0] sweep_oct_counter_term = 4;
	//wire [`DIVIDER_BITS-1:0] sweep_oct_counter_term = 8; // All sweeps are applied every 8th sample right now
	wire [`DIVIDER_BITS-1:0] sweep_oct_counter_term = pre_sweep_index[0] == 0 ? 8 : 32; // Period sweeps are applied every 8 samples, the others every 32 samples

	// NOTE: Update if sweep mapping changes
	wire [`REG_ADDR_BITS-1:0] reg_waddr_sweep = {sweep_index, sweep_channel};



	//wire [LOG2_CHANNELS-1:0] curr_channel = en_eff ? term_index_eff >> $clog2(CHANNEL_TIMES) : reg_raddr_p[1:0];
	wire [LOG2_CHANNELS-1:0] curr_channel_0 = en_eff ? (extra_term ? sweep_channel : term_index_eff >> $clog2(CHANNEL_TIMES)) : reg_raddr_p[1:0];

	// Ok to use current sweep_channel, won't change the cycle before we need it
	wire [LOG2_CHANNELS-1:0] next_curr_channel = next_en ? (next_extra_term ? sweep_channel : next_term_index >> $clog2(CHANNEL_TIMES)) : next_reg_raddr_p[1:0];

/*
	wire [LOG2_CHANNELS-1:0] curr_channel;
	named_buffer #(.BITS(LOG2_CHANNELS)) nb_curr_channel(.in(curr_channel_0), .out(curr_channel));
*/



`ifdef PIPELINE_CURR_CHANNEL
	reg [LOG2_CHANNELS-1:0] curr_channel;
	always_ff @(posedge clk) if (reset || en_eff) curr_channel <= reset ? '0 : next_curr_channel;
`else
	wire [LOG2_CHANNELS-1:0] curr_channel = curr_channel_0;
`endif
	wire dbg_curr_channel_mismatch = (curr_channel != curr_channel_0);



`ifdef USE_PHASE_LATCHES
	assign reg_waddr_internal = extra_term ? reg_waddr_sweep : {PHASE_INDEX, curr_channel};
`else
	assign reg_waddr_internal = reg_waddr_sweep;
`endif



	assign curr_sub_channel = DETUNE_ON ? term_index_eff[0] : 0;

	wire [BITS-1:0] curr_phase = phases[curr_channel];
	wire [PERIOD_BITS-1:0] curr_period = periods[curr_channel];

	//wire [AMP_BITS-1:0] amp = amps[curr_channel];
	wire [BITS-2-1:0] amp = {amps[curr_channel], {(BITS-2-6){1'b0}}};
	wire [`CHANNEL_MODE_BITS-1:0] channel_mode = modes[curr_channel];

	wire [DETUNE_EXP_BITS-1:0] detune_exp = channel_mode[2:0];

`ifdef USE_NEW_REGMAP
	// New register map
	// ----------------
	// ### slope
	wire [7:0] slope0 = slopes0[curr_channel];
	wire [7:0] slope1 = slopes1[curr_channel];
	wire [7:0] slope = part ? slope1 : slope0;

	wire [SLOPE_EXP_BITS-1:0] slope_exp_eff = slope[7:4];
	wire [BITS-3-1:0] slope_offset_eff = {slope[3:0], {(BITS-3-4){1'b0}}};

	// ### pwm_offset
	wire [7:0] pwm_offset = pwm_offsets[curr_channel];
	wire signed [BITS-1:0] tri_offset_eff = {2'b11, pwm_offset, {(BITS-2-8){1'b0}}};

	// ### sweeps
	wire [4:0] curr_sweep_period     = sweep_periods[curr_channel];
	wire [6:0] curr_sweep_amp        = sweep_amps[curr_channel];
	wire [6:0] curr_sweep_slope      = sweep_slopes[curr_channel];
	wire [4:0] curr_sweep_pwm_offset = sweep_pwm_offsets[curr_channel];
	// Replicate 3 bits twice to save on some bits for amp_target
	wire [AMP_BITS-1:0] amp_target = {curr_sweep_amp[6:4], curr_sweep_amp[6:4]};

	// not registers
	reg [`SWEEP_DIR_BITS-1:0] sweep_dir;
	reg [3:0] curr_sweep;
	always_comb begin
		case (sweep_index)
			`SWEEP_INDEX_PERIOD:                      begin;  curr_sweep = curr_sweep_period[3:0];      sweep_dir = {2'b11, curr_sweep_period[4]};     end
			`SWEEP_INDEX_AMP:                         begin;  curr_sweep = curr_sweep_amp[3:0];         sweep_dir = 3'b11X;                            end
			`SWEEP_INDEX_SLOPE0, `SWEEP_INDEX_SLOPE1: begin;  curr_sweep = curr_sweep_slope[3:0];       sweep_dir = curr_sweep_slope[6:4];             end
			`SWEEP_INDEX_PWM_OFFSET:                  begin;  curr_sweep = curr_sweep_pwm_offset[3:0];  sweep_dir = {2'b11, curr_sweep_pwm_offset[4]}; end
			default: begin  curr_sweep = 'X; sweep_dir = 'X;  end
		endcase
	end

`else 
	// Old register map
	// ----------------

`ifdef USE_SLOPE_EXP_REGS
	wire [SLOPE_EXP_BITS-1:0] slope_exp_eff = part ? channel_mode[11:8] : channel_mode[7:4];
`else
	wire [SLOPE_EXP_BITS-1:0] slope_exp_eff = slope_exp;
`endif

`ifdef USE_PARAMS_REGS
	wire [15:0] curr_params = params[curr_channel];
	wire signed [BITS-1:0] tri_offset_eff = {2'b11, curr_params[15:8], {(BITS-2-8){1'b0}}};
	wire [3:0] slope_offset_0 = part ? curr_params[7:4] : curr_params[3:0];
	wire [BITS-3-1:0] slope_offset_eff = {slope_offset_0, {(BITS-3-4){1'b0}}};
`else
	wire signed [BITS-1:0] tri_offset_eff = tri_offset;
	wire [BITS-3-1:0] slope_offset_eff = slope_offset;
`endif

`ifdef USE_SWEEP_REGS
	//wire [4:0] curr_sweep = sweeps[curr_channel];
	wire [11:0] curr_sweep0 = sweeps[curr_channel];
	wire [4:0] curr_sweep = (sweep_index == `SWEEP_INDEX_PERIOD) ? curr_sweep0[4:0] : curr_sweep0[9:5];
	wire sweep_sign = curr_sweep[4];
	// Replicate 3 bits twice to save on some bits for amp_target
	wire [AMP_BITS-1:0] amp_target = {curr_sweep0[11:9], curr_sweep0[11:9]}; // sweep_sign is not used for amp
`else
	wire sweep_sign = 0;
`endif

`endif


	wire oct_enable_index_override_en = extra_term;
	wire [3:0] oct_enable_index_override = curr_sweep[3:0];
	wire hard_oct_enable_override_en = (oct_enable_index_override[3:1] == '0); // 0 or 1
	wire hard_oct_enable_override = oct_enable_index_override[0];
	// TODO: update based on how often we sweep the given parameter
	wire [`DIVIDER_BITS-1:0] oct_counter_term = (extra_term && !next_term_if_en) ? sweep_oct_counter_term : 1; // must set to 1 when oct_counter_we, or we get wrong increments



	reg [`REG_BITS-1:0] rdata; // not a register
	always_comb begin
		rdata = 'X;
		case (reg_raddr_p[`REG_ADDR_BITS-1:2])
			0: rdata = curr_period;
			1: rdata = amp >> (BITS-2-6);
`ifdef USE_NEW_REGMAP
			2: rdata = slope0;
			3: rdata = slope1;
			4: rdata = pwm_offset;
			5: rdata = channel_mode;
`else
			2: rdata = channel_mode;
`ifdef USE_PARAMS_REGS
			3: rdata = curr_params;
`endif
`ifdef USE_SWEEP_REGS
			4: rdata = curr_sweep;
`endif
`endif
			default: rdata = 'X;
		endcase
	end
	assign reg_rdata_p = rdata;


	wire [OCT_BITS-1:0] octave;
	wire [MANTISSA_BITS-1:0] mantissa;
	//wire [BITS-2:0] mantissa_ext;
	assign {octave, mantissa} = curr_period;
	//assign mantissa_ext = {mantissa, {((BITS-1) - MANTISSA_BITS){1'b0}}};


	reg signed [BITS_E-1:0] src1; // not a register
	always_comb begin
		case (src1_sel)
			`SRC1_SEL_PHASE: src1 = curr_phase;
			`SRC1_SEL_MANTISSA: src1 = {keep_exp_on_top ? octave : {OCT_BITS{1'b0}}, mantissa}; //mantissa_ext;
			`SRC1_SEL_TRI_OFFSET: src1 = tri_offset_eff;
			//`SRC1_SEL_SLOPE_OFFSET: src1 = slope_offset_eff;
			`SRC1_SEL_SLOPE_OFFSET: src1 = {keep_exp_on_top ? slope_exp_eff : {SLOPE_EXP_BITS{1'b0}}, slope_offset_eff};
//			`SRC1_SEL_AMP, `SRC1_SEL_OUT_ACC, `SRC1_SEL_ZERO: src1 = amp; // Feed in amp also for `SRC1_SEL_OUT_ACC, to handle replace_src2_with_amp
			`SRC1_SEL_AMP: src1 = amp;
			`SRC1_SEL_AMP_TARGET: src1 = amp_target;
			default: src1 = 'X;
		endcase
	end

/*
	// Pipeline octave
	// TODO: Is this ok? Can we use a multicycle constraint instead?
	reg [OCT_BITS-1:0] octave_reg;
	always_ff @(posedge clk) octave_reg <= octave;
*/

	wire alu_en = en_eff;

	wire [`DEST_SEL_BITS-1:0] dest_sel;
	wire [BITS_E-1:0] result;
	pwls_ALU_unit #(
		.BITS(BITS), .BITS_E(BITS_E), .SHIFT_COUNT_BITS(SHIFT_COUNT_BITS), .OCT_BITS(OCT_BITS), .DETUNE_EXP_BITS(DETUNE_EXP_BITS), .SLOPE_EXP_BITS(SLOPE_EXP_BITS),
		.OUT_RSHIFT(OUT_RSHIFT), .OUT_ACC_FRAC_BITS(OUT_ACC_FRAC_BITS), .LFSR_HIGHEST_OCT(LFSR_HIGHEST_OCT),
		.OUT_ACC_INITIAL_TOP(OUT_ACC_INITIAL_TOP), .REV_PHASE_SHR(REV_PHASE_SHR), .AMP_BITS(AMP_BITS)
	) alu_unit(
		.clk(clk), .reset(reset), .en(alu_en),
		.state(state_eff), .extra_term(extra_term), .first_term(term_index_eff == '0), .oct_counter_we(oct_counter_we), .sub_channel(curr_sub_channel),
		.octave(octave),
		//.octave(octave_reg),
		.detune_exp(detune_exp), .slope_exp(slope_exp_eff), .channel_mode(channel_mode), .sweep_dir(sweep_dir), .sweep_index(sweep_index),
		.src1_sel_out(src1_sel), .part_out(part), .keep_exp_on_top(keep_exp_on_top),
		.src1_external(src1), .phase_external(curr_phase), .amp_external(amp),
		.dest_sel_out(dest_sel), .result(result), .reg_we(reg_we_internal),
		.hard_oct_enable_override_en(hard_oct_enable_override_en), .hard_oct_enable_override(hard_oct_enable_override),
		.oct_enable_index_override_en(oct_enable_index_override_en), .oct_enable_index_override(oct_enable_index_override), .oct_counter_term(oct_counter_term),
		.sample_counter(sample_counter),
`ifdef USE_TEST_INTERFACE
	.step_part_enables(step_part_enables),
	.ireg_raddr(ireg_raddr), .ireg_waddr(ireg_waddr), .ireg_rdata(ireg_rdata), .ireg_wdata(ireg_wdata),
`endif
		.acc_out(acc_out), .out_acc_out(out_acc_out)
	);


	generate
		for (i = 0; i < NUM_CHANNELS; i++) begin
			always_ff @(posedge clk) begin
				if (reset) begin
`ifndef USE_PHASE_LATCHES
					phases[i] <= 0;
`endif

/*
					periods[i] <= 0; // not needed?
					amps[i] <= 0; // silent
					modes[i] = 0; // turn off LFSR, detune
`ifdef USE_PARAMS_REGS
					params[i] = 0;
`endif
*/
				end else begin
`ifndef USE_PHASE_LATCHES
					if (i == curr_channel && dest_sel == `DEST_SEL_PHASE && alu_en) phases[i] <= result;
`endif

/*
					if (i == reg_waddr_eff && reg_we_eff) periods[i] <= reg_wdata_eff;
					if (4+i == reg_waddr_eff && reg_we_eff) amps[i] <= reg_wdata_eff;
					if (8+i == reg_waddr_eff && reg_we_eff) modes[i] <= reg_wdata_eff;
`ifdef USE_PARAMS_REGS
					if (12+i == reg_waddr_eff && reg_we_eff) params[i] <= reg_wdata_eff;
`endif
*/
				end
			end
		end
	endgenerate


// PWM output
// ==========
	localparam PWM_BITS = 7;

	reg [PWM_BITS-1:0] pwm_counter;

	// Stop when we reach pwm_counter = 1 << (PWM_BITS - 1), but not when it has a small negative value
	wire pwm_inc = !(pwm_counter[PWM_BITS-1] && !pwm_counter[PWM_BITS-2]);
	assign pwm_out = !pwm_inc;

	always @(posedge clk) begin
		if (sample_out_acc) pwm_counter <= out_acc_out[PWM_BITS+OUT_ACC_FRAC_BITS-1 -: PWM_BITS]; // sample_out_acc is low when en_eff is
		else pwm_counter <= pwm_counter + pwm_inc; // TODO: should it be paused when en_eff is low?
	end


// Additional outputs
// ==================

	assign phase_out = curr_phase;
	assign new_out_acc = (term_index_eff == 0) && (state_eff == 1); // should allow time for out_acc to be computed even with one cycle of pipelining

	assign term_index_out = term_index;
	assign state_out = state;

	assign tri_offset_eff_out = tri_offset_eff;

`ifdef USE_NEW_REGMAP
	assign curr_params_out = 'Z;
`else
`ifdef USE_PARAMS_REGS
	assign curr_params_out = curr_params;
`else
	assign curr_params_out = 'Z;
`endif
`endif

`ifdef USE_TEST_INTERFACE
	assign reg_we_internal_out = reg_we_internal;
	assign reg_waddr_internal_out = reg_waddr_internal;
	assign reg_wdata_internal_out = reg_wdata_internal;
`endif
endmodule : pwls_multichannel_ALU_unit
