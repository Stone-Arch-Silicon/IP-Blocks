`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Module Name: engine
// Project Name: Systolic Array IP
//
// Description:
// Schedules one matrix tile, routes input lanes to the selected array,
// and packs finalized result rows into an elastic output FIFO.
// Manages output-stationary drain or weight-stationary bank swapping.
// Separates the job FSM state register, next-state logic, and output decode.
// A shared clock enable freezes the compute pipeline under backpressure.
//
// Revision:
// Revision 0.01 - Initial parameterized implementation.
// Revision 0.02 - Readability, section comments, and module documentation.
// Revision 0.03 - Short module names and explicit controller FSMs.
// Additional Comments:
// Configure the IP in rtl/sa_pkg.sv and re-elaborate after edits.
// Port names and cycle timing are retained; module names are shortened.
//////////////////////////////////////////////////////////////////////////////////

module engine
    import sa_pkg::*;
(
    input  logic                clk,
    input  logic                rst_n,
    input  logic                start_i,
    input  logic                reuse_weights_i,
    input  logic [31:0]         length_i,
    input  logic [31:0]         rows_i,
    input  logic [31:0]         cols_i,
    output logic                busy_o,
    output logic                done_o,
    output logic                error_o,
    output logic                shadow_ready_o,
    output logic                active_weights_o,
    output logic [31:0]         cycles_o,
    output logic [31:0]         input_beats_o,
    output logic [31:0]         output_beats_o,
    input  logic [INPUT_W-1:0]  s_axis_tdata,
    input  logic                s_axis_tvalid,
    input  logic                s_axis_tlast,
    output logic                s_axis_tready,
    input  logic [WEIGHT_W-1:0] s_weight_tdata,
    input  logic                s_weight_tvalid,
    input  logic                s_weight_tlast,
    output logic                s_weight_tready,
    output logic [OUTPUT_W-1:0] m_axis_tdata,
    output logic [USER_W-1:0]   m_axis_tuser,
    output logic                m_axis_tvalid,
    output logic                m_axis_tlast,
    input  logic                m_axis_tready
);

    // -------------------------------------------------------------------------
    // Job state, captured dimensions, bank state, and datapath signals
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        RUN         = 3'b001,
        DRAIN       = 3'b010,
        OUTPUT_ROWS = 3'b011,
        WAIT_OUTPUT = 3'b100
    } state_t;
    state_t                state;
    state_t                next_state;
    logic                   ce;
    logic                   input_fire;
    logic                   weight_fire;
    logic                   output_fire;
    logic [LENGTH_W-1:0]    length_q;
    logic [LENGTH_W-1:0]    input_count;
    logic [ROW_COUNT_W-1:0] rows_q;
    logic [ROW_COUNT_W-1:0] output_row;
    logic [ROW_COUNT_W-1:0] weight_row;
    logic [COL_COUNT_W-1:0] cols_q;
    logic                   active_bank;
    logic                   shadow_ready;
    logic                   active_valid;
    operand_t               a            [ROWS];
    operand_t               b            [COLS];
    operand_t               w            [COLS];
    accum_t                 raw_sum      [COLS];
    accum_t                 raw_carry    [COLS];
    special_t               raw_special  [COLS];
    logic                   raw_valid;
    logic                   raw_last;
    logic                   array_done;
    logic                   array_drain;
    logic                   ws_valid;
    logic                   ws_last;
    logic                   final_valid  [COLS];
    logic                   final_last;
    logic                   last_valid;
    result_t                final_data   [COLS];
    logic [4:0]             final_flags  [COLS];
    logic [OUTPUT_W-1:0]    packed_data;
    logic [USER_W-1:0]      packed_flags;

    // -------------------------------------------------------------------------
    // Stream handshakes and weight-bank status
    // ce comes from FIFO space. It freezes every compute stage together,
    // while shadow weight loading uses its own independent handshake.
    // -------------------------------------------------------------------------
    assign shadow_ready_o   = shadow_ready;
    assign active_weights_o = active_valid;
    assign input_fire       = s_axis_tvalid && s_axis_tready;
    assign output_fire      = m_axis_tvalid && m_axis_tready;
    assign s_weight_tready  = (DATAFLOW == WEIGHT_STATIONARY) && !shadow_ready && !start_i;
    assign weight_fire      = s_weight_tvalid && s_weight_tready;

    // -------------------------------------------------------------------------
    // Job FSM state register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // -------------------------------------------------------------------------
    // Job FSM combinational next-state logic
    // Start has priority over completion. Completion follows the external
    // output handshake, even while ce is low because the FIFO was full.
    // -------------------------------------------------------------------------
    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                next_state = IDLE;
            end

            RUN: begin
                if (input_fire && input_count == length_q - 1'b1)
                    next_state = (DATAFLOW == OUTPUT_STATIONARY) ? DRAIN : WAIT_OUTPUT;
            end

            DRAIN: begin
                if (ce && array_done)
                    next_state = OUTPUT_ROWS;
            end

            OUTPUT_ROWS: begin
                if (ce && output_row == rows_q - 1'b1)
                    next_state = WAIT_OUTPUT;
            end

            WAIT_OUTPUT: begin
                next_state = WAIT_OUTPUT;
            end

            default: begin
                next_state = IDLE;
            end
        endcase

        if (start_i)
            next_state = RUN;
        else if (output_fire && m_axis_tlast)
            next_state = IDLE;
    end

    // -------------------------------------------------------------------------
    // Job FSM combinational output logic
    // Invalid encodings disable operand acceptance and drain until recovery.
    // -------------------------------------------------------------------------
    always_comb begin
        busy_o        = 1'b1;
        s_axis_tready = 1'b0;
        array_drain   = 1'b0;

        case (state)
            IDLE: begin
                busy_o = 1'b0;
            end

            RUN: begin
                s_axis_tready = ce;
            end

            OUTPUT_ROWS: begin
                array_drain = 1'b1;
            end

            DRAIN, WAIT_OUTPUT: begin
            end

            default: begin
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Unpack operand lanes with lane zero in the least-significant bits
    // -------------------------------------------------------------------------
    for (genvar r = 0; r < ROWS; r++) begin : g_input_a
        assign a[r] = s_axis_tdata[r*OPERAND_W+:OPERAND_W];
    end
    for (genvar c = 0; c < COLS; c++) begin : g_input_b
        assign w[c] = s_weight_tdata[c*OPERAND_W+:OPERAND_W];
        if (DATAFLOW == OUTPUT_STATIONARY) begin : g_os
            assign b[c] = s_axis_tdata[(ROWS+c)*OPERAND_W+:OPERAND_W];
        end else begin : g_ws
            assign b[c] = '0;
        end
    end

    // -------------------------------------------------------------------------
    // Elaborate exactly one stationary dataflow
    // OS retains every output in its PE, then drains active rows.
    // WS streams completed rows while activations continue to arrive.
    // -------------------------------------------------------------------------
    if (DATAFLOW == OUTPUT_STATIONARY) begin : g_os
        array_os u_array (
            .clk        (clk),
            .rst_n      (rst_n),
            .clear      (start_i),
            .ce         (ce),
            .valid_i    (input_fire),
            .first_i    (input_count == 0),
            .last_i     (input_count == length_q - 1'b1),
            .drain      (array_drain),
            .active_rows(rows_q),
            .active_cols(cols_q),
            .a_i        (a),
            .b_i        (b),
            .sum_o      (raw_sum),
            .carry_o    (raw_carry),
            .special_o  (raw_special),
            .done_o     (array_done)
        );
        assign raw_valid = array_drain;
        assign raw_last  = output_row == rows_q - 1'b1;
        assign ws_valid  = 0;
        assign ws_last   = 0;
    end else begin : g_ws
        array_ws u_array (
            .clk               (clk),
            .rst_n             (rst_n),
            .clear             (start_i),
            .ce                (ce),
            .valid_i           (input_fire),
            .last_i            (input_count == length_q - 1'b1),
            .active_rows       (rows_q),
            .active_cols       (cols_q),
            .a_i               (a),
            .weight_i          (w),
            .weight_we         (weight_fire),
            .weight_write_bank (!active_bank),
            .weight_active_bank(active_bank),
            .weight_row        (weight_row),
            .sum_o             (raw_sum),
            .carry_o           (raw_carry),
            .special_o         (raw_special),
            .valid_o           (ws_valid),
            .last_o            (ws_last)
        );
        assign raw_valid  = ws_valid;
        assign raw_last   = ws_last;
        assign array_done = 0;
    end

    // -------------------------------------------------------------------------
    // Finalize every output column in parallel
    // -------------------------------------------------------------------------
    for (genvar c = 0; c < COLS; c++) begin : g_finalize
        finalize u_finalize (
            .clk      (clk),
            .rst_n    (rst_n),
            .clear    (start_i),
            .ce       (ce),
            .valid_i  (raw_valid),
            .sum_i    (raw_sum[c]),
            .carry_i  (raw_carry[c]),
            .special_i(raw_special[c]),
            .valid_o  (final_valid[c]),
            .data_o   (final_data[c]),
            .flags_o  (final_flags[c])
        );
    end

    // -------------------------------------------------------------------------
    // Match the row-last tag to the two-stage finalizer latency
    // -------------------------------------------------------------------------
    delay #(
        .W    (1),
        .DEPTH(2)
    ) u_last (
        .clk    (clk),
        .rst_n  (rst_n),
        .clear  (start_i),
        .ce     (ce),
        .valid_i(raw_valid),
        .data_i (raw_last),
        .valid_o(last_valid),
        .data_o (final_last)
    );

    // -------------------------------------------------------------------------
    // Pack result lanes and five exception bits per column
    // -------------------------------------------------------------------------
    always_comb begin
        packed_data  = '0;
        packed_flags = '0;
        for (int c = 0; c < COLS; c++) begin
            packed_data[c*RESULT_W+:RESULT_W] = final_data[c];
            packed_flags[c*5+:5]              = final_flags[c];
        end
    end

    // -------------------------------------------------------------------------
    // Elastic output buffer and global pipeline backpressure
    // Registered FIFO occupancy drives ce; downstream ready cannot create
    // a combinational path through the full array.
    // -------------------------------------------------------------------------
    fifo #(
        .W    (OUTPUT_W + USER_W + 1),
        .DEPTH(OUT_FIFO_DEPTH)
    ) u_fifo (
        .clk    (clk),
        .rst_n  (rst_n),
        .s_valid(final_valid[0]),
        .s_ready(ce),
        .s_data ({packed_data, packed_flags, final_last}),
        .m_valid(m_axis_tvalid),
        .m_ready(m_axis_tready),
        .m_data ({m_axis_tdata, m_axis_tuser, m_axis_tlast})
    );

    // -------------------------------------------------------------------------
    // Job datapath registers, shadow weight loading, and performance counters
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            length_q       <= '0;
            rows_q         <= '0;
            cols_q         <= '0;
            input_count    <= '0;
            output_row     <= '0;
            weight_row     <= '0;
            active_bank    <= 0;
            shadow_ready   <= 0;
            active_valid   <= 0;
            done_o         <= 0;
            error_o        <= 0;
            cycles_o       <= 0;
            input_beats_o  <= 0;
            output_beats_o <= 0;
        end else begin
            done_o  <= 0;
            error_o <= 0;
            if (busy_o)
                cycles_o <= cycles_o + 1'b1;
            if (input_fire)
                input_beats_o <= input_beats_o + 1'b1;
            if (output_fire)
                output_beats_o <= output_beats_o + 1'b1;

            // -------------------------------------------------------------------------
            // Load a full physical weight tile into the inactive bank
            // -------------------------------------------------------------------------
            if (weight_fire) begin
                if (s_weight_tlast != (weight_row == ROW_COUNT_W'(ROWS - 1)))
                    error_o <= 1;
                if (weight_row == ROW_COUNT_W'(ROWS - 1)) begin
                    weight_row   <= '0;
                    shadow_ready <= 1;
                end else
                    weight_row <= weight_row + 1'b1;
            end

            // -------------------------------------------------------------------------
            // Capture an accepted command and select the weight bank
            // The CSR block validates commands before pulsing start_i.
            // -------------------------------------------------------------------------
            if (start_i) begin
                length_q       <= LENGTH_W'(length_i);
                rows_q         <= ROW_COUNT_W'(rows_i);
                cols_q         <= COL_COUNT_W'(cols_i);
                input_count    <= '0;
                output_row     <= '0;
                cycles_o       <= 0;
                input_beats_o  <= 0;
                output_beats_o <= 0;
                if (DATAFLOW == WEIGHT_STATIONARY && !reuse_weights_i) begin
                    active_bank  <= !active_bank;
                    active_valid <= 1;
                    shadow_ready <= 0;
                end
            end else begin

                // -------------------------------------------------------------------------
                // Advance input and drain counters only on their enabled beats
                // -------------------------------------------------------------------------
                if (input_fire) begin
                    if (s_axis_tlast != (input_count == length_q - 1'b1))
                        error_o <= 1;
                    if (input_count != length_q - 1'b1)
                        input_count <= input_count + 1'b1;
                end

                if (array_drain && ce && output_row != rows_q - 1'b1)
                    output_row <= output_row + 1'b1;

                // Done means the last result has actually been accepted.
                if (output_fire && m_axis_tlast)
                    done_o <= 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Simulation-only configuration and interface checks
    // -------------------------------------------------------------------------
    // synthesis translate_off
    initial begin
        assert (ROWS >= 1 && COLS >= 1)
        else
            $fatal(1, "Array dimensions must be positive");
        assert (MAX_K >= 1 && MAX_M >= 1)
        else
            $fatal(1, "Lengths must be positive");
        assert (DATAFLOW inside {OUTPUT_STATIONARY, WEIGHT_STATIONARY})
        else
            $fatal(1, "Bad dataflow");
        assert (NUMERIC_MODE inside {INTEGER_MODE, FP16_MODE})
        else
            $fatal(1, "Bad numeric mode");
        assert (INT_W inside {2, 4, 8})
        else
            $fatal(1, "INT_W must be 2,4,8");
        assert (INT_ACC_W >= INT_MIN_ACC_W)
        else
            $fatal(1, "Integer accumulator too narrow");
        assert (FP_RESULT_W inside {16, 32})
        else
            $fatal(1, "FP_RESULT_W must be 16 or 32");
        assert (OUT_FIFO_DEPTH >= 2 && EXTRA_PRODUCT_REGS >= 0)
        else
            $fatal(1, "Bad pipeline/FIFO config");
    end
    assert property (
        @(posedge clk) disable iff (!rst_n)
        m_axis_tvalid && !m_axis_tready |=>
        m_axis_tvalid && $stable({m_axis_tdata, m_axis_tuser, m_axis_tlast})
    );

    assert property (
        @(posedge clk) disable iff (!rst_n)
        start_i |-> !busy_o
    );

    // A completion pulse acknowledges an actual final output transfer.
    assert property (
        @(posedge clk) disable iff (!rst_n)
        done_o |-> !busy_o && $past(output_fire && m_axis_tlast && !start_i)
    );

    assert property (
        @(posedge clk) disable iff (!rst_n)
        output_fire && m_axis_tlast && !start_i |=> done_o && !busy_o
    );

    // Backpressure cannot advance a retained OS row.
    assert property (
        @(posedge clk) disable iff (!rst_n)
        array_drain && !ce && !start_i && !(output_fire && m_axis_tlast) |=>
        array_drain && $stable(output_row)
    );
    // synthesis translate_on
endmodule
