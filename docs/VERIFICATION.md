# Verification and IP Acceptance

Every IP needs **reproducible evidence** that it does what its specification claims. Passing a few simulations does not establish universal correctness; report exactly what was tested.

## What each IP must provide

- **Specification:** intended function, ports, timing/latency, handshake, clock/reset behavior, parameter ranges, constraints, and assumptions (`ip/<block>/README.md` plus `docs/`).
- **Self-checking testbench:** automatically compares DUT outputs with an independent model or explicit expected results. Fail the simulation with a nonzero exit status (`$fatal` on failure), not just a printed `FAIL` message.
- **Test plan:** cover reset/startup, normal operation, edge cases, invalid inputs if defined, continuous transactions, stalls/backpressure if applicable, and legal parameter configurations.
- **Protocol checks:** assertions (SVA where supported) for safety properties such as no overflow, stable data under stall, legal FSM states, no invalid grant combinations, and expected handshakes.
- **Reproduction instructions:** tool and version, commands, top module, dependencies, seeds, and how to interpret pass/fail. Put them in the block README or a local script.
- **Results summary:** last tested revision, configurations, pass/fail counts, tool versions, outstanding limitations, and any justified exclusions.

Prefer deterministic directed tests first, then constrained-random tests with recorded seeds when useful. Add a regression test for every fixed bug. Testbench timing must avoid race conditions (clocking blocks or deliberate stimulus/sample scheduling). Use 4-state comparisons where detecting X/Z is appropriate. Include a watchdog timeout to catch hangs.

## Before merging a change

- [ ] Function and interface changes match the written specification.
- [ ] RTL lint passes, or every remaining warning is explained and reviewed.
- [ ] A self-checking testbench passes for the documented configurations.
- [ ] Relevant assertions and edge cases are covered.
- [ ] No unexplained X/Z, inferred latches, missing assignments, or multiple drivers.
- [ ] Parameters, widths, signedness, reset, and CDC implications have been considered.
- [ ] Documentation and tests are updated with the RTL change.
- [ ] At least one reviewer other than the author approves.

## Before declaring an IP reusable

- [ ] Interface and behavior are stable, specified, and reviewed.
- [ ] Regression is repeatable from a clean checkout using the documented tools.
- [ ] Supported parameter sets and limitations are stated, with evidence for tested combinations.
- [ ] Synthesis has been attempted for the intended target (FPGA or ASIC flow), and major warnings/unsupported constructs have been addressed; if not, the block is explicitly labeled **simulation-only**.
- [ ] A stable revision/tag is recorded and the block README includes an honest maturity label.

## Maturity labels

| Label | Required evidence |
| --- | --- |
| **In development** | Work in progress; no completeness claim |
| **Simulation-verified** | Reviewed specification and passing documented regression |
| **FPGA-tested** | Tested in physical FPGA hardware; board/tool/configuration recorded |
| **Silicon-proven** | Functionally validated on fabricated silicon; test evidence recorded |

These are evidence labels, **not** warranties. Physical validation does not remove the need to state configurations, conditions, and known limitations.
