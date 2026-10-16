# Contributing to the IP Library

Stone Arch Silicon develops **one IP block at a time as a team**. The repository keeps completed IP blocks available for reuse, but new feature work should focus on the designated active block. Bug fixes to released blocks are welcome.

## 1. Agree on the scope

Before implementation, the team should document the active block's purpose, interfaces, clock/reset behavior, parameters, dependencies, and acceptance tests in `ip/<block>/README.md` and `ip/<block>/docs/`. Keep a GitHub issue for each concrete task (e.g., RTL datapath, assertions, testbench, lint, documentation). Coordinate interface changes in an issue **before** changing them.

New IP proposals can be discussed while a block is active, but the team starts the next block only after the current block meets its agreed release criteria.

## 2. Make a focused change

1. Open or claim an issue. If it is large, split it into smaller, reviewable tasks.
2. Branch from `main` using `feature/<issue>-<short-name>` or `fix/<issue>-<short-name>`.
3. Follow [SystemVerilog coding guidelines](docs/SYSTEMVERILOG_STYLE.md). Keep RTL, testbenches, and documentation in the active block's folder.
4. Add or update tests alongside changes to behavior; follow [verification requirements](docs/VERIFICATION.md).
5. Run the checks documented in the block's README and record the results in your pull request. Never claim a check ran if it did not.
6. Open a pull request referencing the issue. Request review from at least one other contributor.

Avoid unrelated refactoring, interface-breaking changes without discussion, generated build products, vendor tool databases, credentials, proprietary PDK data, or copied third-party RTL without license review.

## 3. Review and merge

Reviewers check functional intent, interface compatibility, reset/clock behavior, width and signedness, parameter edge cases, verification evidence, and documentation. Address review comments before merging. Maintainers decide when the PR is ready. Protect `main` with required reviews and automated checks once checks are available.

## 4. Finish the active IP

Before declaring a block reusable, complete the [verification and release checklist](docs/VERIFICATION.md), record the **tested configurations and limitations**, and mark the block's maturity accurately. A passing simulation does **not** mean FPGA-tested or silicon-proven.

Use tags or block-specific releases to identify stable versions when maintainers approve a release. Keep the top-level README's **Active IP** line current.

## Licensing and authorship

This repository is licensed under **Apache-2.0**. By contributing, you agree your contribution can be distributed under that license, subject to its terms. Only submit code you have the right to share. Respect sponsor, employer, university, third-party, patent, and confidentiality obligations; ask maintainers before contributing anything with uncertain ownership. Preserve existing attribution and SPDX headers.
