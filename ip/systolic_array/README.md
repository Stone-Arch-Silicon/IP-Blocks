# Stone Arch Silicon — Parameterized Systolic Array IP

**Status:** In development  
**Maintainers:** Stone Arch Silicon RTL team  
**Top module:** `sa_top`  
**Configuration package:** `rtl/sa_pkg.sv`  

## Purpose

This IP is a configurable matrix-multiplication engine for ASIC and FPGA accelerator designs. It computes:

```text
C[M,N] = A[M,K] × B[K,N]
```

A rectangular grid of processing elements (PEs) performs the multiply–accumulate operations with local operand movement and pipelined arithmetic. Typical uses include neural-network linear layers, batched matrix operations, and accelerator compute tiles.

The design implements **two separately elaborated dataflows**:

- **Output-stationary (OS):** Each PE accumulates a result element while A travels right and B travels down. Best suited to output tiles that fit within the physical PE rows and columns.
- **Weight-stationary (WS):** Each PE holds a B weight, A travels right, and partial sums travel down. A double-buffered weight bank supports reuse across output rows/jobs and loading the inactive bank while computation proceeds.

Supported numeric builds are **signed INT2, INT4, INT8**, and **FP16 operands with FP16 or FP32 results**. FP16 dot products use exact internal finite accumulation followed by a single round-to-nearest-even conversion; they are not equivalent to repeated FP32-accumulator FMAs.

The IP provides an AXI4-Lite control/status interface and ready/valid operand, weight, and result streams. **Memory, DMA, scheduling, quantization/scaling, and clock-domain crossings belong to the surrounding system.** There is no built-in AXI4 memory master.

## Interface

### Clock and reset

| Signal | Direction | Width | Description |
| --- | --- | --- | --- |
| `clk` | Input | 1 | Rising-edge clock for all control and datapath registers; **one clock domain**. No target frequency is qualified. |
| `rst_n` | Input | 1 | **Active-low, synchronous** reset. Assert across at least one rising edge. Aborts the active job, clears control/FIFO/validity, and invalidates WS weight banks. Internal payload flops need not be reset. |

**Important:** These are the actual public port names; `clk_i` and `rst_ni` from the generic README template are *not* ports of `sa_top`.

### AXI4-Lite control (`s_axi_*`)

Addresses are local **12-bit byte addresses**; data are 32 bits. Each AXI channel uses a VALID/READY handshake, with AW and W captured independently. One outstanding read and one outstanding write are supported.

| Signal | Direction | Width | Description |
| --- | --- | --- | --- |
| `s_axi_awaddr` | Input | `CSR_ADDR_W` (12) | Write byte address |
| `s_axi_awprot` | Input | 3 | Protection attributes; ignored (tie low if unused) |
| `s_axi_awvalid` | Input | 1 | Write address valid |
| `s_axi_awready` | Output | 1 | Write address accepted |
| `s_axi_wdata` | Input | 32 | Write data |
| `s_axi_wstrb` | Input | 4 | Per-byte write strobes |
| `s_axi_wvalid` | Input | 1 | Write data valid |
| `s_axi_wready` | Output | 1 | Write data accepted |
| `s_axi_bresp` | Output | 2 | Write response: `00` OKAY, `10` SLVERR |
| `s_axi_bvalid` | Output | 1 | Write response valid |
| `s_axi_bready` | Input | 1 | Host accepts write response |
| `s_axi_araddr` | Input | `CSR_ADDR_W` (12) | Read byte address |
| `s_axi_arprot` | Input | 3 | Protection attributes; ignored |
| `s_axi_arvalid` | Input | 1 | Read address valid |
| `s_axi_arready` | Output | 1 | Read address accepted |
| `s_axi_rdata` | Output | 32 | Read data |
| `s_axi_rresp` | Output | 2 | Read response: `00` OKAY, `10` SLVERR |
| `s_axi_rvalid` | Output | 1 | Read data valid |
| `s_axi_rready` | Input | 1 | Host accepts read response |

### Operand input (`s_axis_*`)

