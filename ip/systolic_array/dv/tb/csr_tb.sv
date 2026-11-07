`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Module Name: csr_tb
// Project Name: Systolic Array IP
//
// Description:
// Exercises concurrent AXI4-Lite read/write responses and independent AW/W
// capture. Checks prolonged response stalls and reset of partial transactions.
// Uses the public register map as its golden model, without DUT state access.
//
// Revision:
// Revision 0.03 - Directed coverage for the explicit AXI response FSMs.
// Additional Comments:
// Run with python3 tools/run_csr.py. Configuration comes from rtl/sa_pkg.sv.
//////////////////////////////////////////////////////////////////////////////////

module csr_tb;
    import sa_pkg::*;

    // ====
    // DUT
    // ====
    // Clock, reset, and AXI channel signals
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [CSR_ADDR_W-1:0] s_axi_awaddr = '0;
    logic [2:0] s_axi_awprot = '0;
    logic s_axi_awvalid = 1'b0;
    logic s_axi_awready;
    logic [31:0] s_axi_wdata = '0;
    logic [3:0] s_axi_wstrb = 4'hf;
    logic s_axi_wvalid = 1'b0;
    logic s_axi_wready;
    logic [1:0] s_axi_bresp;
    logic s_axi_bvalid;
    logic s_axi_bready = 1'b0;
    logic [CSR_ADDR_W-1:0] s_axi_araddr = '0;
    logic [2:0] s_axi_arprot = '0;
    logic s_axi_arvalid = 1'b0;
    logic s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0] s_axi_rresp;
    logic s_axi_rvalid;
    logic s_axi_rready = 1'b0;

    // Engine command/status connections
    logic start_o;
    logic reuse_weights_o;
    logic [31:0] length_o;
    logic [31:0] rows_o;
    logic [31:0] cols_o;
    logic irq_o;

    localparam CLK_PERIOD = 10;
    always #(CLK_PERIOD / 2) clk = ~clk;

    csr DUT (
        .clk              (clk),
        .rst_n            (rst_n),
        .s_axi_awaddr     (s_axi_awaddr),
        .s_axi_awprot     (s_axi_awprot),
        .s_axi_awvalid    (s_axi_awvalid),
        .s_axi_awready    (s_axi_awready),
        .s_axi_wdata      (s_axi_wdata),
        .s_axi_wstrb      (s_axi_wstrb),
        .s_axi_wvalid     (s_axi_wvalid),
        .s_axi_wready     (s_axi_wready),
        .s_axi_bresp      (s_axi_bresp),
        .s_axi_bvalid     (s_axi_bvalid),
        .s_axi_bready     (s_axi_bready),
        .s_axi_araddr     (s_axi_araddr),
        .s_axi_arprot     (s_axi_arprot),
        .s_axi_arvalid    (s_axi_arvalid),
        .s_axi_arready    (s_axi_arready),
        .s_axi_rdata      (s_axi_rdata),
        .s_axi_rresp      (s_axi_rresp),
        .s_axi_rvalid     (s_axi_rvalid),
        .s_axi_rready     (s_axi_rready),
        .busy_i           (1'b0),
        .done_i           (1'b0),
        .error_i          (1'b0),
        .shadow_ready_i   (1'b0),
        .active_weights_i (1'b0),
        .cycles_i         (32'b0),
        .input_beats_i    (32'b0),
        .output_beats_i   (32'b0),
        .start_o          (start_o),
        .reuse_weights_o  (reuse_weights_o),
        .length_o         (length_o),
        .rows_o           (rows_o),
        .cols_o           (cols_o),
        .irq_o            (irq_o)
    );

    // =============
    // Golden Model
    // =============
    // LENGTH is software writable; ROWS is a fixed capability register.
    // A pending read must retain its captured value until it is accepted.
    integer pass_count = 0;
    integer fail_count = 0;

    // =====
    // Tasks
    // =====
    task automatic check(input logic condition, input string description);
        if (condition === 1'b1)
            pass_count++;
        else begin
            fail_count++;
            $error("FAIL: %s", description);
        end
    endtask

    task automatic wait_cycles(input integer count);
        repeat (count) @(posedge clk);
        #1;
    endtask

    task automatic reset_dut;
        @(negedge clk);
        rst_n = 1'b0;
        s_axi_awvalid = 1'b0;
        s_axi_wvalid = 1'b0;
        s_axi_arvalid = 1'b0;
        s_axi_bready = 1'b0;
        s_axi_rready = 1'b0;
        wait_cycles(3);
        check(!s_axi_bvalid && !s_axi_rvalid, "Reset clears both responses");
        check(length_o == 1 && rows_o == ROWS && cols_o == COLS,
              "Reset restores configuration defaults");
        @(negedge clk);
        rst_n = 1'b1;
    endtask

    task automatic send_aw(input logic [CSR_ADDR_W-1:0] address);
        @(negedge clk);
        s_axi_awaddr = address;
        s_axi_awvalid = 1'b1;
        do @(posedge clk); while (!s_axi_awready);
        @(negedge clk);
        s_axi_awvalid = 1'b0;
    endtask

    task automatic send_w(input logic [31:0] data);
        @(negedge clk);
        s_axi_wdata = data;
        s_axi_wvalid = 1'b1;
        do @(posedge clk); while (!s_axi_wready);
        @(negedge clk);
        s_axi_wvalid = 1'b0;
    endtask

    task automatic send_ar(input logic [CSR_ADDR_W-1:0] address);
        @(negedge clk);
        s_axi_araddr = address;
        s_axi_arvalid = 1'b1;
        do @(posedge clk); while (!s_axi_arready);
        @(negedge clk);
        s_axi_arvalid = 1'b0;
    endtask

    task automatic accept_b;
        @(negedge clk);
        s_axi_bready = 1'b1;
        do @(posedge clk); while (!s_axi_bvalid);
        check(s_axi_bresp == 2'b00, "Write response is OKAY");
        @(negedge clk);
        s_axi_bready = 1'b0;
    endtask

    task automatic accept_r(input logic [31:0] expected);
        @(negedge clk);
        s_axi_rready = 1'b1;
        do @(posedge clk); while (!s_axi_rvalid);
        check(s_axi_rresp == 2'b00 && s_axi_rdata == expected,
              $sformatf("Read response: expected %h, received %h", expected, s_axi_rdata));
        @(negedge clk);
        s_axi_rready = 1'b0;
    endtask

    // ============
    // Test timeout
    // ============
    initial begin
        #(CLK_PERIOD * 10000);
        $fatal(1, "CSR TEST FAILED: timeout");
    end

    // =========
    // Main test
    // =========
    initial begin
        // Reset abandons either half of an incomplete write.
        reset_dut();
        send_aw('h008);
        wait_cycles(5);
        check(!s_axi_bvalid && !s_axi_awready && s_axi_wready,
              "AW alone waits for W without generating a response");
        reset_dut();
        send_w(32'd55);
        wait_cycles(5);
        check(!s_axi_bvalid && s_axi_awready && !s_axi_wready,
              "W alone waits for AW without generating a response");
        reset_dut();

        // Both response channels may remain valid independently under stalls.
        fork
            send_aw('h008);
            send_w(32'd25);
            send_ar('h01c);
        join
        wait_cycles(2);
        repeat (7) begin
            wait_cycles(1);
            check(s_axi_bvalid && s_axi_rvalid, "Both responses remain pending");
            check(s_axi_bresp == 0 && s_axi_rresp == 0 && s_axi_rdata == ROWS,
                  "Stalled response payloads are stable");
            check(!s_axi_awready && !s_axi_wready && !s_axi_arready,
                  "Outstanding responses block new requests on their channels");
        end

        // Completing B permits another write while the old read stays pending.
        accept_b();
        fork
            send_aw('h008);
            send_w(32'd40);
        join
        accept_b();
        check(s_axi_rvalid && s_axi_rdata == ROWS, "Write progress preserves stalled read");
        accept_r(32'(ROWS));
        send_ar('h008);
        accept_r(32'd40);

        // Completing R permits another read while the old write stays pending.
        fork
            send_aw('h008);
            send_w(32'd52);
            send_ar('h01c);
        join
        accept_r(32'(ROWS));
        send_ar('h008);
        accept_r(32'd52);
        check(s_axi_bvalid && !s_axi_awready && !s_axi_wready,
              "Read progress preserves stalled write response");
        accept_b();

        // Reset also flushes complete but unaccepted read and write responses.
        fork
            send_aw('h008);
            send_w(32'd99);
            send_ar('h01c);
        join
        wait_cycles(3);
        check(s_axi_bvalid && s_axi_rvalid, "Both responses are pending before reset");
        reset_dut();
        send_ar('h008);
        accept_r(32'd1);

        // Complete legal writes with a long gap in either channel ordering.
        send_aw('h008);
        wait_cycles(5);
        send_w(32'd200);
        accept_b();
        send_ar('h008);
        accept_r(32'd200);
        send_w(32'd201);
        wait_cycles(5);
        send_aw('h008);
        accept_b();
        send_ar('h008);
        accept_r(32'd201);

        if (fail_count != 0 || pass_count == 0)
            $fatal(1, "CSR TEST FAILED: Passed=%0d Failed=%0d", pass_count, fail_count);
        $display("CSR TEST PASSED: Passed=%0d Failed=%0d", pass_count, fail_count);
        $finish;
    end
endmodule
