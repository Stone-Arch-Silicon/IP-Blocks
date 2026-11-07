`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Module Name: sa_top
// Project Name: Systolic Array IP
//
// Description:
// Integrates the AXI4-Lite control registers and streaming tile engine.
// Exposes operand, weight, and result streams plus a completion/error
// interrupt. All interface widths are derived from sa_pkg.
//
// Revision:
// Revision 0.01 - Initial parameterized implementation.
// Revision 0.02 - Readability, section comments, and module documentation.
// Revision 0.03 - Short module names and explicit controller FSMs.
// Additional Comments:
// Configure the IP in rtl/sa_pkg.sv and re-elaborate after edits.
// Port names and cycle timing are retained; module names are shortened.
//////////////////////////////////////////////////////////////////////////////////

module sa_top
    import sa_pkg::*;
(

    // -------------------------------------------------------------------------
    // Clock and synchronous active-low reset
    // -------------------------------------------------------------------------
    input  logic clk,
    input  logic rst_n,

    // -------------------------------------------------------------------------
    // AXI4-Lite control/status interface
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
    // Operand and weight input streams
    // -------------------------------------------------------------------------
    input  logic [INPUT_W-1:0]  s_axis_tdata,
    input  logic                s_axis_tvalid,
    input  logic                s_axis_tlast,
    output logic                s_axis_tready,
    input  logic [WEIGHT_W-1:0] s_weight_tdata,
    input  logic                s_weight_tvalid,
    input  logic                s_weight_tlast,
    output logic                s_weight_tready,

    // -------------------------------------------------------------------------
    // Result stream and interrupt
    // -------------------------------------------------------------------------
    output logic [OUTPUT_W-1:0] m_axis_tdata,
    output logic [USER_W-1:0]   m_axis_tuser,
    output logic                m_axis_tvalid,
    output logic                m_axis_tlast,
    input  logic                m_axis_tready,
    output logic                irq
);

    // -------------------------------------------------------------------------
    // Control and status connections between the CSR block and engine
    // -------------------------------------------------------------------------
    logic        start;
    logic        reuse_weights;
    logic        busy;
    logic        done;
    logic        error;
    logic        shadow_ready;
    logic        active_weights;
    logic [31:0] length;
    logic [31:0] rows;
    logic [31:0] cols;
    logic [31:0] cycles;
    logic [31:0] input_beats;
    logic [31:0] output_beats;

    // -------------------------------------------------------------------------
    // Control/status register block
    // -------------------------------------------------------------------------
    csr u_csr (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awprot    (s_axi_awprot),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),
        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wready    (s_axi_wready),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arprot    (s_axi_arprot),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arready   (s_axi_arready),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready),
        .busy_i          (busy),
        .done_i          (done),
        .error_i         (error),
        .shadow_ready_i  (shadow_ready),
        .active_weights_i(active_weights),
        .cycles_i        (cycles),
        .input_beats_i   (input_beats),
        .output_beats_i  (output_beats),
        .start_o         (start),
        .reuse_weights_o (reuse_weights),
        .length_o        (length),
        .rows_o          (rows),
        .cols_o          (cols),
        .irq_o           (irq)
    );

    // -------------------------------------------------------------------------
    // Tile execution engine and streaming datapath
    // -------------------------------------------------------------------------
    engine u_engine (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_i         (start),
        .reuse_weights_i (reuse_weights),
        .length_i        (length),
        .rows_i          (rows),
        .cols_i          (cols),
        .busy_o          (busy),
        .done_o          (done),
        .error_o         (error),
        .shadow_ready_o  (shadow_ready),
        .active_weights_o(active_weights),
        .cycles_o        (cycles),
        .input_beats_o   (input_beats),
        .output_beats_o  (output_beats),
        .s_axis_tdata    (s_axis_tdata),
        .s_axis_tvalid   (s_axis_tvalid),
        .s_axis_tlast    (s_axis_tlast),
        .s_axis_tready   (s_axis_tready),
        .s_weight_tdata  (s_weight_tdata),
        .s_weight_tvalid (s_weight_tvalid),
        .s_weight_tlast  (s_weight_tlast),
        .s_weight_tready (s_weight_tready),
        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tuser    (m_axis_tuser),
        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tlast    (m_axis_tlast),
        .m_axis_tready   (m_axis_tready)
    );
endmodule
