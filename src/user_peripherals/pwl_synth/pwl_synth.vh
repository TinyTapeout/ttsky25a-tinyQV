/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`define USE_NEW_REGMAP
`ifdef USE_NEW_REGMAP
`define USE_NEW_REGMAP_B // only takes effect if USE_NEW_REGMAP is enabled
`endif

`define USE_PHASE_LATCHES
`define USE_OCT_COUNTER_LATCHES
`define USE_NEW_READ

`define USE_SLOPE_EXP_REGS
`define USE_PARAMS_REGS
`define USE_SWEEP_REGS

`define USE_3X_FLAG
`define USE_X2N_FLAGS
`define USE_COMMON_SAT
`define USE_PWL_OSC
`define USE_ORION_WAVE
`define USE_ORION_MASK
`define USE_STEREO


`ifdef USE_STEREO
`define USE_GLOBAL_CFG_REG
`endif

// Only used for verilator tests
//// `define USE_TEST_INTERFACE

`ifndef USE_NEW_READ
`define USE_OLD_READ // if defined, the old read is used either as primary or extra read mechanism
`endif
`ifdef USE_TEST_INTERFACE
`define USE_OLD_READ
`endif

`ifdef USE_NEW_REGMAP
//	`define CHANNEL_MODE_BITS 4
	`define CHANNEL_MODE_BITS 9
	`ifdef USE_NEW_REGMAP_B
		`define REGS_PER_CHANNEL 8
		`define REG_BITS 13 // Could be 13? If the registers don't grow too much
	`else
		`define USE_NEW_REGMAP_A
		`define REGS_PER_CHANNEL 6
		`define REG_BITS 18
	`endif
`else
	`define REGS_PER_CHANNEL 5
	`ifdef USE_SLOPE_EXP_REGS
		`define CHANNEL_MODE_BITS 12
	`else
		`define CHANNEL_MODE_BITS 4
	`endif
	`define REG_BITS 16
`endif

`ifdef USE_PHASE_LATCHES
	`define REG_ADDR_BITS 6
`else
	`define REG_ADDR_BITS 5
`endif


`define CFG_BIT_STEREO_EN 0


// 0-2: detune_exp
`define CHANNEL_MODE_BIT_NOISE 3
//// 4-7, 8-11: slope_exp
`define CHANNEL_MODE_BIT_3X 4
`define CHANNEL_MODE_BIT_X2N0 5
`define CHANNEL_MODE_BIT_X2N1 6
`define CHANNEL_MODE_BIT_COMMON_SAT 7
`define CHANNEL_MODE_BIT_PWL_OSC 8


`define WF_BITS 2
`define WF_OSC     0
`define WF_NOISE   1
`define WF_PWL_OSC 2
`define WF_ORION   3


`define DIVIDER_BITS 24
`define SWEEP_DIR_BITS 3

`define DETUNE_SRC_CONTROL_BITS 3
`define DETUNE_SRC_CONTROL_BIT_HIGH_OVERIDE_EN 0
`define DETUNE_SRC_CONTROL_BIT_HIGH_OVERIDE    1
`define DETUNE_SRC_CONTROL_BIT_LOW_OVERIDE_EN  2


`ifdef USE_ORION_WAVE
`define SRC1_SEL_BITS 4
`else
`define SRC1_SEL_BITS 3
`endif
`define SRC1_SEL_MANTISSA     3'd0
`define SRC1_SEL_AMP          3'd1
`define SRC1_SEL_SLOPE_OFFSET 3'd2
`define SRC1_SEL_ZERO         3'd3
`define SRC1_SEL_TRI_OFFSET   3'd4
`define SRC1_SEL_PHASE        3'd5
`define SRC1_SEL_OUT_ACC      3'd6
`define SRC1_SEL_AMP_TARGET   3'd7
`ifdef USE_ORION_WAVE
`define SRC1_SEL_ACC          4'd8
`endif

`define SRC2_SEL_BITS 3
`define SRC2_SEL_ACC          3'd0
`define SRC2_SEL_REV_PHASE    3'd1
`define SRC2_SEL_PHASE_STEP   3'd2
`define SRC2_SEL_DETUNE       3'd3
`define SRC2_SEL_PHASE_MODIFIED 3'd4
`define SRC2_SEL_ZERO         3'd5
`ifdef USE_ORION_WAVE
`define SRC2_SEL_BITSHUFFLE_ACC 3'd6
`endif

`define DEST_SEL_BITS 2
`define DEST_SEL_PHASE   2'd0
`define DEST_SEL_ACC     2'd1
`define DEST_SEL_OUT_ACC 2'd2
`define DEST_SEL_NOTHING 2'd3


