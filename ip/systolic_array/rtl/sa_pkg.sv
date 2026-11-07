`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Package Name: sa_pkg
// Project Name: Systolic Array IP
//
// Description:
// Defines the only user-editable configuration surface for this IP.
// Selects the dataflow and numeric format at elaboration, derives safe
// accumulator and interface widths, and declares shared packed types.
//
// Only edit the fields inside USER CONFIGURATION
//
// Revision:
// Revision 0.01 - Initial parameterized implementation.
// Revision 0.02 - Readability, section comments, and module documentation.
// Revision 0.03 - Short module names and explicit controller FSMs.
// Additional Comments:
// Configure the IP in rtl/sa_pkg.sv and re-elaborate after edits.
// Port names and cycle timing are retained; module names are shortened.
//////////////////////////////////////////////////////////////////////////////////

package sa_pkg;

    // -------------------------------------------------------------------------
    // Supported elaboration choices
    // -------------------------------------------------------------------------
    localparam int OUTPUT_STATIONARY  = 0;
    localparam int WEIGHT_STATIONARY  = 1;
    localparam int INTEGER_MODE       = 0;
    localparam int FP16_MODE          = 1;

    // ===================== USER CONFIGURATION =====================
    localparam int DATAFLOW           = WEIGHT_STATIONARY;
    localparam int NUMERIC_MODE       = FP16_MODE;
    localparam int ROWS               = 8;
    localparam int COLS               = 8;
    localparam int INT_W              = 8;     // Signed two's complement: 2, 4 or 8.
    localparam int MAX_K              = 1024;  // Maximum OS reduction length.
    localparam int MAX_M              = 1024;  // Maximum WS activation rows/job.
    localparam int INT_ACC_OVERRIDE   = 0;     // 0 = automatic, otherwise >= safe bound.
    localparam int FP_RESULT_W        = 32;    // 16 or 32; FP operands are always binary16.
    localparam int EXTRA_PRODUCT_REGS = 0;     // Extra registered transport, not multiplier splitting.
    localparam int OUT_FIFO_DEPTH     = 4;     // >= 2; need not be a power of two.
    // ==============================================================
    // -------------------------------------------------------------------------
    // Derived widths and shared types - no user edits below this point
    // Minimum index widths remain one bit for a single row or column.
    // -------------------------------------------------------------------------
    function automatic integer imax(
        input  integer a,
        input  integer b
    );
        return (a > b) ? a : b;
    endfunction

    function automatic integer idx_width(
        input  integer n
    );
        return (n > 1) ? $clog2(n) : 1;
    endfunction

    // -------------------------------------------------------------------------
    // Numeric range and accumulator sizing
    // -------------------------------------------------------------------------
    localparam int OPERAND_W          = (NUMERIC_MODE == FP16_MODE) ? 16 : INT_W;
    localparam int MAX_TERMS          = (DATAFLOW == OUTPUT_STATIONARY) ? MAX_K : ROWS;
    localparam int INT_MIN_ACC_W      = 2 * INT_W + $clog2(imax(MAX_TERMS, 1));
    localparam int INT_ACC_W          = (INT_ACC_OVERRIDE == 0) ? imax(32, INT_MIN_ACC_W) : INT_ACC_OVERRIDE;
    // Every finite binary16 product is an integer multiple of 2^-48.
    // |a*b| < 2^32, hence < 2^80 accumulator units. Include sign + growth.
    localparam int FP_ACC_W           = 81 + $clog2(imax(MAX_TERMS, 1));
    localparam int ACC_W              = (NUMERIC_MODE == FP16_MODE) ? FP_ACC_W : INT_ACC_W;
    localparam int RESULT_W           = (NUMERIC_MODE == FP16_MODE) ? FP_RESULT_W : INT_ACC_W;

    // -------------------------------------------------------------------------
    // Pipeline timing and streaming interface dimensions
    // -------------------------------------------------------------------------
    localparam int PRODUCT_LATENCY    = ((NUMERIC_MODE == FP16_MODE) ? 3 : 1) + EXTRA_PRODUCT_REGS;
    // Products are formed ahead of the sum wavefront. The carry-save reduction
    // advances one row per cycle regardless of multiplier pipeline depth.
    localparam int WS_HOP             = 1;
    localparam int INPUT_LANES        = ROWS + ((DATAFLOW == OUTPUT_STATIONARY) ? COLS : 0);
    localparam int INPUT_W            = 8 * ((INPUT_LANES * OPERAND_W + 7) / 8);
    localparam int WEIGHT_W           = 8 * ((COLS * OPERAND_W + 7) / 8);
    localparam int OUTPUT_W           = 8 * ((COLS * RESULT_W + 7) / 8);
    localparam int USER_W             = 5 * COLS;
    localparam int CSR_ADDR_W         = 12;
    localparam int LENGTH_W           = idx_width(imax(MAX_K, MAX_M) + 1);
    localparam int ROW_COUNT_W        = idx_width(ROWS + 1);
    localparam int COL_COUNT_W        = idx_width(COLS + 1);

    // -------------------------------------------------------------------------
    // Shared datapath types
    // -------------------------------------------------------------------------
    typedef logic [OPERAND_W-1:0] operand_t;
    typedef logic [ACC_W-1:0] accum_t;
    typedef logic [RESULT_W-1:0] result_t;
    // OR-reducible exception metadata. Bit order deliberately documented.
    typedef struct packed {
        logic nan;
        logic invalid;
        logic pos_inf;
        logic neg_inf;
    } special_t;
endpackage
