/*
 * Keropiyo Tiny AM Radio - compact one-stage filter prototype
 *
 * Assumptions:
 *   - Tiny Tapeout clock: 50 MHz
 *   - ui_in[0]: output from an external high-speed comparator
 *   - uo_out[0]: feedback bit to the comparator RC network
 *   - ui_in[1], ui_in[2]: rotary encoder A/B
 *   - ui_in[3]: mute (high = mute)
 *   - ui_in[4]: return tuning to 810 kHz (high = home)
 *   - uo_out[1]: PWM audio output
 *
 * The digital path is:
 *   1-bit comparator loop -> 24-bit NCO/mixer
 *   -> one-stage I/Q accumulate-and-dump decimator
 *   -> approximate AM envelope -> DC removal -> PWM
 *
 * This compact version replaces the previous two-stage 22-bit CIC with
 * two 11-bit accumulators. It is intended to reduce silicon area.
 *
 * This is a learning prototype. Real reception will require RF/analog
 * verification, stronger channel filtering, gain control, and tuning tests.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_keropiyo_am_radio (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ----------------------------------------------------------------
    // Pin assignments
    // ----------------------------------------------------------------
    wire comparator_in = ui_in[0];
    wire encoder_a     = ui_in[1];
    wire encoder_b     = ui_in[2];
    wire mute_in       = ui_in[3];
    wire tune_home_in  = ui_in[4];

    // ----------------------------------------------------------------
    // Synchronize external inputs
    // ----------------------------------------------------------------
    reg comp_meta;
    reg comp_sync;
    reg comp_feedback;

    reg enc_a_meta;
    reg enc_a_sync;
    reg enc_b_meta;
    reg enc_b_sync;

    reg mute_meta;
    reg mute_sync;
    reg home_meta;
    reg home_sync;

    always @(posedge clk) begin
        if (!rst_n) begin
            comp_meta     <= 1'b0;
            comp_sync     <= 1'b0;
            comp_feedback <= 1'b0;

            enc_a_meta <= 1'b0;
            enc_a_sync <= 1'b0;
            enc_b_meta <= 1'b0;
            enc_b_sync <= 1'b0;

            mute_meta <= 1'b0;
            mute_sync <= 1'b0;
            home_meta <= 1'b0;
            home_sync <= 1'b0;
        end else begin
            comp_meta     <= comparator_in;
            comp_sync     <= comp_meta;
            comp_feedback <= comp_sync;

            enc_a_meta <= encoder_a;
            enc_a_sync <= enc_a_meta;
            enc_b_meta <= encoder_b;
            enc_b_sync <= enc_b_meta;

            mute_meta <= mute_in;
            mute_sync <= mute_meta;
            home_meta <= tune_home_in;
            home_sync <= home_meta;
        end
    end

    // The delayed comparator result is returned through an RC network
    // to the other comparator input. Together they form a 1-bit ADC loop.
    wire comp_out = comp_feedback;

    // ----------------------------------------------------------------
    // Rotary encoder and AM tuning
    //
    // 24-bit NCO tuning word:
    // tuning_word = frequency_hz * 2^24 / 50_000_000
    //
    // Japanese medium-wave channels use 9 kHz spacing.
    // Channel 0   = approximately 531 kHz
    // Channel 31  = approximately 810 kHz (reset/home)
    // Channel 119 = approximately 1602 kHz
    // ----------------------------------------------------------------
    localparam [23:0] TUNE_MIN   = 24'd178174;
    localparam [23:0] TUNE_STEP  = 24'd3020;
    localparam [23:0] TUNE_START = 24'd271794;
    localparam [23:0] TUNE_MAX   = 24'd537554;

    reg [23:0] tuning_word;
    reg [6:0]  channel_number;

    reg [1:0] enc_previous;
    reg signed [2:0] enc_quarter_steps;

    wire [1:0] enc_now = {enc_a_sync, enc_b_sync};

    always @(posedge clk) begin
        if (!rst_n) begin
            tuning_word       <= TUNE_START;
            channel_number    <= 7'd31;
            enc_previous      <= 2'b00;
            enc_quarter_steps <= 3'sd0;
        end else if (home_sync) begin
            tuning_word       <= TUNE_START;
            channel_number    <= 7'd31;
            enc_previous      <= enc_now;
            enc_quarter_steps <= 3'sd0;
        end else if (enc_now != enc_previous) begin
            case ({enc_previous, enc_now})
                // One direction: 00 -> 01 -> 11 -> 10 -> 00
                4'b0001, 4'b0111, 4'b1110, 4'b1000: begin
                    if (enc_quarter_steps == 3'sd3) begin
                        enc_quarter_steps <= 3'sd0;

                        if (tuning_word < TUNE_MAX) begin
                            tuning_word    <= tuning_word + TUNE_STEP;
                            channel_number <= channel_number + 1'b1;
                        end
                    end else begin
                        enc_quarter_steps <= enc_quarter_steps + 1'b1;
                    end
                end

                // Opposite direction
                4'b0010, 4'b1011, 4'b1101, 4'b0100: begin
                    if (enc_quarter_steps == -3'sd3) begin
                        enc_quarter_steps <= 3'sd0;

                        if (tuning_word > TUNE_MIN) begin
                            tuning_word    <= tuning_word - TUNE_STEP;
                            channel_number <= channel_number - 1'b1;
                        end
                    end else begin
                        enc_quarter_steps <= enc_quarter_steps - 1'b1;
                    end
                end

                // Invalid transition, usually caused by contact bounce.
                default: begin
                    enc_quarter_steps <= 3'sd0;
                end
            endcase

            enc_previous <= enc_now;
        end
    end

    // ----------------------------------------------------------------
    // Numerically controlled oscillator (NCO)
    // ----------------------------------------------------------------
    reg [23:0] phase_accumulator;

    always @(posedge clk) begin
        if (!rst_n)
            phase_accumulator <= 24'd0;
        else
            phase_accumulator <= phase_accumulator + tuning_word;
    end

    // Quadrature square-wave local oscillators.
    // cos: + - - + across the four quadrants
    // sin: + + - - across the four quadrants
    wire lo_i_positive =
        ~(phase_accumulator[23] ^ phase_accumulator[22]);

    wire lo_q_positive =
        ~phase_accumulator[23];

    // Treat comparator output as +1 or -1 and mix with the two LOs.
    wire signed [1:0] mixer_i =
        (comp_sync == lo_i_positive) ? 2'sd1 : -2'sd1;

    wire signed [1:0] mixer_q =
        (comp_sync == lo_q_positive) ? 2'sd1 : -2'sd1;

    // ----------------------------------------------------------------
    // Compact one-stage I/Q accumulate-and-dump decimator
    //
    // Sum 512 mixer samples, output the sums, then clear the accumulators.
    // 50 MHz / 512 = 97.65625 ksample/s
    // ----------------------------------------------------------------
    wire signed [10:0] baseband_i;
    wire signed [10:0] baseband_q;
    wire sample_tick;

    keropiyo_accumulate_dump_iq #(
        .DECIM_BITS(9)
    ) compact_filter (
        .clk(clk),
        .rst_n(rst_n),
        .i_in(mixer_i),
        .q_in(mixer_q),
        .i_out(baseband_i),
        .q_out(baseband_q),
        .out_valid(sample_tick)
    );

    // ----------------------------------------------------------------
    // AM envelope detector
    //
    // sqrt(I^2 + Q^2) is expensive. Use:
    // abs(I) + abs(Q)
    // ----------------------------------------------------------------
    function [10:0] abs11;
        input signed [10:0] value;

        begin
            abs11 = value[10] ? (~value + 1'b1) : value;
        end
    endfunction

    wire [10:0] i_absolute = abs11(baseband_i);
    wire [10:0] q_absolute = abs11(baseband_q);

    wire [11:0] envelope_sum =
        {1'b0, i_absolute} + {1'b0, q_absolute};

    // The one-stage filter has a gain of 512 instead of 512^2.
    // Multiply by four using wiring only, then saturate to 12 bits.
    wire [13:0] envelope_scaled =
        {envelope_sum, 2'b00};

    wire envelope_overflow =
        |envelope_scaled[13:12];

    wire [11:0] envelope_now =
        envelope_overflow ? 12'hfff : envelope_scaled[11:0];

    // ----------------------------------------------------------------
    // Remove the carrier/DC component and create an 8-bit audio level
    // ----------------------------------------------------------------
    reg signed [15:0] dc_estimate;
    reg        [7:0]  audio_level;

    wire signed [15:0] envelope_signed =
        $signed({4'b0000, envelope_now});

    wire signed [15:0] dc_error =
        envelope_signed - dc_estimate;

    // Gain for this prototype. Adjust after simulation and bench tests.
    wire signed [15:0] audio_scaled =
        16'sd128 + (dc_error >>> 2);

    reg [7:0] audio_next;

    always @* begin
        if (audio_scaled < 16'sd0)
            audio_next = 8'd0;
        else if (audio_scaled > 16'sd255)
            audio_next = 8'd255;
        else
            audio_next = audio_scaled[7:0];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            dc_estimate <= 16'sd0;
            audio_level <= 8'd128;
        end else if (sample_tick) begin
            // Slow IIR average tracks the carrier level.
            dc_estimate <= dc_estimate + (dc_error >>> 8);
            audio_level <= audio_next;
        end
    end

    // ----------------------------------------------------------------
    // PWM audio output: 50 MHz / 256 = 195.3125 kHz PWM carrier
    // ----------------------------------------------------------------
    reg [7:0] pwm_counter;

    always @(posedge clk) begin
        if (!rst_n)
            pwm_counter <= 8'd0;
        else
            pwm_counter <= pwm_counter + 1'b1;
    end

    // Muting holds the PWM at 50% duty, producing no AC audio after
    // the coupling/filter network.
    wire [7:0] pwm_level =
        mute_sync ? 8'd128 : audio_level;

    wire pwm_audio =
        pwm_counter < pwm_level;

    // ----------------------------------------------------------------
    // Tiny Tapeout outputs
    // ----------------------------------------------------------------
    assign uo_out[0]   = comp_out;
    assign uo_out[1]   = pwm_audio;
    assign uo_out[2]   = sample_tick;
    assign uo_out[7:3] = audio_level[7:3];

    // Expose the selected 9 kHz channel number for debugging/display.
    assign uio_out = {1'b0, channel_number};
    assign uio_oe  = 8'hff;

    // Avoid unused-input warnings.
    wire _unused = &{
        ena,
        ui_in[7:5],
        uio_in,
        1'b0
    };

endmodule


// ====================================================================
// Compact one-stage I/Q accumulate-and-dump decimator
//
// With 512 input values of +1 or -1, the output range is -512 to +512.
// An 11-bit signed value is sufficient.
// ====================================================================
module keropiyo_accumulate_dump_iq #(
    parameter integer DECIM_BITS = 9
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire signed [1:0]       i_in,
    input  wire signed [1:0]       q_in,
    output reg  signed [10:0]      i_out,
    output reg  signed [10:0]      q_out,
    output reg                     out_valid
);

    reg [DECIM_BITS-1:0] decim_counter;

    reg signed [10:0] i_accumulator;
    reg signed [10:0] q_accumulator;

    wire signed [10:0] i_extended =
        {{9{i_in[1]}}, i_in};

    wire signed [10:0] q_extended =
        {{9{q_in[1]}}, q_in};

    wire signed [10:0] i_sum_next =
        i_accumulator + i_extended;

    wire signed [10:0] q_sum_next =
        q_accumulator + q_extended;

    always @(posedge clk) begin
        if (!rst_n) begin
            decim_counter <= {DECIM_BITS{1'b0}};

            i_accumulator <= 11'sd0;
            q_accumulator <= 11'sd0;

            i_out     <= 11'sd0;
            q_out     <= 11'sd0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= 1'b0;

            if (&decim_counter) begin
                decim_counter <= {DECIM_BITS{1'b0}};

                // Include the current mixer sample in this 512-sample block.
                i_out <= i_sum_next;
                q_out <= q_sum_next;

                i_accumulator <= 11'sd0;
                q_accumulator <= 11'sd0;

                out_valid <= 1'b1;
            end else begin
                decim_counter <= decim_counter + 1'b1;

                i_accumulator <= i_sum_next;
                q_accumulator <= q_sum_next;
            end
        end
    end

endmodule

`default_nettype wire
