`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Module Name: csr
// Project Name: Systolic Array IP
//
// Description:
// Implements the 32-bit AXI4-Lite control/status register interface.
// Buffers write address and data independently, validates start commands,
// and holds responses stable until accepted. Supports byte strobes,
// sticky completion/error status, capabilities, counters, and interrupts.
// Uses separate explicit state/next-state FSMs for write and read responses.
//
// Revision:
// Revision 0.01 - Initial parameterized implementation.
// Revision 0.02 - Readability, section comments, and module documentation.
// Revision 0.03 - Short module names and explicit controller FSMs.
// Additional Comments:
// Configure the IP in rtl/sa_pkg.sv and re-elaborate after edits.
// Port names and cycle timing are retained; module names are shortened.
//////////////////////////////////////////////////////////////////////////////////

module csr
    import sa_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    // -------------------------------------------------------------------------
    // AXI4-Lite write and read channels
    // -------------------------------------------------------------------------
    input  logic [CSR_ADDR_W-1:0] s_axi_awaddr,
    input  logic [2:0]            s_axi_awprot,
    input  logic                  s_axi_awvalid,
    output logic                  s_axi_awready,
    input  logic [31:0]           s_axi_wdata,
    input  logic [3:0]            s_axi_wstrb,
    input  logic                  s_axi_wvalid,
    output logic                  s_axi_wready,
    output logic [1:0]            s_axi_bresp,
    output logic                  s_axi_bvalid,
    input  logic                  s_axi_bready,
    input  logic [CSR_ADDR_W-1:0] s_axi_araddr,
    input  logic [2:0]            s_axi_arprot,
    input  logic                  s_axi_arvalid,
    output logic                  s_axi_arready,
    output logic [31:0]           s_axi_rdata,
    output logic [1:0]            s_axi_rresp,
    output logic                  s_axi_rvalid,
    input  logic                  s_axi_rready,

    // -------------------------------------------------------------------------
    // Engine status, counters, and command outputs
    // -------------------------------------------------------------------------
    input  logic        busy_i,
    input  logic        done_i,
    input  logic        error_i,
    input  logic        shadow_ready_i,
    input  logic        active_weights_i,
    input  logic [31:0] cycles_i,
    input  logic [31:0] input_beats_i,
    input  logic [31:0] output_beats_i,
    output logic        start_o,
    output logic        reuse_weights_o,
    output logic [31:0] length_o,
    output logic [31:0] rows_o,
    output logic [31:0] cols_o,
    output logic        irq_o
);

    // -------------------------------------------------------------------------
    // AXI response FSM states and registers
    // Address and data capture remain independent within WRITE_COLLECT.
    // -------------------------------------------------------------------------
    typedef enum logic {
        WRITE_COLLECT  = 1'b0,
        WRITE_RESPONSE = 1'b1
    } write_state_t;

    typedef enum logic {
        READ_IDLE     = 1'b0,
        READ_RESPONSE = 1'b1
    } read_state_t;

    write_state_t write_state;
    write_state_t next_write_state;
    read_state_t  read_state;
    read_state_t  next_read_state;

    // -------------------------------------------------------------------------
    // Independent write-channel holding registers and sticky status
    // -------------------------------------------------------------------------
    logic                  aw_hold;
    logic                  w_hold;
    logic [CSR_ADDR_W-1:0] awaddr_q;
    logic [31:0]           wdata_q;
    logic [3:0]            wstrb_q;
    logic                  done_sticky;
    logic                  error_sticky;
    logic                  irq_enable;
    logic                  command_ok;
    logic [31:0]           rd_data;
    logic [1:0]            rd_resp;
    logic                  unused_prot;
    logic                  write_commit;
    logic                  read_accept;

    // -------------------------------------------------------------------------
    // Channel readiness, interrupt generation, and command validation
    // AW and W may arrive in either order. A new write is blocked while a
    // response remains outstanding. Protection attributes do not alter access.
    // -------------------------------------------------------------------------
    assign unused_prot = ^{s_axi_awprot, s_axi_arprot};
    assign write_commit = (write_state == WRITE_COLLECT) && aw_hold && w_hold;
    assign read_accept = s_axi_arvalid && s_axi_arready;
    assign irq_o = irq_enable && (done_sticky || error_sticky);
    assign command_ok = !busy_i && !start_o &&
                        length_o != 0 && rows_o != 0 && cols_o != 0 &&
                        rows_o <= ROWS && cols_o <= COLS &&
                        ((DATAFLOW == OUTPUT_STATIONARY && length_o <= MAX_K) ||
                         (DATAFLOW == WEIGHT_STATIONARY && length_o <= MAX_M &&
                          (wdata_q[1] ? active_weights_i : shadow_ready_i)));

    // -------------------------------------------------------------------------
    // Write-response FSM state register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n)
            write_state <= WRITE_COLLECT;
        else
            write_state <= next_write_state;
    end

    // -------------------------------------------------------------------------
    // Write-response FSM combinational next-state logic
    // Commit only after both AW and W are buffered. Retain the response
    // until BREADY; the next transaction begins in the following cycle.
    // -------------------------------------------------------------------------
    always_comb begin
        next_write_state = write_state;

        case (write_state)
            WRITE_COLLECT: begin
                if (write_commit)
                    next_write_state = WRITE_RESPONSE;
            end

            WRITE_RESPONSE: begin
                if (s_axi_bready)
                    next_write_state = WRITE_COLLECT;
            end

            default: begin
                next_write_state = WRITE_COLLECT;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Read-response FSM state register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n)
            read_state <= READ_IDLE;
        else
            read_state <= next_read_state;
    end

    // -------------------------------------------------------------------------
    // Read-response FSM combinational next-state logic
    // The read payload is captured on AR acceptance and held through RREADY.
    // -------------------------------------------------------------------------
    always_comb begin
        next_read_state = read_state;

        case (read_state)
            READ_IDLE: begin
                if (read_accept)
                    next_read_state = READ_RESPONSE;
            end

            READ_RESPONSE: begin
                if (s_axi_rready)
                    next_read_state = READ_IDLE;
            end

            default: begin
                next_read_state = READ_IDLE;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Write-response FSM combinational output logic
    // AWREADY and WREADY are independent; neither requires the other VALID.
    // -------------------------------------------------------------------------
    always_comb begin
        s_axi_awready = 1'b0;
        s_axi_wready  = 1'b0;
        s_axi_bvalid  = 1'b0;

        case (write_state)
            WRITE_COLLECT: begin
                s_axi_awready = !aw_hold;
                s_axi_wready  = !w_hold;
            end

            WRITE_RESPONSE: begin
                s_axi_bvalid = 1'b1;
            end

            default: begin
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Read-response FSM combinational output logic
    // -------------------------------------------------------------------------
    always_comb begin
        s_axi_arready = 1'b0;
        s_axi_rvalid  = 1'b0;

        case (read_state)
            READ_IDLE: begin
                s_axi_arready = 1'b1;
            end

            READ_RESPONSE: begin
                s_axi_rvalid = 1'b1;
            end

            default: begin
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Apply byte strobes to writable 32-bit configuration registers
    // -------------------------------------------------------------------------
    function automatic logic [31:0] byte_merge(
        input  logic [31:0] previous,
        input  logic [31:0] incoming,
        input  logic [3:0]  strobe
    );
        logic [31:0] value;
        value = previous;
        for (int i = 0; i < 4; i++)
            if (strobe[i])
                value[8*i+:8] = incoming[8*i+:8];
        return value;
    endfunction

    // -------------------------------------------------------------------------
    // Read address decode: control, configuration, capabilities, counters
    // Unmapped or unaligned addresses return SLVERR (2'b10).
    // -------------------------------------------------------------------------
    always_comb begin
        rd_data = '0;
        rd_resp = 2'b00;
        case (s_axi_araddr)
            'h000: rd_data = 0;
            'h004:
                rd_data = {27'b0, active_weights_i, shadow_ready_i, error_sticky, done_sticky, busy_i};
            'h008: rd_data = length_o;
            'h00c: rd_data = rows_o;
            'h010: rd_data = cols_o;
            'h014: rd_data = {31'b0, irq_enable};
            'h018: rd_data = 32'h53410000 | (32'(NUMERIC_MODE) << 8) | 32'(DATAFLOW);
            'h01c: rd_data = 32'(ROWS);
            'h020: rd_data = 32'(COLS);
            'h024: rd_data = 32'(OPERAND_W);
            'h028: rd_data = 32'(ACC_W);
            'h02c: rd_data = 32'(RESULT_W);
            'h030: rd_data = 32'(MAX_K);
            'h034: rd_data = 32'(MAX_M);
            'h038: rd_data = cycles_i;
            'h03c: rd_data = input_beats_i;
            'h040: rd_data = output_beats_i;
            default: rd_resp = 2'b10;
        endcase
    end

    // -------------------------------------------------------------------------
    // AXI payload registers, software configuration, and sticky status
    // FSM state is registered separately; this block owns data and events.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            aw_hold         <= 0;
            w_hold          <= 0;
            s_axi_bresp     <= 0;
            s_axi_rdata     <= 0;
            s_axi_rresp     <= 0;
            start_o         <= 0;
            reuse_weights_o <= 0;
            length_o        <= 1;
            rows_o          <= 32'(ROWS);
            cols_o          <= 32'(COLS);
            done_sticky     <= 0;
            error_sticky    <= 0;
            irq_enable      <= 0;
        end else begin
            start_o <= 0;

            // -------------------------------------------------------------------------
            // Capture write address and write data independently
            // -------------------------------------------------------------------------
            if (s_axi_awvalid && s_axi_awready) begin
                aw_hold  <= 1;
                awaddr_q <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_hold  <= 1;
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
            end

            // -------------------------------------------------------------------------
            // Commit one write only after both channels have been captured
            // -------------------------------------------------------------------------
            if (write_commit) begin
                aw_hold      <= 0;
                w_hold       <= 0;
                s_axi_bresp  <= 2'b00;
                case (awaddr_q)
                    'h000:
                        if (wstrb_q[0] && wdata_q[0]) begin
                            if (command_ok) begin
                                start_o         <= 1;
                                reuse_weights_o <= wdata_q[1];
                                done_sticky     <= 0;
                            end else begin
                                s_axi_bresp  <= 2'b10;
                                error_sticky <= 1;
                            end
                        end
                    'h004:
                        if (wstrb_q[0]) begin
                            if (wdata_q[1])
                                done_sticky <= 0;
                            if (wdata_q[2])
                                error_sticky <= 0;
                        end
                    'h008: length_o <= byte_merge(length_o, wdata_q, wstrb_q);
                    'h00c: rows_o <= byte_merge(rows_o, wdata_q, wstrb_q);
                    'h010: cols_o <= byte_merge(cols_o, wdata_q, wstrb_q);
                    'h014:
                        if (wstrb_q[0])
                            irq_enable <= wdata_q[0];
                    default: begin
                        s_axi_bresp  <= 2'b10;
                        error_sticky <= 1;
                    end
                endcase
            end

            // -------------------------------------------------------------------------
            // Hold read responses until accepted and capture the next address
            // -------------------------------------------------------------------------
            if (read_accept) begin
                s_axi_rdata  <= rd_data;
                s_axi_rresp  <= rd_resp;
            end

            // -------------------------------------------------------------------------
            // Set sticky status from hardware after software clear handling
            // -------------------------------------------------------------------------
            // Hardware events win over simultaneous software W1C.
            if (done_i)
                done_sticky <= 1;
            if (error_i)
                error_sticky <= 1;
        end
    end

    // -------------------------------------------------------------------------
    // Simulation-only AXI response stability checks
    // -------------------------------------------------------------------------
    // synthesis translate_off
    assert property (
        @(posedge clk) disable iff (!rst_n)
        s_axi_bvalid && !s_axi_bready |=>
        s_axi_bvalid && $stable(s_axi_bresp)
    );

    assert property (
        @(posedge clk) disable iff (!rst_n)
        s_axi_rvalid && !s_axi_rready |=>
        s_axi_rvalid && $stable({s_axi_rdata, s_axi_rresp})
    );
    // synthesis translate_on
endmodule
