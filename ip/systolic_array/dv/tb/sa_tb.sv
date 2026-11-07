`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Stone Arch Silicon
// Engineer: Paulo Dietrich
//
// Module Name: sa_tb
// Project Name: Systolic Array IP
//
// Description:
// Checks the complete IP against independently generated matrix vectors.
// Exercises AXI channel ordering, byte strobes, stream stalls, weight
// bank reuse, framing errors, interrupts, and reset during operation.
// Retains the DUT / Golden Model / Tasks / Main test template structure.
//
// Revision:
// Revision 0.01 - Initial parameterized implementation.
// Revision 0.02 - Readability, section comments, and module documentation.
// Revision 0.03 - Short module names and explicit controller FSMs.
// Additional Comments:
// Configure the IP in rtl/sa_pkg.sv and re-elaborate after edits.
// Port names and cycle timing are retained; module names are shortened.
//////////////////////////////////////////////////////////////////////////////////

module sa_tb;
    import sa_pkg::*;

    // ====
    // DUT
    // ====
    // --------
    // Signals
    // --------
    // Clock and reset
    logic clk = 0;
    logic rst_n = 0;

    // Inputs
    logic [CSR_ADDR_W-1:0] s_axi_awaddr = 0;
    logic [CSR_ADDR_W-1:0] s_axi_araddr = 0;
    logic [2:0]            s_axi_awprot = 0;
    logic [2:0]            s_axi_arprot = 0;
    logic                  s_axi_awvalid = 0;
    logic                  s_axi_wvalid = 0;
    logic                  s_axi_bready = 0;
    logic                  s_axi_arvalid = 0;
    logic                  s_axi_rready = 0;
    logic [31:0]           s_axi_wdata = 0;
    logic [3:0]            s_axi_wstrb = 0;
    logic [INPUT_W-1:0]    s_axis_tdata = 0;
    logic                  s_axis_tvalid = 0;
    logic                  s_axis_tlast = 0;
    logic [WEIGHT_W-1:0]   s_weight_tdata = 0;
    logic                  s_weight_tvalid = 0;
    logic                  s_weight_tlast = 0;
    logic                  m_axis_tready = 0;

    // Outputs
    logic                s_axi_awready;
    logic                s_axi_wready;
    logic                s_axi_bvalid;
    logic                s_axi_arready;
    logic                s_axi_rvalid;
    logic [1:0]          s_axi_bresp;
    logic [1:0]          s_axi_rresp;
    logic [31:0]         s_axi_rdata;
    logic                s_axis_tready;
    logic                s_weight_tready;
    logic [OUTPUT_W-1:0] m_axis_tdata;
    logic [USER_W-1:0]   m_axis_tuser;
    logic                m_axis_tvalid;
    logic                m_axis_tlast;
    logic                irq;

    // Debugging
    integer case_number = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    integer result_count = 0;
    integer seed = 32'h53415349;
    integer simulation_cycle = 0;
    integer first_input_cycle;
    integer last_output_cycle;
    always @(posedge clk)
        simulation_cycle <= simulation_cycle + 1;

    // -----------
    // Parameters
    // -----------
    localparam CLK_PERIOD = 10;
    localparam MAX_TEST_WORDS = imax(imax(MAX_K, MAX_M), ROWS) + 1;
    localparam TIMEOUT_CYCLES = 2000 + 20 * (MAX_K + MAX_M + ROWS * WS_HOP + COLS);

    // ------------
    // Start clock
    // ------------
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ----------------
    // Instantiate DUT
    // ----------------
    sa_top DUT (.*);

    // =============
    // Golden Model
    // =============
    // tools/reference.py uses exact Python Fraction arithmetic and a separate
    // rational quotient/remainder quantizer. The testbench never calls DUT math.
    logic [INPUT_W-1:0]  input_words    [MAX_TEST_WORDS];
    logic [WEIGHT_W-1:0] weight_words   [ROWS];
    logic [WEIGHT_W-1:0] shadow_words   [ROWS];
    logic [OUTPUT_W-1:0] expected_words [MAX_TEST_WORDS];
    logic [USER_W-1:0]   expected_flags [MAX_TEST_WORDS];
    integer              job_length;
    integer              active_rows;
    integer              active_cols;
    integer              expected_rows;
    integer              load_mode;
    integer              preload_shadow;
    integer              bad_last;
    integer              random_stalls;

    // ======
    // Tasks
    // ======
    // ------
    // Reset
    // ------
    task automatic reset_dut;
        @(negedge clk);
        rst_n           = 0;
        s_axi_awvalid   = 0;
        s_axi_wvalid    = 0;
        s_axi_bready    = 0;
        s_axi_arvalid   = 0;
        s_axi_rready    = 0;
        s_axis_tvalid   = 0;
        s_weight_tvalid = 0;
        m_axis_tready   = 0;
        repeat (5)
            @(negedge clk);
        rst_n = 1;
        #1;
    endtask

    // --------
    // Checker
    // --------
    task automatic check(
        input  bit condition,
        input string label_text
    );
        if (!condition) begin
            $display("FAIL: case=%0d %s", case_number, label_text);
            fail_count++;
            if (fail_count > 20)
                $fatal(1, "Too many failures");
        end else
            pass_count++;
    endtask

    // ------------------
    // Wait clock cycles
    // ------------------
    task automatic wait_cycles(
        input  integer cycles
    );
        repeat (cycles)
            @(negedge clk);
        #1;
    endtask

    // ----------------------
    // AXI-Lite bus operations
    // ----------------------
    task automatic axi_write(
        input  integer      address,
        input  logic [31:0] data,
        input  logic [3:0]  strobe = 4'hf,
        input  logic [1:0]  response = 2'b00
    );
        integer aw_delay;
        integer w_delay;
        aw_delay = $urandom_range(0, 4);
        w_delay  = $urandom_range(0, 4);
        fork
            begin
                repeat (aw_delay)
                    @(negedge clk);
                @(negedge clk);
                s_axi_awaddr  = CSR_ADDR_W'(address);
                s_axi_awvalid = 1;
                do @(posedge clk); while (!s_axi_awready);
                @(negedge clk);
                s_axi_awvalid = 0;
            end
            begin
                repeat (w_delay)
                    @(negedge clk);
                @(negedge clk);
                s_axi_wdata  = data;
                s_axi_wstrb  = strobe;
                s_axi_wvalid = 1;
                do @(posedge clk); while (!s_axi_wready);
                @(negedge clk);
                s_axi_wvalid = 0;
            end
        join
        repeat ($urandom_range(0, 4))
            @(negedge clk);
        @(negedge clk);
        s_axi_bready = 1;
        do @(posedge clk); while (!s_axi_bvalid);
        check(s_axi_bresp === response, $sformatf(
              "BRESP addr=%h got=%b expected=%b", address, s_axi_bresp, response));
        @(negedge clk);
        s_axi_bready = 0;
    endtask

    task automatic axi_read(

        input  integer address,

        output logic [31:0] value,

        input  logic [1:0] response = 2'b00

    );
        @(negedge clk);
        s_axi_araddr  = CSR_ADDR_W'(address);
        s_axi_arvalid = 1;
        do @(posedge clk); while (!s_axi_arready);
        @(negedge clk);
        s_axi_arvalid = 0;
        repeat ($urandom_range(0, 4))
            @(negedge clk);
        @(negedge clk);
        s_axi_rready = 1;
        do @(posedge clk); while (!s_axi_rvalid);
        value = s_axi_rdata;
        check(s_axi_rresp === response, $sformatf("RRESP addr=%h", address));
        @(negedge clk);
        s_axi_rready = 0;
    endtask

    // -----------------
    // Apply input data
    // -----------------
    task automatic apply_data;
        for (int i = 0; i < job_length; i++) begin
            if (random_stalls != 0)
                repeat ($urandom_range(
                    0, 3
                )) begin
                    @(negedge clk);
                    s_axis_tvalid = 0;
                end
            @(negedge clk);
            s_axis_tdata = input_words[i];
            s_axis_tlast = (bad_last != 0) ?
                ((job_length != 1) && (i == 0)) : (i == job_length - 1);
            s_axis_tvalid = 1;
            do @(posedge clk); while (!s_axis_tready);
            if (i == 0)
                first_input_cycle = simulation_cycle;
        end
        @(negedge clk);
        s_axis_tvalid = 0;
    endtask

    task automatic load_weights(

        input  bit use_shadow = 0

    );
        for (int r = 0; r < ROWS; r++) begin
            repeat ($urandom_range(
                0, 2
            )) begin
                @(negedge clk);
                s_weight_tvalid = 0;
            end
            @(negedge clk);
            s_weight_tdata  = use_shadow ? shadow_words[r] : weight_words[r];
            s_weight_tlast  = r == ROWS - 1;
            s_weight_tvalid = 1;
            do @(posedge clk); while (!s_weight_tready);
        end
        @(negedge clk);
        s_weight_tvalid = 0;
    endtask

    // -------------------
    // Start command pulse
    // -------------------
    task automatic press_start;
        axi_write('h000, (DATAFLOW == WEIGHT_STATIONARY && load_mode == 1) ? 3 : 1);
    endtask

    // --------------------
    // Wait for completion
    // --------------------
    task automatic wait_for_done;
        integer cycles;
        integer received;
        cycles   = 0;
        received = 0;
        while (received < expected_rows && cycles < TIMEOUT_CYCLES) begin
            @(negedge clk);
            // Long stalls exercise FIFO full and a frozen wavefront.
            m_axis_tready = (random_stalls == 0) ||
                ((cycles % 53 >= 17) && ($urandom_range(0, 3) != 0));
            @(posedge clk);
            if (m_axis_tvalid && m_axis_tready) begin
                check(m_axis_tdata === expected_words[received], $sformatf(
                      "row=%0d actual=%h expected=%h",
                      received,
                      m_axis_tdata,
                      expected_words[received]
                      ));
                check(m_axis_tuser === expected_flags[received], $sformatf(
                      "flags row=%0d actual=%h expected=%h",
                      received,
                      m_axis_tuser,
                      expected_flags[received]
                      ));
                check(m_axis_tlast === (received == expected_rows - 1), "result TLAST");
                result_count += COLS;
                last_output_cycle = simulation_cycle;
                received++;
            end
            cycles++;
        end
        check(received == expected_rows, "completion before timeout");
        if (received != expected_rows)
            $fatal(1, "Timeout waiting for output");
        @(negedge clk);
        m_axis_tready = 0;
    endtask

    // -----------------------
    // Run complete test case
    // -----------------------
    task automatic run_test;
        logic [31:0] value;
        axi_write('h004, 6);  // W1C previous done/error.
        axi_write('h008, 32'(job_length));
        axi_write('h00c, 32'(active_rows));
        axi_write('h010, 32'(active_cols));
        if (DATAFLOW == WEIGHT_STATIONARY && load_mode == 0)
            load_weights();
        press_start();
        fork
            apply_data();
            wait_for_done();
            begin
                if (DATAFLOW == WEIGHT_STATIONARY && (preload_shadow != 0))
                    load_weights(1);
            end
        join
        wait_cycles(3);
        axi_read('h004, value);
        check(!value[0] && value[1], "idle with sticky completion");
        check(value[2] == (bad_last != 0), "framing error status");
        check(irq, "completion interrupt");
        axi_read('h03c, value);
        check(value == job_length, "input beat count");
        axi_read('h040, value);
        check(value == expected_rows, "output beat count");
        if ((random_stalls == 0)) begin
            axi_read('h038, value);
            $display(
                "PERF case=%0d length=%0d rows=%0d cols=%0d busy_cycles=%0d first_input_to_last_output=%0d",
                case_number, job_length, active_rows, active_cols, value,
                last_output_cycle - first_input_cycle);
        end
    endtask

    // Check capability reads, invalid commands, byte writes, and W1C status.
    task automatic test_control;
        logic [31:0] value;
        axi_read('h01c, value);
        check(value == ROWS, "row capability");
        axi_read('h020, value);
        check(value == COLS, "column capability");
        axi_read('h024, value);
        check(value == OPERAND_W, "operand capability");
        axi_read('h02c, value);
        check(value == RESULT_W, "result capability");
        axi_read('hfff, value, 2'b10);
        axi_write('hfff, 1, 4'hf, 2'b10);
        axi_write('h008, 32'h12345678);
        axi_write('h008, 32'h00ab00cd, 4'b0101);
        axi_read('h008, value);
        check(value == 32'h12ab56cd, "byte write strobes");
        axi_write('h008, 0);
        axi_write('h000, 1, 4'hf, 2'b10);  // Zero length rejected.
        axi_write('h008, 1);
        axi_write('h00c, 0);
        axi_write('h000, 1, 4'hf, 2'b10);  // Zero rows rejected.
        axi_write('h00c, 32'(ROWS));
        axi_write('h010, 32'(COLS + 1));
        axi_write('h000, 1, 4'hf, 2'b10);  // Excess columns rejected.
        axi_write('h010, 32'(COLS));
        if (DATAFLOW == WEIGHT_STATIONARY) begin
            axi_write('h000, 1, 4'hf, 2'b10);  // No completed weight load.
            axi_write('h000, 3, 4'hf, 2'b10);  // No active bank to reuse.
        end
        axi_write('h000, 1, 4'h0);  // Zero strobe is a no-op.
        axi_write('h004, 6);
        axi_read('h004, value);
        check(value[2:0] == 0, "W1C status");
        axi_write('h014, 1);
    endtask

    // =============
    // Test timeout
    // =============
    initial begin
        #(CLK_PERIOD * 10000000);
        $fatal(1, "TEST FAILED: Simulation timeout");
    end

    // =========
    // Main test
    // =========
    initial begin
        integer fd;
        integer scanned;
        integer cases;
        string         vector_path;
        logic [31:0] value;
        seed = $urandom(seed);
        if (!$value$plusargs("VECTORS=%s", vector_path))
            vector_path = "build/vectors/vectors.txt";
        fd = $fopen(vector_path, "r");
        if (fd == 0)
            $fatal(1, "Cannot open vectors: %s", vector_path);

        // -----
        // Reset
        // -----
        reset_dut();
        test_control();

        // ----------------------
        // Normal operation
        // ----------------------
        scanned = $fscanf(fd, "%d", cases);
        if (scanned != 1)
            $fatal(1, "Malformed vector header");
        for (case_number = 0; case_number < cases; case_number++) begin
            scanned = $fscanf(
                fd,
                "%d %d %d %d %d %d %d %d",
                job_length,
                active_rows,
                active_cols,
                expected_rows,
                load_mode,
                preload_shadow,
                bad_last,
                random_stalls
            );
            if (scanned != 8)
                $fatal(1, "Malformed case header");
            if (DATAFLOW == WEIGHT_STATIONARY)
                for (int r = 0; r < ROWS; r++) begin
                    scanned = $fscanf(fd, "%h", weight_words[r]);
                    if (scanned != 1)
                        $fatal(1, "Malformed weights");
                end
            if (DATAFLOW == WEIGHT_STATIONARY && (preload_shadow != 0))
                for (int r = 0; r < ROWS; r++) begin
                    scanned = $fscanf(fd, "%h", shadow_words[r]);
                    if (scanned != 1)
                        $fatal(1, "Malformed shadow weights");
                end
            for (int i = 0; i < job_length; i++) begin
                scanned = $fscanf(fd, "%h", input_words[i]);
                if (scanned != 1)
                    $fatal(1, "Malformed input");
            end
            for (int i = 0; i < expected_rows; i++) begin
                scanned = $fscanf(fd, "%h %h", expected_words[i], expected_flags[i]);
                if (scanned != 2)
                    $fatal(1, "Malformed expected output");
            end
            run_test();
        end
        $fclose(fd);

        // -------------------------
        // Edge Cases
        // -------------------------
        axi_write('h008, 32'(DATAFLOW == OUTPUT_STATIONARY ? MAX_K + 1 : MAX_M + 1));
        axi_write('h000, 1, 4'hf, 2'b10);
        axi_write('h008, 32'(job_length));
        load_mode = (DATAFLOW == WEIGHT_STATIONARY) ? 1 : 0;
        press_start();
        axi_write('h000, 1, 4'hf, 2'b10);  // Busy start rejected.
        // -------------------------------
        // Reset during operation
        // -------------------------------
        @(negedge clk);
        s_axis_tvalid = 1;
        s_axis_tdata  = input_words[0];
        s_axis_tlast  = 0;
        do @(posedge clk); while (!s_axis_tready);
        reset_dut();
        wait_cycles(ROWS * WS_HOP + COLS + 10);
        check(!m_axis_tvalid, "reset flushes in-flight operation");
        axi_read('h004, value);
        check(value == 0, "reset clears control and weight validity");
        // Re-run the last golden case after reset to check recovery.
        load_mode      = 0;
        preload_shadow = 0;
        axi_write('h014, 1);
        run_test();

        // -------
        // Results
        // -------
        $display("----------------------------");
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        $display("Checked result elements: %0d", result_count);
        if ((pass_count + fail_count) == 0)
            $fatal(1, "NO CHECKS RUN");
        else if (fail_count != 0)
            $fatal(1, "TEST FAILED: %0d failures", fail_count);
        else
            $display("TEST PASSED");
        $display("----------------------------");
        $finish;
    end
endmodule
