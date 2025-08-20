/*
 * Copyright (c) 2025 Rebecca G. Bettencourt
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

(* keep_hierarchy *)
module tqvp_rebeccargb_universal_decoder (
    input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input         rst_n,        // Reset_n - low to reset.
    input  [7:0]  ui_in,        // The input PMOD.  Note that ui_in[7] is normally used for UART RX.
    output [7:0]  uo_out,       // The output PMOD.  Note that uo_out[0] is normally used for UART TX.
    input  [3:0]  address,      // Address within this peripheral's address space
    input         data_write,   // Data write request from the TinyQV core.
    input  [7:0]  data_in,      // Data in to the peripheral, valid when data_write is high.
    output [7:0]  data_out      // Data out from the peripheral, set this in accordance with the supplied address
);

    reg [7:0] data;
    reg [3:0] datax;
    reg rbi; // ripple blanking input
    reg lt;  // lamp test
    reg bi;  // blanking input
    reg al;  // active low
    reg x9;  // extra segment on 9
    reg x7;  // extra segment on 7
    reg x6;  // extra segment on 6
    reg lc;  // lower case
    reg fs;  // font select
    reg v2;  // variation selector 2
    reg v1;  // variation selector 1
    reg v0;  // variation selector 0
    reg le;  // latch enable (0 = get input from data, 1 = get input from ui_in)
    reg oe;  // output enable (0 = send output to uo_out, 1 = do not use uo_out)
    reg [2:0] mode;

    wire [7:0] iv = (le ? ui_in : data);             // input value
    wire [3:0] bcd = (mode[0] ? iv[7:4] : iv[3:0]);  // bcd input value

    wire b_a, b_b, b_c, b_d, b_e, b_f, b_g, b_rbo;
    universal_bcd_decoder ubcd(
        .A(bcd[0]), .B(bcd[1]), .C(bcd[2]), .D(bcd[3]), .V0(v0), .V1(v1), .V2(v2),
        .X6(x6), .X7(x7), .X9(x9), .RBI(rbi), .LT(lt), .BI(bi), .AL(al),
        .Qa(b_a), .Qb(b_b), .Qc(b_c), .Qd(b_d), .Qe(b_e), .Qf(b_f), .Qg(b_g), .RBO(b_rbo)
    );

    wire a_a, a_b, a_c, a_d, a_e, a_f, a_g, a_ltr;
    ascii_decoder ad(
        .D0(iv[0]), .D1(iv[1]), .D2(iv[2]), .D3(iv[3]), .D4(iv[4]), .D5(iv[5]), .D6(iv[6]),
        .X6(x6), .X7(x7), .X9(x9), .LC(lc), .FS(fs), .ABI(bi), .AL(al),
        .Qa(a_a), .Qb(a_b), .Qc(a_c), .Qd(a_d), .Qe(a_e), .Qf(a_f), .Qg(a_g), .LTR(a_ltr)
    );

    wire c_u1, c_v1, c_w1, c_x1, c_y1, c_u2, c_v2, c_w2, c_x2, c_y2;
    dual_cistercian_decoder dcd(
        .A1(iv[0]), .B1(iv[1]), .C1(iv[2]), .D1(iv[3]),
        .A2(iv[4]), .B2(iv[5]), .C2(iv[6]), .D2(iv[7]),
        .LT1(lt), .LT2(lt), .BI(bi), .AL(al),
        .U1(c_u1), .V1(c_v1), .W1(c_w1), .X1(c_x1), .Y1(c_y1),
        .U2(c_u2), .V2(c_v2), .W2(c_w2), .X2(c_x2), .Y2(c_y2)
    );

    wire k_a, k_b, k_c, k_d, k_e, k_f, k_g, k_h, k_rbo, k_v;
    kaktovik_decoder kd(
        .A(iv[0]), .B(iv[1]), .C(iv[2]), .D(iv[3]), .E(iv[4]),
        .RBI(rbi), .VBI(v2|v1|v0), .LT(lt), .BI(bi), .AL(al),
        .Qa(k_a), .Qb(k_b), .Qc(k_c), .Qd(k_d), .Qe(k_e),
        .Qf(k_f), .Qg(k_g), .Qh(k_h), .RBO(k_rbo), .V(k_v)
    );

    wire [7:0] pt = ((iv | {8{~lt}}) & {8{bi}}) ^ {8{~al}};     // pass-through
    wire [3:0] dp = ((datax | {4{~lt}}) & {4{bi}}) ^ {4{~al}};  // decimal point

    wire [7:0] ov = (
        // output value
        mode[2] ? (
            mode[1] ? (
                // Kaktovik
                mode[0] ? pt : {k_h, k_g, k_f, k_e, k_d, k_c, k_b, k_a}
            ) : (
                // Cistercian
                mode[0] ? {dp[2:0], c_y2, c_x2, c_w2, c_v2, c_u2}
                        : {dp[2:0], c_y1, c_x1, c_w1, c_v1, c_u1}
            )
        ) : (
            mode[1] ? (
                // ASCII
                mode[0] ? pt : {dp[0], a_g, a_f, a_e, a_d, a_c, a_b, a_a}
            ) : (
                // BCD
                {(mode[0] ? dp[1] : dp[0]), b_g, b_f, b_e, b_d, b_c, b_b, b_a}
            )
        )
    );

    wire [3:0] status = (
        // status register
        mode[2] ? (
            mode[1] ? (
                // Kaktovik
                {k_rbo, k_v, 2'b00}
            ) : (
                // Cistercian
                {(((bcd != 0) | rbi | ~lt) & bi), (bcd >= 4'd10), 2'b00}
            )
        ) : (
            mode[1] ? (
                // ASCII
                {(((iv[6:0] != 0) | rbi | ~lt) & bi), iv[7], a_ltr, 1'b0}
            ) : (
                // BCD
                {b_rbo, (bcd >= 4'd10), 2'b00}
            )
        )
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            data <= 0;
            datax <= 0;
            rbi <= 1; // ripple blanking input
            lt <= 1;  // lamp test
            bi <= 1;  // blanking input
            al <= 1;  // active low
            x9 <= 1;  // extra segment on 9
            x7 <= 1;  // extra segment on 7
            x6 <= 1;  // extra segment on 6
            lc <= 1;  // lower case
            fs <= 0;  // font select
            v2 <= 0;  // variation select 2
            v1 <= 0;  // variation select 1
            v0 <= 0;  // variation select 0
            le <= 0;  // latch enable (0 = get input from data, 1 = get input from ui_in)
            oe <= 0;  // output enable (0 = send output to uo_out, 1 = do not use uo_out)
            mode <= 0;
        end else if (data_write) begin
            if (address == 4'h0) begin
                data <= data_in;
            end else if (address == 4'h1) begin
                datax <= data_in[3:0];
                rbi <= data_in[7];
                lt <= data_in[6];
                bi <= data_in[5];
                al <= data_in[4];
            end else if (address == 4'h2) begin
                x9 <= data_in[7];
                x7 <= data_in[6];
                x6 <= data_in[5];
                lc <= data_in[4];
                fs <= data_in[3];
                v2 <= data_in[2];
                v1 <= data_in[1];
                v0 <= data_in[0];
            end else if (address == 4'h3) begin
                le <= data_in[7];
                oe <= data_in[6];
                mode <= data_in[2:0];
            end
        end
    end

    // All output pins must be assigned. If not used, assign to 0.
    assign uo_out = (oe ? 8'h00 : ov);

    assign data_out = (
        (address == 4'h0) ? data :
        (address == 4'h1) ? {rbi, lt, bi, al, datax} :
        (address == 4'h2) ? {x9, x7, x6, lc, fs, v2, v1, v0} :
        (address == 4'h3) ? {le, oe, 3'b000, mode} :
        (address == 4'h4) ? ov :
        (address == 4'h5) ? {status, dp} :
        (address == 4'h6) ? iv :
        (address == 4'h7) ? ui_in :
        8'hFF
    );

endmodule