| Signal | Direction | Width | Description |
| --- | --- | --- | --- |
| `s_axis_tdata` | Input | `INPUT_W` | Packed operand lanes; OS: `ROWS` A lanes followed by `COLS` B lanes; WS: `ROWS` A lanes |
| `s_axis_tvalid` | Input | 1 | Beat valid |
| `s_axis_tready` | Output | 1 | Beat accepted on a rising edge when VALID is also high |
| `s_axis_tlast` | Input | 1 | Must mark the last configured operand beat; checked against the beat counter |

### Weight input (`s_weight_*`, WS only)

| Signal | Direction | Width | Description |
| --- | --- | --- | --- |
| `s_weight_tdata` | Input | `WEIGHT_W` | One physical B row, with `COLS` packed operand lanes |
| `s_weight_tvalid` | Input | 1 | Weight beat valid |
| `s_weight_tready` | Output | 1 | Inactive bank can accept a weight row; remains low in OS builds |
| `s_weight_tlast` | Input | 1 | Must be asserted on weight beat `ROWS-1` |

The WS loader requires **exactly `ROWS` beats per complete physical weight tile**, even when the active K dimension is smaller. An accepted new-weight START swaps the completed shadow bank into active use. Weight preloading can overlap computation; a complete bank cannot be overwritten until it is activated.

### Result output and interrupt

| Signal | Direction | Width | Description |
| --- | --- | --- | --- |
| `m_axis_tdata` | Output | `OUTPUT_W` | Packed C result row, `COLS` lanes, least-significant lane first |
| `m_axis_tuser` | Output | `USER_W = 5*COLS` | Per-column FP status `{NV,DZ,OF,UF,NX}`; all zero in integer mode |
| `m_axis_tvalid` | Output | 1 | Result row valid |
| `m_axis_tready` | Input | 1 | Consumer accepts result |
| `m_axis_tlast` | Output | 1 | Final result row of the command |
| `irq` | Output | 1 | Level-high interrupt when enabled and sticky DONE or ERROR is set |

All stream transfers occur **only when `TVALID && TREADY` on a rising clock edge**. A source must hold VALID, DATA, LAST, and any sideband stable until a handshake. There are no `TKEEP`, `TSTRB`, `TID`, or `TDEST` ports. Within a packed beat, lane `i` is at `[i*LANE_W +: LANE_W]`; high byte-padding bits are not separate lanes.

### Key register map

| Offset | Register | Description |
| --- | --- | --- |
| `0x000` | `COMMAND` | Bit 0 START; bit 1 REUSE_WEIGHTS for WS (`0x1` new tile, `0x3` reuse) |
| `0x004` | `STATUS` | Bit 0 BUSY; 1 DONE (W1C); 2 ERROR (W1C); 3 SHADOW_READY; 4 ACTIVE_WEIGHTS |
| `0x008` | `LENGTH` | OS: reduction length K; WS: output row count M |
| `0x00C` | `ACTIVE_ROWS` | OS: output rows M; WS: reduction rows K |
| `0x010` | `ACTIVE_COLS` | Output columns N |
| `0x014` | `IRQ_ENABLE` | Bit 0 enables interrupt |
| `0x018` | `BUILD_ID` | Mode identifier (not a source-revision hash) |
| `0x01C`–`0x034` | Build constants | Physical dimensions, operand/accumulator/result widths, compile-time limits |
| `0x038` | `BUSY_CYCLES` | Busy clock counter for most recent job |
| `0x03C` | `INPUT_BEATS` | Accepted operand beats |
| `0x040` | `OUTPUT_BEATS` | Accepted result beats |

Register writes use AXI4-Lite WSTRB. Unmapped/unaligned or read-only writes return SLVERR and set sticky ERROR; invalid reads return SLVERR and zero data. Invalid START requests are rejected. DONE is set **after the final result handshake**, not merely when a result is computed. For the complete register-bit contract, see [docs/specification.md](docs/specification.md).

### Run-time legal dimensions

