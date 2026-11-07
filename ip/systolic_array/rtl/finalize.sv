`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Module Name: finalize
// Project Name: Systolic Array IP
//
// Description:
// Converts one carry-save result into the configured output format.
// Stage 1 propagates carry; stage 2 registers integer output or rounds
// the exact fixed-point sum to binary16/binary32 using ties-to-even.
// Exception flags use {NV, DZ, OF, UF, NX}; division-by-zero is zero.
//
// Revision:
// Revision 0.01 - Initial parameterized implementation.
// Revision 0.02 - Readability, section comments, and module documentation.
// Revision 0.03 - Short module names and explicit controller FSMs.
// Additional Comments:
// Configure the IP in rtl/sa_pkg.sv and re-elaborate after edits.
// Port names and cycle timing are retained; module names are shortened.
//////////////////////////////////////////////////////////////////////////////////

module finalize
    import sa_pkg::*;
(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       clear,
    input  logic       ce,
    input  logic       valid_i,
    input  accum_t     sum_i,
    input  accum_t     carry_i,
    input  special_t   special_i,
    output logic       valid_o,
    output result_t    data_o,
    output logic [4:0] flags_o
);

    // -------------------------------------------------------------------------
    // Stage 1: resolve carry-save state with one carry-propagating add
    // -------------------------------------------------------------------------
    accum_t   total_q;
    special_t special_q;
    logic     v;
    always_ff @(posedge clk) begin
        if (!rst_n || clear) begin
            v       <= 0;
            valid_o <= 0;
        end else if (ce) begin
            v       <= valid_i;
            valid_o <= v;
        end
        if (ce && valid_i) begin
            total_q   <= sum_i + carry_i;
            special_q <= special_i;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2: elaborate either integer output or floating-point rounding
    // -------------------------------------------------------------------------
    if (NUMERIC_MODE == INTEGER_MODE) begin : g_integer
        always_ff @(posedge clk)
            if (ce && v) begin
                data_o  <= total_q;
                flags_o <= '0;
            end
    end else begin : g_float

        // -------------------------------------------------------------------------
        // Floating-point format constants and exact-sum quantizer
        // -------------------------------------------------------------------------
        localparam int F = (FP_RESULT_W == 16) ? 10 : 23;
        localparam int E = (FP_RESULT_W == 16) ? 5 : 8;
        localparam int BIAS = (1 << (E - 1)) - 1;
        localparam int EMIN = 1 - BIAS;
        localparam int EMAX = BIAS;
        function automatic logic [RESULT_W+4:0] round_exact(
            input  accum_t   value,
            input  special_t special
        );
            accum_t       magnitude;
            accum_t       shifted;
            logic         sign_bit;
            logic         guard_bit;
            logic         sticky_bit;
            logic         inexact_bit;
            logic [F+1:0] rounded;
            logic [E-1:0] exponent_bits;
            logic [F-1:0] fraction_bits;
            logic [4:0]   status;
            result_t      result_bits;
            integer       lead;
            integer       exponent;
            integer       shift_by;
            begin

                // -------------------------------------------------------------------------
                // Locate the magnitude leading bit and choose the output quantum
                // The accumulator binary point is fixed at 48 fractional bits.
                // For a subnormal result, clamp the quantum to the minimum exponent.
                // -------------------------------------------------------------------------
                sign_bit  = value[ACC_W-1];
                magnitude = sign_bit ? (~value + ACC_W'(1)) : value;
                lead      = 0;
                for (int i = 0; i < ACC_W; i++)
                    if (magnitude[i])
                        lead = i;
                exponent = lead - 48;
                shift_by = (exponent < EMIN) ? (EMIN - F + 48) : (lead - F);
                shifted  = (shift_by >= 0) ? (magnitude >> shift_by) : (magnitude << (-shift_by));

                // -------------------------------------------------------------------------
                // Round once to nearest, with ties to an even retained significand
                // Guard identifies the half-way bit; sticky ORs all lower discarded bits.
                // -------------------------------------------------------------------------
                guard_bit  = 0;
                sticky_bit = 0;
                for (int i = 0; i < ACC_W; i++) begin
                    if (i == shift_by - 1)
                        guard_bit = magnitude[i];
                    if (i < shift_by - 1)
                        sticky_bit |= magnitude[i];
                end
                inexact_bit = guard_bit | sticky_bit;
                rounded = {1'b0, shifted[F:0]} + (F + 2)'(guard_bit && (sticky_bit || shifted[0]));

                // -------------------------------------------------------------------------
                // Initialize output fields and resolve NaN/infinity/zero precedence
                // -------------------------------------------------------------------------
                status        = '0;
                exponent_bits = '0;
                fraction_bits = '0;
                result_bits   = '0;
                if (special.nan || (special.pos_inf && special.neg_inf)) begin
                    exponent_bits = '1;
                    fraction_bits[F-1] = 1'b1;  // Canonical quiet NaN.
                    sign_bit = 0;
                    status[4] = special.invalid || (special.pos_inf && special.neg_inf);
                end else if (special.pos_inf || special.neg_inf) begin
                    exponent_bits = '1;
                    sign_bit      = special.neg_inf;
                end else if (magnitude == 0) begin
                    sign_bit = 0;  // Exact zero, including cancellation, is canonical +0.
                end else begin

                    // -------------------------------------------------------------------------
                    // Pack finite results and report overflow or inexact underflow
                    // -------------------------------------------------------------------------
                    status[0] = inexact_bit;
                    if (exponent < EMIN) begin
                        // Tininess after rounding. A rounded minimum normal is not tiny.
                        exponent_bits = E'(rounded[F]);
                        fraction_bits = rounded[F-1:0];
                        status[1]     = inexact_bit && !rounded[F];
                    end else begin
                        if (rounded[F+1]) begin
                            rounded  = rounded >> 1;
                            exponent = exponent + 1;
                        end
                        if (exponent > EMAX) begin
                            exponent_bits = '1;
                            fraction_bits = '0;
                            status[2]     = 1;
                            status[0]     = 1;
                        end else begin
                            exponent_bits = E'(exponent + BIAS);
                            fraction_bits = rounded[F-1:0];
                        end
                    end
                end
                result_bits = {sign_bit, exponent_bits, fraction_bits};
                return {status, result_bits};
            end
        endfunction

        // -------------------------------------------------------------------------
        // Register the rounded result and matching exception flags
        // -------------------------------------------------------------------------
        always_ff @(posedge clk)
            if (ce && v)
                {flags_o, data_o} <= round_exact(total_q, special_q);
    end
endmodule