`define STATE_CMP_REV_PHASE 0
`define STATE_UPDATE_PHASE 1
`define STATE_DETUNE 2
`define STATE_TRI 3
`define STATE_COMBINED_SLOPE_CMP 4
`define STATE_COMBINED_SLOPE_ADD 5
`define STATE_AMP_CMP 6
`define STATE_OUT_ACC 7
`define STATE_LAST 7
`define STATE_BITS ($clog2(`STATE_LAST + 1))


`define PRED_SEL_BITS 2
`define PRED_SEL_OSC  0
`define PRED_SEL_LFSR 1
`define PRED_SEL_CMP  2
`define PRED_SEL_READ_VALID 3


`define PART_SEL_BITS 3
//`define PART_SEL_ACC_MSB 0
`define PART_SEL_SRC2_PRE_SIGN 0
`define PART_SEL_SWEEP   1
`define PART_SEL_NEQ     2
`define PART_SEL_NOSAT   3
`define PART_SEL_READ    4 // only used if USE_NEW_READ
`define PART_SEL_ZERO    5 // only used if USE_ORION_WAVE
`define PART_SEL_CARRY   6 // only used if USE_OCT_COUNTER_LATCHES


// synced with SRC1_SEL_*** and register address bits
`define SWEEP_INDEX_BITS 3
`define SWEEP_INDEX_PERIOD 0
`define SWEEP_INDEX_AMP 1
`define SWEEP_INDEX_SLOPE0 2 // must be even
`define SWEEP_INDEX_SLOPE1 3 // must be odd, should probably be SWEEP_INDEX_SLOPE0+1
`define SWEEP_INDEX_PWM_OFFSET 4
// Not used for sweeping, but for read-back
`define SWEEP_INDEX_PHASE 5
`define READ_INDEX_BITS 3


// For test interface
`define TST_ADDR_NOTHING -1
`define TST_ADDR_ACC 0
`define TST_ADDR_OUT_ACC 1
`define TST_ADDR_PRED 2
`define TST_ADDR_PART 3
`define TST_ADDR_LFSR_EXTRA_BITS 4
`define TST_ADDR_OCT_COUNTER 5
`define TST_ADDR_OUT_ACC_ALT_FRAC 6




//`define ALWAYS_FF_POSEDGE_CLK always_ff @(posedge clk)
`define ALWAYS_FF_POSEDGE_CLK always_ff @(posedge clk, negedge rst_n)


//`define PIPELINE

`ifdef PIPELINE // only applicable if PIPELINE enabled:
`define PIPELINE_SRC2
`define PIPELINE_SRC2_LSHIFT
`endif

`define PIPELINE_CURR_CHANNEL

`ifndef PURE_RTL
//`define NAMED_BUF_EN
`define USE_LATCHES
`define USE_EXTRA_DELAY_BUFFERS
`endif


// Define SCL_sky130_fd_sc_hd if not pure RTL and not IHP. Shouldn't be needed, but seems to be needed for my local runs at least.
`ifndef PURE_RTL
`ifndef SCL_sg13g2_stdcell
`define SCL_sky130_fd_sc_hd
`endif
`endif
