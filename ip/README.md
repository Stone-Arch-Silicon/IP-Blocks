# IP blocks

Each completed block lives in `ip/<block_name>/`. **Only one new IP block is active at a time**; previous blocks remain here for bug fixes and reuse.

When starting a block:

1. Create `ip/<block_name>/rtl/`, `tb/`, and `docs/`.
2. Copy [`templates/IP_README.md`](../templates/IP_README.md) to `ip/<block_name>/README.md` and fill in the specification **before** implementing the RTL.
3. Update the root README's **Active IP** line and open GitHub issues for the team's tasks.
4. Use the repository's coding and verification standards before considering the block complete.
