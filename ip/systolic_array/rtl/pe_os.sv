`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Module Name: pe_os
// Project Name: Systolic Array IP
//
// Description:
// Implements one output-stationary processing element.
// Forwards operands, pipelines multiplication, and accumulates products
// as sum/carry state without a carry-propagating feedback path.
// Reuses the accumulator registers as a vertical result drain chain.
//
// Revision:
// Revision 0.01 - Initial parameterized implementation.
// Revision 0.02 - Readability, section comments, and module documentation.
// Revision 0.03 - Short module names and explicit controller FSMs.
// Additional Comments:
// Configure the IP in rtl/sa_pkg.sv and re-elaborate after edits.
// Port names and cycle timing are retained; module names are shortened.
//////////////////////////////////////////////////////////////////////////////////

module pe_os
    import sa_pkg::*;
(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       clear,
    input  logic       ce,
    input  logic       active,
    input  operand_t   a_i,
    input  operand_t   b_i,
    input  logic       av_i,
    input  logic       bv_i,
    input  logic [1:0] tag_i,
    output operand_t   a_o,
    output operand_t   b_o,
    output logic       av_o,
    output logic       bv_o,
    output logic [1:0] tag_o,
    input  logic       drain,
    input  accum_t     drain_sum_i,
    input  accum_t     drain_carry_i,
    input  special_t   drain_special_i,
    output accum_t     result_sum_o,
    output accum_t     result_carry_o,
    output special_t   result_special_o,
    output logic       last_done
);

    // -------------------------------------------------------------------------
    // Product pipeline and local carry-save accumulator state
    // -------------------------------------------------------------------------
    accum_t     p;
    accum_t     sum_q;
    accum_t     carry_q;
    accum_t     x;
    accum_t     y;
    accum_t     sum_next;
    accum_t     carry_next;
    special_t   pf;
    special_t   flags_q;
    special_t   flags_next;
    logic       pv;
    logic [1:0] pt;

    // -------------------------------------------------------------------------
    // One-cycle operand forwarding to the right and below
    // The first/last tag follows the activation wavefront. Payload registers
    // are deliberately unreset; cleared valid bits flush in-flight work.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n || clear) begin
            av_o <= 0;
            bv_o <= 0;
        end else if (ce) begin
            av_o <= av_i;
            bv_o <= bv_i;
        end
        if (ce) begin
            a_o   <= a_i;
            b_o   <= b_i;
            tag_o <= tag_i;
        end
    end

    // -------------------------------------------------------------------------
    // Pipelined multiply with inactive-lane zero masking
    // -------------------------------------------------------------------------
    product u_product (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (clear),
        .ce       (ce),
        .valid_i  (av_i && bv_i),
        .a_i      (active ? a_i : operand_t'('0)),
        .b_i      (active ? b_i : operand_t'('0)),
        .tag_i    (tag_i),
        .valid_o  (pv),
        .product_o(p),
        .special_o(pf),
        .tag_o    (pt)
    );

    // -------------------------------------------------------------------------
    // Carry-save accumulation and first-product initialization
    // pt[1] marks the first term, so a new dot product starts from zero
    // without resetting the wide sum/carry registers.
    // -------------------------------------------------------------------------
    // No carry-propagating adder in the accumulation recurrence.
    assign x          = pt[1] ? '0 : sum_q;
    assign y          = pt[1] ? '0 : carry_q;
    assign sum_next   = x ^ y ^ p;
    assign carry_next = ((x & y) | (x & p) | (y & p)) << 1;
    assign flags_next = (pt[1] ? special_t'('0) : flags_q) | pf;

    // -------------------------------------------------------------------------
    // Accumulator update, completion pulse, and vertical result drain
    // Products have priority over drain. The engine drains only after the
    // bottom-right PE completes, so no valid product is overwritten.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n || clear)
            last_done <= 0;
        else if (ce)
            last_done <= pv && pt[0];
        if (ce && pv) begin
            sum_q   <= sum_next;
            carry_q <= carry_next;
            flags_q <= flags_next;
        end else if (ce && drain) begin
            // Reuse accumulator storage for local row-by-row result drain.
            sum_q   <= drain_sum_i;
            carry_q <= drain_carry_i;
            flags_q <= drain_special_i;
        end
    end

    // -------------------------------------------------------------------------
    // Expose retained state to the row above or to the column finalizer
    // -------------------------------------------------------------------------
    assign result_sum_o     = sum_q;
    assign result_carry_o   = carry_q;
    assign result_special_o = flags_q;
endmodule
