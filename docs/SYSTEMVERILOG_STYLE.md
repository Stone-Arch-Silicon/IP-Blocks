# SystemVerilog Coding Guidelines

These are the default rules for **synthesizable RTL** in the Stone Arch Silicon IP Library. Deviations are allowed when a pull request explains the engineering reason and the block's documentation records it. Testbench-only constructs are covered separately in [Verification Guidelines](VERIFICATION.md).

## 1. Files and modules

- Use **SystemVerilog (`.sv`)** for RTL and testbenches. Use **`.svh`** only for include files; prefer packages for shared definitions.
- Use **one primary module/interface/package per file**, with a matching `snake_case` filename and descriptive module name. Keep modules reasonably small and single-purpose.
- Add a license identifier at the top of each new source file:

  ```systemverilog
  // SPDX-License-Identifier: Apache-2.0
  ```
- Use `default_nettype none` to catch accidental implicit wires, and restore `default_nettype wire` at the end of a module source file if the toolchain requires it. Do not rely on implicitly declared nets.
- Specify ports with ANSI-style declarations, declare signal types explicitly, and use `logic` for ordinary RTL signals. Declare intentional bidirectional or resolved nets explicitly as `wire`/`tri` when required.

## 2. Naming and formatting

| Item | Convention | Example |
| --- | --- | --- |
| Modules, instances, signals | `snake_case` | `sync_fifo`, `write_ptr_q` |
| Inputs / outputs | `_i` / `_o` suffix | `valid_i`, `ready_o` |
| Active-low inputs / outputs | `_ni` / `_no` suffix | `rst_ni` |
| Clock | `clk_i` (or named clock domain) | `clk_i`, `axi_clk_i` |
| Registered state / next state | `_q` / `_d` suffix | `state_q`, `state_d` |
| Parameters / constants | `UPPER_SNAKE_CASE` | `DATA_WIDTH` |
| Types | `_t` suffix | `state_t` |

- Use **4 spaces** for indentation, no tabs. Use `begin`/`end` on multiline blocks, meaningful names, and concise comments explaining *why* the logic exists.
- Use named port connections (`.clk_i(clk_i)`), not positional connections, for module instances.
- Keep RTL independent of a particular FPGA/ASIC vendor unless the IP specification explicitly requires a technology-specific wrapper.

## 3. Combinational versus sequential logic

- Use `always_comb` for combinational logic and **blocking (`=`)** assignments inside it. Assign every output or next-state variable on **all** paths; avoid inferred latches.
- Use `always_ff` for flip-flop logic and **nonblocking (`<=`)** assignments inside it. A register should have one procedural driver.
- Use continuous `assign` for simple wiring and expressions.
- Do **not** use `#` delays, `force/release`, testbench tasks, or unsynthesizable `initial` blocks in portable synthesizable RTL.
- Do not create combinational feedback or multiple drivers unless an IP explicitly and safely requires them.

```systemverilog
// SPDX-License-Identifier: Apache-2.0
`default_nettype none

module enabled_counter #(
    parameter int unsigned WIDTH = 8
) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic             enable_i,
    output logic [WIDTH-1:0] count_o
);
    // Example uses asynchronous assertion of active-low reset.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            count_o <= '0;
        end else if (enable_i) begin
            count_o <= count_o + WIDTH'(1);
        end
    end
endmodule

`default_nettype wire
```

The reset above is **only an example**. Each IP must specify whether its reset is synchronous or asynchronous, its polarity, reset values, assertion/deassertion requirements, and whether all state must be reset. Do not mix reset styles within the same clock domain without a documented reason.

## 4. Widths, signedness, and parameters

- Use **explicit widths** for buses, constants, and arithmetic results. Avoid accidental truncation, overflow, sign extension, and unsized literals in datapaths.
- Use `signed` intentionally. Mixed signed/unsigned arithmetic must have explicit casts or intermediate signals; document fixed-point scaling, rounding, and saturation when relevant.
- Use `parameter` for supported public configuration and `localparam` for derived/internal values. Document valid parameter ranges and test representative configurations.
- Prefer `$clog2` for index widths, but protect edge cases (such as depth 1) so no zero/negative-width declarations occur.
- Do not silently depend on simulator X propagation or synthesis don't-care assumptions. In synthesizable RTL, avoid driving `X` or `Z` except for deliberate resolved interfaces.

## 5. FSMs and protocols

- Declare FSM states using `typedef enum logic [...]`, with a registered state and explicit next-state logic. Handle illegal/default states predictably.
- Use plain `case` with a `default` branch when practical; do **not** use `casex` in synthesizable logic. Use `unique`/`priority` only when their guarantees and synthesis implications are justified.
- For valid/ready interfaces, define exactly when a transfer occurs and ensure data/control remain stable during backpressure as required by the protocol.
- Avoid gated/generated clocks in generic IP unless required and reviewed. Use clock enables where possible.
- Document all clock domains and reset domains. Clock-domain crossings require an appropriate reviewed CDC mechanism (e.g., synchronizer, handshake, asynchronous FIFO); simply placing signals in two clocks is not sufficient.

## 6. Quality bar

Before review, check **lint, simulation, reset behavior, parameter edge cases, protocol assertions, and warnings** using the commands documented for the specific IP. Warnings should be fixed or individually explained in the pull request; don't broadly suppress them. See [Verification Guidelines](VERIFICATION.md) for required evidence.