| Setting | Output-stationary | Weight-stationary |
| --- | --- | --- |
| `LENGTH` | K: `1..MAX_K` | M: `1..MAX_M` |
| `ACTIVE_ROWS` | M: `1..ROWS` | K: `1..ROWS` |
| `ACTIVE_COLS` | N: `1..COLS` | N: `1..COLS` |
| Operand transfers | K | M |
| Result transfers | M | M |

Set unused input lanes to zero. Results include `COLS` physical output lanes per beat; inactive result columns and their flags are zeroed. Larger matrix operations require external tiling and scheduling.

## Parameters

The public `sa_top` has **no `#(...)` instance parameters**. Hardware is configured at *compile time* through the `USER CONFIGURATION` constants in [`rtl/sa_pkg.sv`](rtl/sa_pkg.sv). Changing them requires recompilation and regeneration of test vectors. There is no run-time OS/WS or INT/FP switch.

| Parameter | Default | Valid values | Meaning |
| --- | --- | --- | --- |
| `DATAFLOW` | `OUTPUT_STATIONARY` | `OUTPUT_STATIONARY`, `WEIGHT_STATIONARY` | Selects mesh and dataflow |
| `NUMERIC_MODE` | `INTEGER_MODE` | `INTEGER_MODE`, `FP16_MODE` | Selects arithmetic implementation |
| `ROWS` | 8 | Integer ≥ 1 | Physical PE rows |
| `COLS` | 8 | Integer ≥ 1 | Physical PE columns |
| `INT_W` | 8 | 2, 4, 8 | Signed integer operand bits |
| `MAX_K` | 1024 | Integer ≥ 1 | Maximum OS reduction length |
| `MAX_M` | 1024 | Integer ≥ 1 | Maximum WS output rows/job |
| `INT_ACC_OVERRIDE` | 0 | 0 or ≥ `INT_MIN_ACC_W` | 0 chooses safe automatically sized accumulator (at least 32 bits) |
| `FP_RESULT_W` | 32 | 16, 32 | Floating output width; input always binary16 |
| `EXTRA_PRODUCT_REGS` | 0 | Integer ≥ 0 | Additional enabled product-transport stages |
| `OUT_FIFO_DEPTH` | 4 | Integer ≥ 2 | Buffered output beats |

Derived widths (do not edit directly):

```text
OPERAND_W      = FP16_MODE ? 16 : INT_W
RESULT_W       = FP16_MODE ? FP_RESULT_W : INT_ACC_W
PRODUCT_LATENCY= (FP16_MODE ? 3 : 1) + EXTRA_PRODUCT_REGS
INPUT_LANES    = OUTPUT_STATIONARY ? ROWS+COLS : ROWS
INPUT_W        = 8 * ceil(INPUT_LANES*OPERAND_W / 8)
WEIGHT_W       = 8 * ceil(COLS*OPERAND_W / 8)
OUTPUT_W       = 8 * ceil(COLS*RESULT_W / 8)
USER_W         = 5 * COLS
CSR_ADDR_W     = 12
```

A default 8×8 OS INT8 build therefore has 128-bit operand input, 64-bit unused WS weight input, 256-bit result data, and 40-bit result status flags. Physical size and clock speed still require target-specific synthesis and timing qualification.

## Architecture and assumptions

![Top level Block Diagram](images/lucid_ip_overview.png)

- **One generated mesh per build:** `array_os`/`pe_os` or `array_ws`/`pe_ws`. The nonselected mesh is not instantiated.
- **Arithmetic pipeline:** INT products have one registered product stage; FP16 products have three, plus any `EXTRA_PRODUCT_REGS`. Each PE accumulates with carry-save state. FP result finalization resolves the exact total and rounds once.
- **Transport:** Delay/skew stages align operands, FIRST/LAST tags, and result columns. `finalize` resolves/converts output columns; `fifo` buffers full output rows and sidebands.
- **Backpressure:** A full output FIFO freezes the arithmetic pipeline coherently via clock enable. Operand READY falls while the computation is stalled; the FIFO can continue draining. WS shadow-bank loading is independent of the compute enable.
- **Storage:** PE state, WS double-buffered weights, transport registers, and result FIFO are expressed as registers in the delivered RTL. No SRAM macro or external memory controller is instantiated.
- **Clocking / CDC:** All public ports use `clk`. External clock domains need complete AXI/stream CDC bridges. Do not synchronize payload bits individually.
- **Reset:** Synchronous active-low reset; reset and connected source/sink logic together. The payload bits may retain old values after reset but are invalid until their associated validity is set.
- **Job model:** One active matrix command at a time. WS can preload shadow weights while a job runs, but it cannot compute two independent jobs at once.
- **Error behavior:** Invalid START is rejected with SLVERR and sticky ERROR. Bad TLAST marks ERROR but does not automatically cancel the count-driven job. Too few beats or a permanently stalled result consumer can leave BUSY high indefinitely; there is no internal watchdog or ABORT register. Use coordinated reset for recovery.
- **Not implemented:** Runtime precision/dataflow reconfiguration, sparse execution, bias/activation/softmax, requantization, address-based DMA, scratchpad SRAM, and autonomous tiling.

