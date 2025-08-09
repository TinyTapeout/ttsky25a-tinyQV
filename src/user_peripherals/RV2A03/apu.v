// Rewritten 6/4/2020 by Kitrinx
// This code is GPLv3.
`define COCOTB_TESTING

module LenCounterUnit (
    input  logic       clk,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic       len_clk,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic [7:0] load_value,
    input  logic       halt_in,
    input  logic       addr,
    input  logic       is_triangle,
    input  logic       write,
    input  logic       enabled,
    output logic       lc_on
);

    logic lc_on_1;
    logic clear_next;
    logic [7:0] len_counter_int;
    logic halt;
    logic [7:0] len_counter_next;
    always_ff @(posedge clk) begin : lenunit
        if (aclk1_d)
            if (~enabled)
                lc_on <= 0;

        if (aclk1) begin
            lc_on_1 <= lc_on;
            len_counter_next <= halt || ~|len_counter_int ? len_counter_int : len_counter_int - 1'd1;
            clear_next <= ~halt && ~|len_counter_int;
        end

        if (write) begin
            if (~addr) begin
                halt <= halt_in;
            end else begin
                lc_on <= 1;
                len_counter_int <= load_value;
            end
        end

        // This deliberately can overwrite being loaded from writes
        if (len_clk && lc_on_1) begin
            len_counter_int <= halt ? len_counter_int : len_counter_next;
            if (clear_next)
                lc_on <= 0;
        end

        if (reset) begin
            if (~is_triangle || cold_reset) begin
                halt <= 0;
            end
            lc_on <= 0;
            len_counter_int <= 0;
            len_counter_next <= 0;
        end
    end

endmodule

module EnvelopeUnit (
    input  logic       clk,
    input  logic       reset,
    input  logic       env_clk,
    input  logic [5:0] din,
    input  logic       addr,
    input  logic       write,
    output logic [3:0] envelope
);

    logic [3:0] env_count, env_vol;
    logic env_disabled;

    assign envelope = env_disabled ? env_vol : env_count;

    always_ff @(posedge clk) begin : envunit
        logic [3:0] env_div;
        logic env_reload;
        logic env_loop;

        if (env_clk) begin
            if (~env_reload) begin
                env_div <= env_div - 1'd1;
                if (~|env_div) begin
                    env_div <= env_vol;
                    if (|env_count || env_loop)
                        env_count <= env_count - 1'd1;
                end
            end else begin
                env_div <= env_vol;
                env_count <= 4'hF;
                env_reload <= 1'b0;
            end
        end

        if (write) begin
            if (~addr) {env_loop, env_disabled, env_vol} <= din;
            if (addr) env_reload <= 1;
        end

        if (reset) begin
            env_loop <= 0;
            env_div <= 0;
            env_vol <= 0;
            env_count <= 0;
            env_reload <= 0;
        end
    end

endmodule

module SquareChan (
    input  logic       MMC5,
    input  logic       clk,
    input  logic       ce,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic       allow_us,
    input  logic [1:0] Addr,
    input  logic [7:0] DIN,
    input  logic       write,
    input  logic [7:0] lc_load,
    input  logic       LenCtr_Clock,
    input  logic       Env_Clock,
    input  logic       Enabled,
    output logic [3:0] Sample,
    output logic       IsNonZero
);

    // Register 1
    logic [1:0] Duty;

    // Registers and signals for period and sequencing
    logic [10:0] Period;
    logic [11:0] TimerCtr;
    logic [2:0] SeqPos;

    logic ValidFreq;
    logic subunit_write;
    logic [3:0] Envelope;
    logic lc;
    logic DutyEnabledUsed;
    logic DutyEnabled;

    assign DutyEnabledUsed = MMC5 ^ DutyEnabled;
    assign subunit_write = (Addr == 0 || Addr == 3) & write;
    assign IsNonZero = lc;

    // Simplified ValidFreq check without sweep logic
    assign ValidFreq = (MMC5 && allow_us) || (|Period[10:3]);
    assign Sample = (~lc | ~ValidFreq | ~DutyEnabledUsed) ? 4'd0 : Envelope;

    LenCounterUnit LenSq (
        .clk            (clk),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_d),
        .len_clk        (MMC5 ? Env_Clock : LenCtr_Clock),
        .load_value     (lc_load),
        .halt_in        (DIN[5]),
        .addr           (Addr[0]),
        .is_triangle    (1'b0),
        .write          (subunit_write),
        .enabled        (Enabled),
        .lc_on          (lc)
    );

    EnvelopeUnit EnvSq (
        .clk            (clk),
        .reset          (reset),
        .env_clk        (Env_Clock),
        .din            (DIN[5:0]),
        .addr           (Addr[0]),
        .write          (subunit_write),
        .envelope       (Envelope)
    );

    always_comb begin
        case (Duty)
            0: DutyEnabled = (SeqPos == 7);
            1: DutyEnabled = (SeqPos >= 6);
            2: DutyEnabled = (SeqPos >= 4);
            3: DutyEnabled = (SeqPos < 6);
        endcase
    end

    // Consolidated main logic block with sweep removed
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            Duty <= 0;
            Period <= 0;
            TimerCtr <= 0;
            SeqPos <= 0;
        end else begin
            if (write) begin
                case (Addr)
                    0: Duty <= DIN[7:6];
                    1: begin
                        // This address is now ignored, since the sweep unit is removed.
                        // You could add a comment here to show this.
                    end
                    2: Period[7:0] <= DIN;
                    3: begin
                        Period[10:8] <= DIN[2:0];
                        SeqPos <= 0;
                    end
                endcase
            end

            if (aclk1_d) begin
                if (TimerCtr == 0) begin
                    TimerCtr <= {1'b0, Period};
                    SeqPos <= SeqPos - 1'd1;
                end else begin
                    TimerCtr <= TimerCtr - 1'd1;
                end
            end
        end
    end

endmodule

module TriangleChan (
    input  logic       clk,
    input  logic       phi1,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic       allow_us,
    input  logic [1:0] Addr,
    input  logic [7:0] DIN,
    input  logic       write,
    input  logic [7:0] lc_load,
    input  logic       LenCtr_Clock,
    input  logic       LinCtr_Clock,
    input  logic       Enabled,
    output logic [3:0] Sample,
    output logic       IsNonZero
);

    logic [10:0] Period, applied_period, TimerCtr;
    initial Period = 'h3E;
    logic [4:0] SeqPos;
    logic [6:0] LinCtrPeriod, LinCtrPeriod_1, LinCtr;
    logic LinCtrl, line_reload;
    logic LinCtrZero;
    logic lc;

    logic subunit_write;
    logic [3:0] sample_latch;
    // initial sample_latch = 'b1010;

    assign LinCtrZero = ~|LinCtr;
    assign IsNonZero = lc;
    assign subunit_write = (Addr == 0 || Addr == 3) & write;

    assign Sample = (applied_period > 1 || allow_us) ? (SeqPos[3:0] ^ {4{~SeqPos[4]}}) : sample_latch;
    // assign Sample = Period;

    LenCounterUnit LenTri (
        .clk            (clk),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_d),
        .len_clk        (LenCtr_Clock),
        .load_value     (lc_load),
        .halt_in        (DIN[7]),
        .addr           (Addr[0]),
        .is_triangle    (1'b1),
        .write          (subunit_write),
        .enabled        (Enabled),
        .lc_on          (lc)
    );

    always_ff @(posedge clk) begin
        if (phi1) begin
            if (TimerCtr == 0) begin
                TimerCtr <= Period;
                applied_period <= Period;
                if (IsNonZero & ~LinCtrZero)
                    SeqPos <= SeqPos + 1'd1;
            end else begin
                TimerCtr <= TimerCtr - 1'd1;
            end
        end

        if (aclk1) begin
            LinCtrPeriod_1 <= LinCtrPeriod;
        end

        if (LinCtr_Clock) begin
            if (line_reload)
                LinCtr <= LinCtrPeriod_1;
            else if (!LinCtrZero)
                LinCtr <= LinCtr - 1'd1;

            if (!LinCtrl)
                line_reload <= 0;
        end

        if (write) begin
            case (Addr)
                0: begin
                    LinCtrl <= DIN[7];
                    LinCtrPeriod <= DIN[6:0];
                end
                2: begin
                    Period[7:0] <= DIN;
                end
                3: begin
                    Period[10:8] <= DIN[2:0];
                    line_reload <= 1;
                end
            endcase
        end

        if (reset) begin
            sample_latch <= 4'hF;
            Period <= 0;
            TimerCtr <= 0;
            SeqPos <= 0;
            LinCtrPeriod <= 0;
            LinCtr <= 0;
            LinCtrl <= 0;
            line_reload <= 0;
        end

        if (applied_period > 1) 
            sample_latch <= Sample;
    end

endmodule

module NoiseChan (
    input  logic       clk,
    input  logic       ce,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic [1:0] Addr,
    input  logic [7:0] DIN,
    input  logic       write,
    input  logic [7:0] lc_load,
    input  logic       LenCtr_Clock,
    input  logic       Env_Clock,
    input  logic       Enabled,
    output logic [3:0] Sample,
    output logic       IsNonZero
);
    logic ShortMode;
    logic [14:0] Shift;
    logic [3:0] Period;
    logic [3:0] Envelope;
    logic subunit_write;
    logic lc;

    assign IsNonZero = lc;
    assign subunit_write = (Addr == 0 || Addr == 3) & write;

    // Produce the output signal
    assign Sample = (~lc || Shift[14]) ? 4'd0 : Envelope;

    LenCounterUnit LenNoi (
        .clk            (clk),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_d),
        .len_clk        (LenCtr_Clock),
        .load_value     (lc_load),
        .halt_in        (DIN[5]),
        .addr           (Addr[0]),
        .is_triangle    (1'b0),
        .write          (subunit_write),
        .enabled        (Enabled),
        .lc_on          (lc)
    );

    EnvelopeUnit EnvNoi (
        .clk            (clk),
        .reset          (reset),
        .env_clk        (Env_Clock),
        .din            (DIN[5:0]),
        .addr           (Addr[0]),
        .write          (subunit_write),
        .envelope       (Envelope)
    );

    // Values read directly from the netlist
    reg [10:0] noise_ntsc_lut[0:15];
    initial begin
        noise_ntsc_lut[0] = 11'h200;
        noise_ntsc_lut[1] = 11'h280;
        noise_ntsc_lut[2] = 11'h2A8;
        noise_ntsc_lut[3] = 11'h6EA;
        noise_ntsc_lut[4] = 11'h4E4;
        noise_ntsc_lut[5] = 11'h674;
        noise_ntsc_lut[6] = 11'h630;
        noise_ntsc_lut[7] = 11'h730;
        noise_ntsc_lut[8] = 11'h4AC;
        noise_ntsc_lut[9] = 11'h304;
        noise_ntsc_lut[10] = 11'h722;
        noise_ntsc_lut[11] = 11'h230;
        noise_ntsc_lut[12] = 11'h213;
        noise_ntsc_lut[13] = 11'h782;
        noise_ntsc_lut[14] = 11'h006;
        noise_ntsc_lut[15] = 11'h014;
    end

    logic [10:0] noise_timer;
    logic noise_clock;
    always_ff @(posedge clk) begin
        if (aclk1_d) begin
            noise_timer <= {noise_timer[9:0], (noise_timer[10] ^ noise_timer[8]) | ~|noise_timer};

            if (noise_clock) begin
                noise_clock <= 0;
                noise_timer <= noise_ntsc_lut[Period];
                Shift <= {Shift[13:0], ((Shift[14] ^ (ShortMode ? Shift[8] : Shift[13])) | ~|Shift)};
            end
        end

        if (aclk1) begin
            if (noise_timer == 'h400)
                noise_clock <= 1;
        end

        if (write && Addr == 2) begin
            ShortMode <= DIN[7];
            Period <= DIN[3:0];
        end

        if (reset) begin
            if (|noise_timer) noise_timer <= noise_ntsc_lut[0];
            ShortMode <= 0;
            Shift <= 0;
            Period <= 0;
        end

        if (cold_reset)
            noise_timer <= 0;
    end
endmodule
module FrameCtr (
    input  logic clk,
    input  logic aclk1,
    input  logic aclk2,
    input  logic reset,
    input  logic cold_reset,
    input  logic read,
    input  logic write_ce,
    input  logic [7:0] din,
    input  logic [1:0] addr,
    input  logic MMC5,
    output logic irq,
    output logic irq_flag,
    output logic frame_half,
    output logic frame_quarter
);
    // NTSC -- Confirmed
    // Binary Frame Value         Decimal  Cycle
    // 15'b001_0000_0110_0001,    04193    03713 -- Quarter
    // 15'b011_0110_0000_0011,    13827    07441 -- Half
    // 15'b010_1100_1101_0011,    11475    11170 -- 3 quarter
    // 15'b000_1010_0001_1111,    02591    14899 -- Reset w/o Seq/Interrupt
    // 15'b111_0001_1000_0101     29061    18625 -- Reset w/ seq

    logic frame_reset;
    logic frame_interrupt_buffer;
    logic frame_int_disabled;
    logic FrameInterrupt;
    logic set_irq;
    logic FrameSeqMode_2;
    logic frame_reset_2;
    logic w4017_1, w4017_2;
    logic [14:0] frame;
    logic [14:0] frame_next;

    // Registered outputs for stable enables
    logic frame_half_reg, frame_quarter_reg;
    assign frame_half = frame_half_reg;
    assign frame_quarter = frame_quarter_reg;

    // Register 4017
    logic DisableFrameInterrupt;
    logic FrameSeqMode;

    assign frame_int_disabled = DisableFrameInterrupt;
    assign irq = FrameInterrupt && ~DisableFrameInterrupt;
    assign irq_flag = frame_interrupt_buffer;

    logic seq_mode;
    assign seq_mode = aclk1 ? FrameSeqMode : FrameSeqMode_2;

    logic frm_a, frm_b, frm_c, frm_d, frm_e;
    assign frm_a = 15'b001_0000_0110_0001 == frame;
    assign frm_b = 15'b011_0110_0000_0011 == frame;
    assign frm_c = 15'b010_1100_1101_0011 == frame;
    assign frm_d = 15'b000_1010_0001_1111 == frame && ~seq_mode;
    assign frm_e = 15'b111_0001_1000_0101 == frame;

    assign set_irq = frm_d & ~FrameSeqMode;
    assign frame_reset = frm_d | frm_e | w4017_2;

    always_comb begin
        frame_next = frame_reset_2 ? 15'h7FFF : {frame[13:0], ((frame[14] ^ frame[13]) | ~|frame)};
    end

    always_ff @(posedge clk or posedge reset) begin : apu_block
        if (reset) begin
            // All registers must have a fixed reset value here.
            FrameInterrupt <= 0;
            frame_interrupt_buffer <= 0;
            w4017_1 <= 0;
            w4017_2 <= 0;
            DisableFrameInterrupt <= 0;
            FrameSeqMode <= 0; // Unconditional reset to 0
            frame <= 15'h7FFF;
            frame_half_reg <= 0;
            frame_quarter_reg <= 0;
            frame_reset_2 <= 0;
        end else begin
            if (aclk1) begin
                frame <= frame_next;
                w4017_2 <= w4017_1;
                w4017_1 <= 0;
                
                // This logic is now handled here, not in the reset block.
                if (cold_reset) begin
                    FrameSeqMode_2 <= 0;
                end else begin
                    FrameSeqMode_2 <= FrameSeqMode;
                end
                
                frame_half_reg <= (frm_b | frm_d | frm_e | (w4017_2 & seq_mode));
                frame_quarter_reg <= (frm_a | frm_b | frm_c | frm_d | frm_e | (w4017_2 & seq_mode));
                frame_reset_2 <= aclk2 & frame_reset;
            end

            // Continuously update the Frame IRQ state and read buffer
            if (set_irq & ~frame_int_disabled) begin
                FrameInterrupt <= 1;
                frame_interrupt_buffer <= 1;
            end else if (addr == 2'h1 && read)
                FrameInterrupt <= 0;
            else
                frame_interrupt_buffer <= FrameInterrupt;

            if (frame_int_disabled)
                FrameInterrupt <= 0;

            if (write_ce && addr == 3 && ~MMC5) begin
                FrameSeqMode <= din[7];
                DisableFrameInterrupt <= din[6];
                w4017_1 <= 1;
            end
        end
    end
endmodule
module APU (
    input  logic         MMC5,
    input  logic         clk,
    input  logic         PHI2,      // Now used as a clock enable.
    input  logic         ce,
    input  logic         reset,
    input  logic         cold_reset,
    input  logic         allow_us,       // Set to 1 to allow ultrasonic frequencies
    input  logic  [4:0]  ADDR,           // APU Address Line
    input  logic  [7:0]  DIN,            // Data to APU
    input  logic         RW,
    input  logic         CS,
    input  logic         odd_or_even,
    output logic  [7:0]  DOUT,           // Data from APU
    output wire   [15:0] Sample,
    output logic         IRQ,            // IRQ asserted high == asserted
    output logic         o_ce
    );

    reg [7:0] len_counter_lut[0:31];

    initial begin
        len_counter_lut[0] = 8'h09;
        len_counter_lut[1] = 8'hFD;
        len_counter_lut[2] = 8'h13;
        len_counter_lut[3] = 8'h01;
        len_counter_lut[4] = 8'h27;
        len_counter_lut[5] = 8'h03;
        len_counter_lut[6] = 8'h4F;
        len_counter_lut[7] = 8'h05;
        len_counter_lut[8] = 8'h9F;
        len_counter_lut[9] = 8'h07;
        len_counter_lut[10] = 8'h3B;
        len_counter_lut[11] = 8'h09;
        len_counter_lut[12] = 8'h0D;
        len_counter_lut[13] = 8'h0B;
        len_counter_lut[14] = 8'h19;
        len_counter_lut[15] = 8'h0D;
        len_counter_lut[16] = 8'h0B;
        len_counter_lut[17] = 8'h0F;
        len_counter_lut[18] = 8'h17;
        len_counter_lut[19] = 8'h11;
        len_counter_lut[20] = 8'h2F;
        len_counter_lut[21] = 8'h13;
        len_counter_lut[22] = 8'h5F;
        len_counter_lut[23] = 8'h15;
        len_counter_lut[24] = 8'hBF;
        len_counter_lut[25] = 8'h17;
        len_counter_lut[26] = 8'h47;
        len_counter_lut[27] = 8'h19;
        len_counter_lut[28] = 8'h0F;
        len_counter_lut[29] = 8'h1B;
        len_counter_lut[30] = 8'h1F;
        len_counter_lut[31] = 8'h1D;
    end

    logic [7:0] lc_load;
    assign lc_load = len_counter_lut[DIN[7:3]];

    // All clocking is now handled via a single clock enable signal.
    // The PHI2 signal from the top-level is now a clock enable.
    logic read, write, write_ce;
    logic apu_ce_sync; // Synchronize the PHI2 enable signal

    always @(posedge clk) begin
        apu_ce_sync <= PHI2;
    end

    assign read = RW & CS;
    assign write = ~RW & CS;
    assign write_ce = write & apu_ce_sync;

    // Derived clock signals are replaced with a clock enable.
    logic aclk1, aclk2, aclk1_delayed, phi1;
    assign aclk1 = odd_or_even;
    assign aclk2 = ~odd_or_even & apu_ce_sync;
    assign aclk1_delayed = ~odd_or_even & ce;
    assign phi1 = ce;

    logic [3:0] Enabled;
    logic [3:0] Sq1Sample,Sq2Sample,TriSample,NoiSample;
    logic DmcIrq = 1'b0;

    logic irq_flag;
    logic frame_irq;

    // Generate internal memory write signals
    logic ApuMW0, ApuMW1, ApuMW2, ApuMW3, ApuMW5;
    assign ApuMW0 = ADDR[4:2]==0; // SQ1
    assign ApuMW1 = ADDR[4:2]==1; // SQ2
    assign ApuMW2 = ADDR[4:2]==2; // TRI
    assign ApuMW3 = ADDR[4:2]==3; // NOI
    assign ApuMW5 = ADDR[4:2]==5; // Control registers

    logic Sq1NonZero, Sq2NonZero, TriNonZero, NoiNonZero;
    logic ClkE, ClkL;
    
    // The internal clock enables are now derived from the frame counter.
    logic frame_quarter, frame_half;
    assign ClkE = frame_quarter & aclk1_delayed;
    assign ClkL = frame_half & aclk1_delayed;

    // Use a single synchronous assignment for enabled_buffer.
    logic [3:0] enabled_buffer;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            enabled_buffer <= 0;    
        end else if (apu_ce_sync && ApuMW5 && write && ADDR[1:0] == 1) begin
            enabled_buffer <= DIN[3:0]; // Register $4015
        end
    end
    assign Enabled = enabled_buffer;


    // Generate bus output
    assign DOUT = {DmcIrq, irq_flag, 1'b0, 1'b0, NoiNonZero, TriNonZero, Sq2NonZero, Sq1NonZero};
    assign IRQ = frame_irq || DmcIrq;

    // Generate each channel
    SquareChan Squ1 (
        .MMC5           (MMC5),
        .clk            (clk),
        .ce             (apu_ce_sync), // Use the new clock enable
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_delayed),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .allow_us       (allow_us),
        .Addr           (ADDR[1:0]),
        .DIN            (DIN),
        .write          (ApuMW0 && write),
        .lc_load        (lc_load),
        .LenCtr_Clock   (ClkL),
        .Env_Clock      (ClkE),
        .Enabled        (Enabled[0]),
        .Sample         (Sq1Sample),
        .IsNonZero      (Sq1NonZero)
    );

    SquareChan Squ2 (
        .MMC5           (MMC5),
        .clk            (clk),
        .ce             (apu_ce_sync), // Use the new clock enable
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_delayed),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .allow_us       (allow_us),
        .Addr           (ADDR[1:0]),
        .DIN            (DIN),
        .write          (ApuMW1 && write),
        .lc_load        (lc_load),
        .LenCtr_Clock   (ClkL),
        .Env_Clock      (ClkE),
        .Enabled        (Enabled[1]),
        .Sample         (Sq2Sample),
        .IsNonZero      (Sq2NonZero)
    );

    TriangleChan Tri (
        .clk            (clk),
        .phi1           (phi1),
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_delayed),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .allow_us       (allow_us),
        .Addr           (ADDR[1:0]),
        .DIN            (DIN),
        .write          ((ApuMW2)&&(write)),
        .lc_load        (lc_load),
        .LenCtr_Clock   (ClkE),
        .LinCtr_Clock   (ClkL),
        .Enabled        (Enabled[2]),
        .Sample         (TriSample),
        .IsNonZero      (TriNonZero)
    );

    NoiseChan Noi (
        .clk            (clk),
        .ce             (apu_ce_sync), // Use the new clock enable
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_delayed),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .Addr           (ADDR[1:0]),
        .DIN            (DIN),
        .write          (ApuMW3 && write),
        .lc_load        (lc_load),
        .LenCtr_Clock   (ClkL),
        .Env_Clock      (ClkE),
        .Enabled        (Enabled[3]),
        .Sample         (NoiSample),
        .IsNonZero      (NoiNonZero)
    );

    APUMixer mixer (
        .square1        (Sq1Sample),
        .square2        (Sq2Sample),
        .noise          (NoiSample),
        .triangle       (TriSample),
        .sample         (Sample)
    );

    FrameCtr frame_counter (
        .clk            (clk),
        .aclk1          (aclk1),
        .aclk2          (aclk2),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .read           (ApuMW5 & read),
        .write_ce       (ApuMW5 & write_ce),
        .addr           (ADDR[1:0]),
        .din            (DIN),
        .MMC5           (MMC5),
        .irq            (frame_irq),
        .irq_flag       (irq_flag),
        .frame_half     (frame_half),
        .frame_quarter  (frame_quarter)
    );

    // This is the new output clock enable signal.
    assign o_ce = apu_ce_sync;
endmodule


module APUMixer (
    input  logic  [3:0] square1,
    input  logic  [3:0] square2,
    input  logic  [3:0] triangle,
    input  logic  [3:0] noise,
    output logic [15:0] sample
);

// Note: The original non-linear pulse_lut has been removed.
// Square waves are now mixed with a simple linear sum.
// An input of '0' results in an 'OFF' state for the channel.
// The triangle wave logic has been simplified to use linear scaling instead of lookup tables.

reg [5:0] noise_lut[0:15];
initial begin
    noise_lut[0] = 6'h00;
    noise_lut[1] = 6'h03;
    noise_lut[2] = 6'h05;
    noise_lut[3] = 6'h08;
    noise_lut[4] = 6'h0B;
    noise_lut[5] = 6'h0D;
    noise_lut[6] = 6'h10;
    noise_lut[7] = 6'h13;
    noise_lut[8] = 6'h15;
    noise_lut[9] = 6'h18;
    noise_lut[10] = 6'h1B;
    noise_lut[11] = 6'h1D;
    noise_lut[12] = 6'h20;
    noise_lut[13] = 6'h23;
    noise_lut[14] = 6'h25;
    noise_lut[15] = 6'h28;
end

// Sum
wire [17:0] mixed_sum = {14'b0, square1} + {14'b0, square2} + {12'b0, triangle, 2'b0} + {12'b0, noise_lut[noise]};

// Divide the sum by a constant to scale the output down and prevent overflow.
assign sample = mixed_sum[17:2];


endmodule
