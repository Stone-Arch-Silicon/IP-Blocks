`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Module Name: array_os
// Project Name: Systolic Array IP
//
// Description:
// Builds a parameterized output-stationary mesh with input skew delays.
// Activations move right and weights move down while each PE retains
// its carry-save partial result. Drain shifts accumulator state upward
// so the top boundary emits one complete result row per enabled cycle.
//
// Revision:
// Revision 0.01 - Initial parameterized implementation.
// Revision 0.02 - Readability, section comments, and module documentation.
// Revision 0.03 - Short module names and explicit controller FSMs.
// Additional Comments:
// Configure the IP in rtl/sa_pkg.sv and re-elaborate after edits.
// Port names and cycle timing are retained; module names are shortened.
//////////////////////////////////////////////////////////////////////////////////

module array_os
    import sa_pkg::*;
(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   clear,
    input  logic                   ce,
    input  logic                   valid_i,
    input  logic                   first_i,
    input  logic                   last_i,
    input  logic                   drain,
    input  logic [ROW_COUNT_W-1:0] active_rows,
    input  logic [COL_COUNT_W-1:0] active_cols,
    input  operand_t               a_i        [ROWS],
    input  operand_t               b_i        [COLS],
    output accum_t                 sum_o      [COLS],
    output accum_t                 carry_o    [COLS],
    output special_t               special_o  [COLS],
    output logic                   done_o
);

    // -------------------------------------------------------------------------
    // Nearest-neighbor operand, tag, and accumulator connections
    // -------------------------------------------------------------------------
    operand_t   a      [ROWS][COLS+1];
    operand_t   b      [ROWS+1][COLS];
    logic       av     [ROWS][COLS+1];
    logic       bv     [ROWS+1][COLS];
    logic [1:0] tag    [ROWS][COLS+1];
    accum_t     sums   [ROWS+1][COLS];
    accum_t     carries[ROWS+1][COLS];
    special_t   flags  [ROWS+1][COLS];
    logic       done   [ROWS][COLS];

    // -------------------------------------------------------------------------
    // Skew activation row r by r enabled cycles
    // -------------------------------------------------------------------------
    for (genvar r = 0; r < ROWS; r++) begin : g_a_skew
        delay #(
            .W    (OPERAND_W + 2),
            .DEPTH(r)
        ) u_skew (
            .clk    (clk),
            .rst_n  (rst_n),
            .clear  (clear),
            .ce     (ce),
            .valid_i(valid_i),
            .data_i ({a_i[r], first_i, last_i}),
            .valid_o(av[r][0]),
            .data_o ({a[r][0], tag[r][0]})
        );
    end

    // -------------------------------------------------------------------------
    // Skew weight column c and terminate the result drain chain
    // The bottom inserts zero state during drain; the top exports one row.
    // -------------------------------------------------------------------------
    for (genvar c = 0; c < COLS; c++) begin : g_b_skew
        delay #(
            .W    (OPERAND_W),
            .DEPTH(c)
        ) u_skew (
            .clk    (clk),
            .rst_n  (rst_n),
            .clear  (clear),
            .ce     (ce),
            .valid_i(valid_i),
            .data_i (b_i[c]),
            .valid_o(bv[0][c]),
            .data_o (b[0][c])
        );
        assign sums[ROWS][c]    = '0;
        assign carries[ROWS][c] = '0;
        assign flags[ROWS][c]   = '0;
        assign sum_o[c]         = sums[0][c];
        assign carry_o[c]       = carries[0][c];
        assign special_o[c]     = flags[0][c];
    end

    // -------------------------------------------------------------------------
    // Generate the ROWS x COLS output-stationary mesh
    // Operand movement: A to the right, B downward.
    // Drain movement: sum/carry/exception state upward through local links.
    // -------------------------------------------------------------------------
    for (genvar r = 0; r < ROWS; r++) begin : g_row
        for (genvar c = 0; c < COLS; c++) begin : g_col
            pe_os u_pe (
                .clk             (clk),
                .rst_n           (rst_n),
                .clear           (clear),
                .ce              (ce),
                .active          ((r < active_rows) && (c < active_cols)),
                .a_i             (a[r][c]),
                .b_i             (b[r][c]),
                .av_i            (av[r][c]),
                .bv_i            (bv[r][c]),
                .tag_i           (tag[r][c]),
                .a_o             (a[r][c+1]),
                .b_o             (b[r+1][c]),
                .av_o            (av[r][c+1]),
                .bv_o            (bv[r+1][c]),
                .tag_o           (tag[r][c+1]),
                .drain           (drain),
                .drain_sum_i     (sums[r+1][c]),
                .drain_carry_i   (carries[r+1][c]),
                .drain_special_i (flags[r+1][c]),
                .result_sum_o    (sums[r][c]),
                .result_carry_o  (carries[r][c]),
                .result_special_o(flags[r][c]),
                .last_done       (done[r][c])
            );
        end
    end

    // -------------------------------------------------------------------------
    // Detect completion at the last PE in the compute wavefront
    // -------------------------------------------------------------------------
    assign done_o = done[ROWS-1][COLS-1];
endmodule
