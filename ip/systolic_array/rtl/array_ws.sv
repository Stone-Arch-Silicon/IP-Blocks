`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Module Name: array_ws
// Project Name: Systolic Array IP
//
// Description:
// Builds a parameterized weight-stationary mesh with two weight banks.
// Skews activations and partial-sum tags to meet pipelined products,
// then deskews the bottom boundary into complete result rows.
// The partial-sum wavefront advances one row per enabled cycle.
//
// Revision:
// Revision 0.01 - Initial parameterized implementation.
// Revision 0.02 - Readability, section comments, and module documentation.
// Revision 0.03 - Short module names and explicit controller FSMs.
// Additional Comments:
// Configure the IP in rtl/sa_pkg.sv and re-elaborate after edits.
// Port names and cycle timing are retained; module names are shortened.
//////////////////////////////////////////////////////////////////////////////////

module array_ws
    import sa_pkg::*;
(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   clear,
    input  logic                   ce,
    input  logic                   valid_i,
    input  logic                   last_i,
    input  logic [ROW_COUNT_W-1:0] active_rows,
    input  logic [COL_COUNT_W-1:0] active_cols,
    input  operand_t               a_i               [ROWS],
    input  operand_t               weight_i          [COLS],
    input  logic                   weight_we,
    input  logic                   weight_write_bank,
    input  logic                   weight_active_bank,
    input  logic [ROW_COUNT_W-1:0] weight_row,
    output accum_t                 sum_o             [COLS],
    output accum_t                 carry_o           [COLS],
    output special_t               special_o         [COLS],
    output logic                   valid_o,
    output logic                   last_o
);

    // -------------------------------------------------------------------------
    // Activation, partial-sum, and result-alignment connections
    // -------------------------------------------------------------------------
    operand_t a            [ROWS] [COLS+1];
    logic     av           [ROWS] [COLS+1];
    accum_t   sums         [ROWS+1] [COLS];
    accum_t   carries      [ROWS+1] [COLS];
    special_t flags        [ROWS+1] [COLS];
    logic     pv           [ROWS+1] [COLS];
    logic     last         [ROWS+1] [COLS];
    logic     aligned_valid[COLS];
    logic     aligned_last [COLS];

    // -------------------------------------------------------------------------
    // Skew activation row r to meet the downward sum wavefront
    // -------------------------------------------------------------------------
    for (genvar r = 0; r < ROWS; r++) begin : g_a_skew
        delay #(
            .W    (OPERAND_W),
            .DEPTH(r * WS_HOP)
        ) u_skew (
            .clk    (clk),
            .rst_n  (rst_n),
            .clear  (clear),
            .ce     (ce),
            .valid_i(valid_i),
            .data_i (a_i[r]),
            .valid_o(av[r][0]),
            .data_o (a[r][0])
        );
    end

    // -------------------------------------------------------------------------
    // Initialize column sums, align input tags, and deskew output columns
    // Products lead partial sums by PRODUCT_LATENCY. Column c enters c
    // cycles later, then receives COLS-1-c output delay to align the row.
    // -------------------------------------------------------------------------
    for (genvar c = 0; c < COLS; c++) begin : g_col_boundary
        assign sums[0][c]    = '0;
        assign carries[0][c] = '0;
        assign flags[0][c]   = '0;
        delay #(
            .W    (1),
            .DEPTH(PRODUCT_LATENCY + c)
        ) u_tag_skew (
            .clk    (clk),
            .rst_n  (rst_n),
            .clear  (clear),
            .ce     (ce),
            .valid_i(valid_i),
            .data_i (last_i),
            .valid_o(pv[0][c]),
            .data_o (last[0][c])
        );
        delay #(
            .W    (2 * ACC_W + 5),
            .DEPTH(COLS - 1 - c)
        ) u_deskew (
            .clk    (clk),
            .rst_n  (rst_n),
            .clear  (clear),
            .ce     (ce),
            .valid_i(pv[ROWS][c]),
            .data_i ({sums[ROWS][c], carries[ROWS][c], flags[ROWS][c], last[ROWS][c]}),
            .valid_o(aligned_valid[c]),
            .data_o ({sum_o[c], carry_o[c], special_o[c], aligned_last[c]})
        );
        // synthesis translate_off
        always_ff @(posedge clk)
            if (rst_n && !clear && ce)
                assert (aligned_valid[c] == aligned_valid[COLS-1])
                else
                    $fatal(1, "WS output deskew misalignment");
        // synthesis translate_on
    end

    // -------------------------------------------------------------------------
    // Generate the ROWS x COLS weight-stationary mesh
    // The row decoder writes one shadow-bank weight row per accepted beat.
    // -------------------------------------------------------------------------
    for (genvar r = 0; r < ROWS; r++) begin : g_row
        for (genvar c = 0; c < COLS; c++) begin : g_col
            pe_ws u_pe (
                .clk               (clk),
                .rst_n             (rst_n),
                .clear             (clear),
                .ce                (ce),
                .active            ((r < active_rows) && (c < active_cols)),
                .weight_we         (weight_we && (weight_row == r)),
                .weight_write_bank (weight_write_bank),
                .weight_active_bank(weight_active_bank),
                .weight_i          (weight_i[c]),
                .a_i               (a[r][c]),
                .av_i              (av[r][c]),
                .a_o               (a[r][c+1]),
                .av_o              (av[r][c+1]),
                .sum_i             (sums[r][c]),
                .carry_i           (carries[r][c]),
                .special_i         (flags[r][c]),
                .pv_i              (pv[r][c]),
                .last_i            (last[r][c]),
                .sum_o             (sums[r+1][c]),
                .carry_o           (carries[r+1][c]),
                .special_o         (flags[r+1][c]),
                .pv_o              (pv[r+1][c]),
                .last_o            (last[r+1][c])
            );
        end
    end

    // -------------------------------------------------------------------------
    // Export the aligned row-valid and last-row tag
    // -------------------------------------------------------------------------
    assign valid_o = aligned_valid[COLS-1];
    assign last_o  = aligned_last[COLS-1];
endmodule