For detailed datapath timing, state machines, and the hierarchy, see [docs/architecture.md](docs/architecture.md).

### Latency and throughput

Let `R=ROWS`, `C=COLS`, and `P=PRODUCT_LATENCY`. For continuously accepted operands, no output stalls, and an initially empty output FIFO, the first result is accepted this many clock-edge intervals after the first operand handshake:

- **OS:** `K + R + C + P + 2`
- **WS:** `R + C + P + 2`

The final result is accepted after `K + R + C + P + M + 1` intervals in OS, or `M + R + C + P + 1` intervals in WS. These formulas exclude register setup, WS weight preloading, and any source/sink stalls. The ideal mesh capacity is `ROWS*COLS` MAC operations per enabled cycle; this is **not** a measured sustained throughput or PPA claim. No frequency target has been validated.

## Directory structure

```text
ip/systolic_ip/
├── README.md                       This document
├── rtl/
│   ├── sa_pkg.sv                   Compile-time configuration and types
│   ├── sa_top.sv                   Public IP wrapper (synthesis top)
│   ├── csr.sv                      AXI4-Lite control/status and command validation
│   ├── engine.sv                   Job scheduling, stream handling and result path
│   ├── array_os.sv / pe_os.sv       Output-stationary mesh and PE
│   ├── array_ws.sv / pe_ws.sv       Weight-stationary mesh and PE
│   ├── product.sv / finalize.sv     Numeric product and output conversion
│   ├── delay.sv / fifo.sv           Transport alignment and output buffering
│   └── files.f                     Ordered RTL compile list
├── dv/
    └── tb/
│       ├── sa_tb.sv                    Full-IP self-checking tests
│       ├── csr_tb.sv                   Control-interface tests
│       └── arithmetic_tb.sv            FP arithmetic directed/exhaustive-vector tests
├── tools/
│   ├── reference.py                Bit-exact model and full-IP vector generator
│   └── generate_arithmetic.py      FP arithmetic vectors (imports reference.py)
└── docs/
    ├── specification.md            Public behavior, port and CSR contracts
    ├── architecture.md             Internal hierarchy and dataflow
    └── integration_guide.md        Connections and worked examples
```

The `ip/systolic_ip/` prefix is the intended location in the IP-Blocks repository. Match the paths to the checked-out source tree; the commands below run **inside that directory**.

## Run verification

**Prerequisites:** Linux shell; Python 3.10+ (standard library only); Synopsys VCS with a valid license and SystemVerilog support. Initialize the site's Synopsys tool environment before running. **These are the commands documented for the delivered source baseline, not commands independently executed while authoring this README.** Do not claim a VCS pass without saving the exact tool version, source commit, package values, seed, and logs.

Check the environment:

```bash
command -v vcs
vcs -ID
python3 --version
```

### Full-IP functional simulation (current package configuration)

Run from `ip/systolic_ip/`:

```bash
python3 tools/reference.py --package rtl/sa_pkg.sv --out build/vectors
vcs -full64 -sverilog -f rtl/files.f tb/sa_tb.sv -top sa_tb -o simv_sa -l compile_sa.log
./simv_sa +VECTORS=build/vectors/vectors.txt -l run_sa.log
```

