`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Module Name: fifo
// Project Name: Systolic Array IP
//
// Description:
// Buffers output beats with registered occupancy and wraparound
// pointers for any positive depth. Input ready depends only on stored
// occupancy, isolating array enable from downstream ready timing.
//
// Revision:
// Revision 0.01 - Initial parameterized implementation.
// Revision 0.02 - Readability, section comments, and module documentation.
// Revision 0.03 - Short module names and explicit controller FSMs.
// Additional Comments:
// Configure the IP in rtl/sa_pkg.sv and re-elaborate after edits.
// Port names and cycle timing are retained; module names are shortened.
//////////////////////////////////////////////////////////////////////////////////

module fifo #(
    parameter int W = 32,
    parameter int DEPTH = 4,
    parameter int PW = (DEPTH > 1 ? $clog2(DEPTH) : 1),
    parameter int CW = $clog2(DEPTH + 1)
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         s_valid,
    output logic         s_ready,
    input  logic [W-1:0] s_data,
    output logic         m_valid,
    input  logic         m_ready,
    output logic [W-1:0] m_data
);

    // -------------------------------------------------------------------------
    // Storage, pointers, and registered occupancy
    // -------------------------------------------------------------------------
    logic [W-1:0]  mem   [DEPTH];
    logic [PW-1:0] wr;
    logic [PW-1:0] rd;
    logic [CW-1:0] count;
    logic          push;
    logic          pop;

    // -------------------------------------------------------------------------
    // Ready/valid interface and transfer detection
    // A full FIFO stalls its input even if a pop occurs on this same edge.
    // This removes the combinational path from m_ready to the array enable.
    // -------------------------------------------------------------------------
    assign s_ready = count < CW'(DEPTH);
    assign m_valid = count != 0;
    assign m_data  = mem[rd];
    assign push    = s_valid && s_ready;
    assign pop     = m_valid && m_ready;

    // -------------------------------------------------------------------------
    // Occupancy update and independent read/write pointer advance
    // Explicit wrap supports depths that are not powers of two.
    // The memory payload has no reset; occupancy determines valid entries.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr    <= '0;
            rd    <= '0;
            count <= '0;
        end else begin
            case ({push, pop})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: ;
            endcase
            if (push)
                wr <= (wr == PW'(DEPTH - 1)) ? '0 : wr + 1'b1;
            if (pop)
                rd <= (rd == PW'(DEPTH - 1)) ? '0 : rd + 1'b1;
        end
        if (push)
            mem[wr] <= s_data;
    end
endmodule
