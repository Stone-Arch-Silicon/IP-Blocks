`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Module Name: delay
// Project Name: Systolic Array IP
//
// Description:
// Delays payload and validity by DEPTH enabled cycles, or wires them
// through when DEPTH is zero. Registered paths reset/clear validity only.
// Used for operand skew, tag alignment, and optional product latency.
//
// Revision:
// Revision 0.01 - Initial parameterized implementation.
// Revision 0.02 - Readability, section comments, and module documentation.
// Revision 0.03 - Short module names and explicit controller FSMs.
// Revision 0.04 - Keep zero-depth declarations legal for Design Compiler.
// Additional Comments:
// Configure the IP in rtl/sa_pkg.sv and re-elaborate after edits.
// Port names and cycle timing are retained; module names are shortened.
//////////////////////////////////////////////////////////////////////////////////

module delay #(
    parameter int W = 1,
    parameter int DEPTH = 1
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         clear,
    input  logic         ce,
    input  logic         valid_i,
    input  logic [W-1:0] data_i,
    output logic         valid_o,
    output logic [W-1:0] data_o
);

    // Some elaborators validate array bounds before removing a generate branch.
    // Clamp declarations only; DEPTH=0 still selects the combinational bypass.
    localparam int STORAGE_DEPTH = (DEPTH > 0) ? DEPTH : 1;

    // -------------------------------------------------------------------------
    // Elaboration-time bypass or enabled register chain
    // Only validity is reset. Payload is ignored whenever validity is low.
    // -------------------------------------------------------------------------
    if (DEPTH == 0) begin : g_wire
        assign valid_o = valid_i;
        assign data_o  = data_i;
    end else begin : g_regs
        logic [STORAGE_DEPTH-1:0] v;
        logic [W-1:0]             d [0:STORAGE_DEPTH-1];
        always_ff @(posedge clk) begin
            if (!rst_n || clear)
                v <= '0;
            else if (ce) begin
                v[0] <= valid_i;
                for (int i = 1; i < DEPTH; i++)
                    v[i] <= v[i-1];
            end
            if (ce) begin
                d[0] <= data_i;
                for (int i = 1; i < DEPTH; i++)
                    d[i] <= d[i-1];
            end
        end
        assign valid_o = v[STORAGE_DEPTH-1];
        assign data_o  = d[STORAGE_DEPTH-1];
    end
endmodule