**Expected:** `TEST PASSED` in the simulation output/log, with no failures. The generated `build/vectors/vectors.json` records the vector configuration. The reference generator owns its vector production; the simulation top is `sa_tb`, while synthesis top remains `sa_top`.

### AXI4-Lite CSR checks

```bash
vcs -full64 -sverilog rtl/sa_pkg.sv rtl/csr.sv tb/csr_tb.sv -top csr_tb -o simv_csr -l compile_csr.log
./simv_csr -l run_csr.log
```

**Expected:** `CSR TEST PASSED`.

### FP16 arithmetic checks

First change the package to `FP16_MODE` and select `FP_RESULT_W=16` or `32`. Then regenerate and rebuild:

```bash
python3 tools/generate_arithmetic.py --package rtl/sa_pkg.sv --out build/arithmetic
vcs -full64 -sverilog -f rtl/files.f tb/arithmetic_tb.sv -top arithmetic_tb -o simv_arithmetic -l compile_arithmetic.log
./simv_arithmetic +VECTORS=build/arithmetic/vectors.txt -l run_arithmetic.log
```

**Expected:** `ARITHMETIC PASSED`. The documented generator covers all 65,536 binary16 bit patterns multiplied by one, directed exceptional cases, and randomized dot products. It is not a substitute for full OS/WS stream testing.

**Rebuild rule:** Every change to `rtl/sa_pkg.sv` requires matching regenerated vectors **and** recompiled simulation binaries. For a released configuration, record the VCS build/version, exact Git SHA, random seed(s) used by the generator/testbench (or explicitly note deterministic/unseeded), PASS log path, and coverage. Never equate a successful compile with a passed simulation.

**Known limitations:** One fixed build configuration; one job at a time; no independent memory DMA; no clock-domain crossing; no watchdog/abort; count-driven TLAST checking; no on-chip SRAM macros; no verified ASIC PPA/frequency; the public build identifier does not uniquely identify the RTL commit.

## Integration

1. **Set the hardware:** Edit only the user-configurable constants in `rtl/sa_pkg.sv`. Rebuild RTL, vectors, and software packing logic for that build. Both `sa_top` instances in an ordinary compilation use the same global package values.
2. **Instantiate `sa_top`:** Connect `clk` and synchronous active-low `rst_n`; use `rtl/files.f` for compile order (`sa_pkg.sv` first). Do not use the testbench as the synthesis top.
3. **Attach control:** Connect `s_axi_*` through an AXI4-Lite interconnect, with local 12-bit address decoding. Program `LENGTH`, `ACTIVE_ROWS`, `ACTIVE_COLS`, and optionally IRQ_ENABLE before writing COMMAND.
4. **Attach operand and result adapters:** Pack lanes exactly as specified and implement ready/valid backpressure on both sides. Map result flags and TLAST to the system's result descriptor/interrupt handling. Source/destination SRAM, DMA, address generation, and cache coherency are external responsibilities.
5. **Handle WS correctly:** Stream a complete `ROWS`-beat B tile into the shadow bank; check SHADOW_READY; START with REUSE=0 to activate. Later jobs can use REUSE=1 while the current active tile is valid.
6. **Coordinate reset:** Prevent stray VALID assertions during reset, drop stale upstream/downstream transaction state, and reload WS weights after reset. Cross-clock systems require external CDC bridges.
7. **Constrain the real target:** Define clock period, input/output delays, false/multicycle paths only where architecturally justified, and the actual standard-cell or FPGA technology. Run synthesis, lint, formal/protocol checks, STA, and physical signoff in the intended implementation flow; parameterization alone establishes none of these results.

For integration examples and data packing, read [docs/integration_guide.md](docs/integration_guide.md). For complete hardware contracts, read [docs/specification.md](docs/specification.md).

## Contributors and licensing

Contributions are coordinated by the Stone Arch Silicon RTL team. Follow the repository's [contribution process](../../CONTRIBUTING.md) and [Apache-2.0 license](../../LICENSE). Preserve applicable third-party attribution and license notices; the top-level repository license does not supersede third-party terms.
