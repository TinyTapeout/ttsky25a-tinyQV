module intercal_alu(
	input  wire [3:0]  s,
	input  wire [31:0] a,
	input  wire [31:0] b,
	output wire [31:0] f
);

	wire [15:0] unand16H = {a[16], a[31:17]} & a[31:16];
	wire [15:0] unand16L = {a[0], a[15:1]} & a[15:0];
	wire [31:0] unand32 = {a[0], a[31:1]} & a;

	wire [15:0] unor16H = {a[16], a[31:17]} | a[31:16];
	wire [15:0] unor16L = {a[0], a[15:1]} | a[15:0];
	wire [31:0] unor32 = {a[0], a[31:1]} | a;

	wire [15:0] unxor16H = {a[16], a[31:17]} ^ a[31:16];
	wire [15:0] unxor16L = {a[0], a[15:1]} ^ a[15:0];
	wire [31:0] unxor32 = {a[0], a[31:1]} ^ a;

	wire [31:0] mingle16H = {
		a[31], b[31], a[30], b[30], a[29], b[29], a[28], b[28],
		a[27], b[27], a[26], b[26], a[25], b[25], a[24], b[24],
		a[23], b[23], a[22], b[22], a[21], b[21], a[20], b[20],
		a[19], b[19], a[18], b[18], a[17], b[17], a[16], b[16]
	};
	wire [31:0] mingle16L = {
		a[15], b[15], a[14], b[14], a[13], b[13], a[12], b[12],
		a[11], b[11], a[10], b[10], a[9], b[9], a[8], b[8],
		a[7], b[7], a[6], b[6], a[5], b[5], a[4], b[4],
		a[3], b[3], a[2], b[2], a[1], b[1], a[0], b[0]
	};

	wire        sh15 = (b[31] ?        a[31]  :  1'b0       );
	wire [1:0]  sh14 = (b[30] ? {sh15, a[30]} : {1'b0, sh15});
	wire [2:0]  sh13 = (b[29] ? {sh14, a[29]} : {1'b0, sh14});
	wire [3:0]  sh12 = (b[28] ? {sh13, a[28]} : {1'b0, sh13});
	wire [4:0]  sh11 = (b[27] ? {sh12, a[27]} : {1'b0, sh12});
	wire [5:0]  sh10 = (b[26] ? {sh11, a[26]} : {1'b0, sh11});
	wire [6:0]  sh9  = (b[25] ? {sh10, a[25]} : {1'b0, sh10});
	wire [7:0]  sh8  = (b[24] ? { sh9, a[24]} : {1'b0, sh9 });
	wire [8:0]  sh7  = (b[23] ? { sh8, a[23]} : {1'b0, sh8 });
	wire [9:0]  sh6  = (b[22] ? { sh7, a[22]} : {1'b0, sh7 });
	wire [10:0] sh5  = (b[21] ? { sh6, a[21]} : {1'b0, sh6 });
	wire [11:0] sh4  = (b[20] ? { sh5, a[20]} : {1'b0, sh5 });
	wire [12:0] sh3  = (b[19] ? { sh4, a[19]} : {1'b0, sh4 });
	wire [13:0] sh2  = (b[18] ? { sh3, a[18]} : {1'b0, sh3 });
	wire [14:0] sh1  = (b[17] ? { sh2, a[17]} : {1'b0, sh2 });
	wire [15:0] sh0  = (b[16] ? { sh1, a[16]} : {1'b0, sh1 });
	wire [15:0] select16H = sh0;

	wire        sl15 = (b[15] ?        a[15]  :  1'b0       );
	wire [1:0]  sl14 = (b[14] ? {sl15, a[14]} : {1'b0, sl15});
	wire [2:0]  sl13 = (b[13] ? {sl14, a[13]} : {1'b0, sl14});
	wire [3:0]  sl12 = (b[12] ? {sl13, a[12]} : {1'b0, sl13});
	wire [4:0]  sl11 = (b[11] ? {sl12, a[11]} : {1'b0, sl12});
	wire [5:0]  sl10 = (b[10] ? {sl11, a[10]} : {1'b0, sl11});
	wire [6:0]  sl9  = (b[9]  ? {sl10, a[9] } : {1'b0, sl10});
	wire [7:0]  sl8  = (b[8]  ? { sl9, a[8] } : {1'b0, sl9 });
	wire [8:0]  sl7  = (b[7]  ? { sl8, a[7] } : {1'b0, sl8 });
	wire [9:0]  sl6  = (b[6]  ? { sl7, a[6] } : {1'b0, sl7 });
	wire [10:0] sl5  = (b[5]  ? { sl6, a[5] } : {1'b0, sl6 });
	wire [11:0] sl4  = (b[4]  ? { sl5, a[4] } : {1'b0, sl5 });
	wire [12:0] sl3  = (b[3]  ? { sl4, a[3] } : {1'b0, sl4 });
	wire [13:0] sl2  = (b[2]  ? { sl3, a[2] } : {1'b0, sl3 });
	wire [14:0] sl1  = (b[1]  ? { sl2, a[1] } : {1'b0, sl2 });
	wire [15:0] sl0  = (b[0]  ? { sl1, a[0] } : {1'b0, sl1 });
	wire [15:0] select16L = sl0;

	wire [16:0] s15 = (b[15] ? {sh0, a[15]} : {1'b0, sh0});
	wire [17:0] s14 = (b[14] ? {s15, a[14]} : {1'b0, s15});
	wire [18:0] s13 = (b[13] ? {s14, a[13]} : {1'b0, s14});
	wire [19:0] s12 = (b[12] ? {s13, a[12]} : {1'b0, s13});
	wire [20:0] s11 = (b[11] ? {s12, a[11]} : {1'b0, s12});
	wire [21:0] s10 = (b[10] ? {s11, a[10]} : {1'b0, s11});
	wire [22:0] s9  = (b[9]  ? {s10, a[9] } : {1'b0, s10});
	wire [23:0] s8  = (b[8]  ? { s9, a[8] } : {1'b0, s9 });
	wire [24:0] s7  = (b[7]  ? { s8, a[7] } : {1'b0, s8 });
	wire [25:0] s6  = (b[6]  ? { s7, a[6] } : {1'b0, s7 });
	wire [26:0] s5  = (b[5]  ? { s6, a[5] } : {1'b0, s6 });
	wire [27:0] s4  = (b[4]  ? { s5, a[4] } : {1'b0, s5 });
	wire [28:0] s3  = (b[3]  ? { s4, a[3] } : {1'b0, s4 });
	wire [29:0] s2  = (b[2]  ? { s3, a[2] } : {1'b0, s3 });
	wire [30:0] s1  = (b[1]  ? { s2, a[1] } : {1'b0, s2 });
	wire [31:0] s0  = (b[0]  ? { s1, a[0] } : {1'b0, s1 });
	wire [31:0] select32 = s0;

	reg [31:0] result;
	assign f = result;

	always_comb begin
		case (s)
			0: result = a;
			1: result = b;
			2: result = {unand16H, unand16L};
			3: result = unand32;
			4: result = {unor16H, unor16L};
			5: result = unor32;
			6: result = {unxor16H, unxor16L};
			7: result = unxor32;
			8: result = mingle16L;
			9: result = mingle16H;
			10: result = {select16H, select16L};
			11: result = select32;
			default: result = 0;
		endcase
	end

endmodule
