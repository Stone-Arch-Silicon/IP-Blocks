`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Module Name: product
// Project Name: Systolic Array IP
//
// Description:
// Produces one signed integer or exact binary16 product per enabled
// cycle. Integer mode uses one product register; FP16 mode uses decode,
// significand multiply, and fixed-point alignment stages. Optional
// transport registers extend latency without splitting the multiplier.
//
// Revision:
// Revision 0.01 - Initial parameterized implementation.
// Revision 0.02 - Readability, section comments, and module documentation.
// Revision 0.03 - Short module names and explicit controller FSMs.
// Additional Comments:
// Configure the IP in rtl/sa_pkg.sv and re-elaborate after edits.
// Port names and cycle timing are retained; module names are shortened.
//////////////////////////////////////////////////////////////////////////////////

module product
    import sa_pkg::*;
(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       clear,
    input  logic       ce,
    input  logic       valid_i,
    input  operand_t   a_i,
    input  operand_t   b_i,
    input  logic [1:0] tag_i,      // {first,last}
    output logic       valid_o,
    output accum_t     product_o,
    output special_t   special_o,
    output logic [1:0] tag_o
);

    // -------------------------------------------------------------------------
    // Common product, exception, and first/last tag signals
    // -------------------------------------------------------------------------
    accum_t     product;
    special_t   special;
    logic       valid;
    logic [1:0] tag;

    // -------------------------------------------------------------------------
    // Elaboration-time arithmetic selection
    // -------------------------------------------------------------------------
    if (NUMERIC_MODE == INTEGER_MODE) begin : g_int

        // -------------------------------------------------------------------------
        // Signed integer product: multiply, register, and sign-extend
        // -------------------------------------------------------------------------
        logic signed [2*OPERAND_W-1:0] p;

        always_ff @(posedge clk) begin
            if (!rst_n || clear)
                valid <= 1'b0;
            else if (ce)
                valid <= valid_i;
            if (ce && valid_i) begin
                p   <= $signed(a_i) * $signed(b_i);
                tag <= tag_i;
            end
        end
        assign product = ACC_W'($signed(p));
        assign special = '0;
    end else begin : g_fp

        // -------------------------------------------------------------------------
        // Three-stage binary16 product pipeline state
        // -------------------------------------------------------------------------
        logic [10:0]        ma;
        logic [10:0]        mb;
        logic [5:0]         shift1;
        logic [5:0]         shift2;
        logic               sign1;
        logic               sign2;
        logic [21:0]        mant_product;
        logic [2:0]         v;
        logic [1:0]         tags           [3];
        special_t           f1;
        special_t           f2;
        special_t           f3;
        special_t           decoded;
        logic               az;
        logic               bz;
        logic               ai;
        logic               bi;
        logic               an;
        logic               bn;
        logic signed [22:0] signed_product;
        logic [5:0]         ea;
        logic [5:0]         eb;

        // -------------------------------------------------------------------------
        // Classify operands and prepare fixed-point alignment
        // Finite half-precision values are significand integers scaled by
        // 2^(effective_exponent - 25). Their product uses accumulator units
        // of 2^-48, giving a left shift of ea + eb - 2.
        // Special values travel as metadata and contribute zero numeric payload.
        // -------------------------------------------------------------------------
        always_comb begin
            az = (a_i[14:0] == 0);
            bz = (b_i[14:0] == 0);
            ai = (&a_i[14:10]) && (a_i[9:0] == 0);
            bi = (&b_i[14:10]) && (b_i[9:0] == 0);
            an = (&a_i[14:10]) && (a_i[9:0] != 0);
            bn = (&b_i[14:10]) && (b_i[9:0] != 0);
            decoded = '0;
            decoded.invalid = (an && !a_i[9]) || (bn && !b_i[9]) || (ai && bz) || (bi && az);
            decoded.nan = an || bn || decoded.invalid;
            decoded.pos_inf = !decoded.nan && (ai || bi) && !(a_i[15] ^ b_i[15]);
            decoded.neg_inf = !decoded.nan && (ai || bi) && (a_i[15] ^ b_i[15]);
            ea = (a_i[14:10] == 0) ? 6'd1 : {1'b0, a_i[14:10]};
            eb = (b_i[14:10] == 0) ? 6'd1 : {1'b0, b_i[14:10]};
            signed_product = sign2 ? -$signed({1'b0, mant_product}) : $signed({1'b0, mant_product});
        end
        // -------------------------------------------------------------------------
        // Advance FP validity and data together on each enabled clock
        // -------------------------------------------------------------------------
        always_ff @(posedge clk) begin
            if (!rst_n || clear)
                v <= '0;
            else if (ce)
                v <= {v[1:0], valid_i};
            if (ce) begin

                // -------------------------------------------------------------------------
                // Stage 1: capture significands, exponent shift, sign, and tags
                // -------------------------------------------------------------------------
                if (valid_i) begin
                    ma      <= {(a_i[14:10] != 0), a_i[9:0]};
                    mb      <= {(b_i[14:10] != 0), b_i[9:0]};
                    shift1  <= ea + eb - 6'd2;
                    sign1   <= a_i[15] ^ b_i[15];
                    f1      <= decoded;
                    tags[0] <= tag_i;
                end

                // -------------------------------------------------------------------------
                // Stage 2: multiply the two 11-bit significands
                // -------------------------------------------------------------------------
                if (v[0]) begin
                    mant_product <= ma * mb;
                    shift2       <= shift1;
                    sign2        <= sign1;
                    f2           <= f1;
                    tags[1]      <= tags[0];
                end

                // -------------------------------------------------------------------------
                // Stage 3: sign and align the exact product into the accumulator
                // -------------------------------------------------------------------------
                if (v[1]) begin
                    product <= (|f2) ? '0 : (ACC_W'(signed_product) <<< shift2);
                    f3      <= f2;
                    tags[2] <= tags[1];
                end
            end
        end
        assign valid   = v[2];
        assign special = f3;
        assign tag     = tags[2];
    end

    // -------------------------------------------------------------------------
    // Optional enabled transport stages
    // Product, exception metadata, and first/last tags remain aligned.
    // -------------------------------------------------------------------------
    delay #(
        .W    (ACC_W + 6),
        .DEPTH(EXTRA_PRODUCT_REGS)
    ) u_extra (
        .clk    (clk),
        .rst_n  (rst_n),
        .clear  (clear),
        .ce     (ce),
        .valid_i(valid),
        .data_i ({product, special, tag}),
        .valid_o(valid_o),
        .data_o ({product_o, special_o, tag_o})
    );
endmodule
