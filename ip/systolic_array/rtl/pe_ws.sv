`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Module Name: pe_ws
// Project Name: Systolic Array IP
//
// Description:
// Implements one weight-stationary processing element with active and
// shadow weight storage. Forwards activations to the right and adds a
// pipelined product to the downward carry-save partial-sum wavefront.
// Shadow weights can load independently of compute clock enable.
//
// Revision:
// Revision 0.01 - Initial parameterized implementation.
// Revision 0.02 - Readability, section comments, and module documentation.
// Revision 0.03 - Short module names and explicit controller FSMs.
// Additional Comments:
// Configure the IP in rtl/sa_pkg.sv and re-elaborate after edits.
// Port names and cycle timing are retained; module names are shortened.
//////////////////////////////////////////////////////////////////////////////////

module pe_ws
    import sa_pkg::*;
(
    input  logic     clk,
    input  logic     rst_n,
    input  logic     clear,
    input  logic     ce,
    input  logic     active,
    input  logic     weight_we,
    input  logic     weight_write_bank,
    input  logic     weight_active_bank,
    input  operand_t weight_i,
    input  operand_t a_i,
    input  logic     av_i,
    output operand_t a_o,
    output logic     av_o,
    input  accum_t   sum_i,
    input  accum_t   carry_i,
    input  special_t special_i,
    input  logic     pv_i,
    input  logic     last_i,
    output accum_t   sum_o,
    output accum_t   carry_o,
    output special_t special_o,
    output logic     pv_o,
    output logic     last_o
);

    // -------------------------------------------------------------------------
    // Active/shadow weight storage and product pipeline signals
    // -------------------------------------------------------------------------
    operand_t   weights       [2];
    accum_t     product;
    special_t   pf;
    logic       product_valid;
    logic [1:0] unused_tag;

    // -------------------------------------------------------------------------
    // Independent shadow-bank loading and activation forwarding
    // Weight writes continue while ce is low. The controller writes only the
    // inactive bank and swaps banks between jobs, keeping active weights stable.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (weight_we)
            weights[weight_write_bank] <= weight_i;
        if (!rst_n || clear)
            av_o <= 0;
        else if (ce)
            av_o <= av_i;
        if (ce)
            a_o <= a_i;
    end

    // -------------------------------------------------------------------------
    // Multiply against the selected stationary weight
    // -------------------------------------------------------------------------
    product u_product (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (clear),
        .ce       (ce),
        .valid_i  (av_i),
        .a_i      (active ? a_i : operand_t'('0)),
        .b_i      (active ? weights[weight_active_bank] : operand_t'('0)),
        .tag_i    (2'b00),
        .valid_o  (product_valid),
        .product_o(product),
        .special_o(pf),
        .tag_o    (unused_tag)
    );

    // -------------------------------------------------------------------------
    // One-cycle downward carry-save reduction
    // The array skews the partial-sum valid and product valid to arrive
    // together; the multiplier latency does not extend this row-to-row hop.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n || clear)
            pv_o <= 0;
        else if (ce)
            pv_o <= pv_i && product_valid;
        if (ce && pv_i && product_valid) begin
            sum_o     <= sum_i ^ carry_i ^ product;
            carry_o   <= ((sum_i & carry_i) | (sum_i & product) | (carry_i & product)) << 1;
            special_o <= special_i | pf;
            last_o    <= last_i;
        end
    end

    // -------------------------------------------------------------------------
    // Simulation-only wavefront alignment check
    // -------------------------------------------------------------------------
    // synthesis translate_off
    always_ff @(posedge clk)
        if (rst_n && !clear && ce)
            assert (pv_i == product_valid)
            else
                $fatal(1, "WS wavefront misalignment");
    // synthesis translate_on
endmodule
