/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "pwl_synth.vh"

`ifdef USE_LATCHES

module pwls_shared_data #(parameter BITS=16) (
		input wire clk, rst_n,
		input wire [BITS-1:0] in,
		output wire [BITS-1:0] out
	);
	genvar i;

	wire [BITS-1:0] data_in = !rst_n ? '0 : in;
	wire [BITS-1:0] latch_out;
	generate
		for (i = 0; i < BITS; i++) begin
`ifdef SCL_sky130_fd_sc_hd
			sky130_fd_sc_hd__dlxtn_1 n_latch(.GATE_N(clk), .D(data_in[i]), .Q(latch_out[i]));
//	`ifdef USE_EXTRA_DELAY_BUFFERS
			wire d1;
			(* keep *) (* dont_touch *) sky130_fd_sc_hd__dlygate4sd3_1 hold_buf1(.A(latch_out[i]), .X(d1));
			(* keep *) (* dont_touch *) sky130_fd_sc_hd__dlygate4sd3_1 hold_buf2(.A(d1), .X(out[i]));
/*
	`else
			assign out[i] = latch_out[i];
	`endif
*/
`endif
`ifdef SCL_sg13g2_stdcell
			sg13g2_dllrq_1 n_latch(.GATE_N(clk), .D(data_in[i]), .RESET_B(1), .Q(latch_out[i]));
			assign out[i] = latch_out[i];
`endif
		end
	endgenerate
endmodule : pwls_shared_data

module pwls_register #(parameter BITS=16) (
		input wire clk, rst_n,
		input wire we,
		input wire [BITS-1:0] wdata,
		output wire [BITS-1:0] rdata
	);
	genvar i;

	wire gclk;
`ifdef SCL_sky130_fd_sc_hd
	sky130_fd_sc_hd__dlclkp_1 clock_gate(.CLK(clk), .GATE(we || !rst_n), .GCLK(gclk));
`endif
`ifdef SCL_sg13g2_stdcell
	sg13g2_lgcp_1 clock_gate(.CLK(clk), .GATE(we || !rst_n), .GCLK(gclk));
`endif

	generate
		for (i = 0; i < BITS; i++) begin
`ifdef SCL_sky130_fd_sc_hd
			sky130_fd_sc_hd__dlxtp_1 p_latch(.GATE(gclk), .D(wdata[i]), .Q(rdata[i]));
`endif
`ifdef SCL_sg13g2_stdcell
			sg13g2_dlhq_1 p_latch(.GATE(gclk), .D(wdata[i]), .Q(rdata[i]));
`endif
		end
	endgenerate
endmodule

`else // not USE_LATCHES

module pwls_shared_data #(parameter BITS=16) (
		input wire clk, rst_n,
		input wire [BITS-1:0] in,
		output wire [BITS-1:0] out
	);
	assign out = in;
endmodule : pwls_shared_data

module pwls_register #(parameter BITS=16) (
		input wire clk, rst_n,
		input wire we,
		input wire [BITS-1:0] wdata,
		output wire [BITS-1:0] rdata
	);
	reg [BITS-1:0] data;
	always_ff @(posedge clk) begin
		if (!rst_n) data <= 0;
		else if (we) data <= wdata;
	end
	assign rdata = data;
endmodule

`endif
