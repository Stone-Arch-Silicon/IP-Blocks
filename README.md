# Stone Arch Silicon — IP Library

**One block at a time. Built together. Reused everywhere.**

Stone Arch Silicon develops **one reusable SystemVerilog IP block at a time**, with the whole organization contributing. Completed blocks remain here for future FPGA, ASIC, and SoC projects.

**Active IP:** _To be selected — update this line when the project starts._

## Structure

```text
ip/<block_name>/
├── rtl/          Synthesizable RTL
├── tb/           Tests and assertions
├── pd/           Physical Design Scripts
├── docs/
│   ├── specification.md
│   ├── architecture.md
│   ├── verification_plan.md
│   ├── physical_design.md
│   └── integration_guide.md
└── README.md     Interfaces and verification status

docs/            Shared coding and verification standards
templates/       README template for each IP
.github/         Pull-request template
```

## Workflow

**Select IP → agree on spec → assign GitHub issues → design and verify → review → release → repeat.**

Get started: [Contributing](CONTRIBUTING.md) · [SystemVerilog style](docs/SYSTEMVERILOG_STYLE.md) · [Verification](docs/VERIFICATION.md).

**License:** [Apache 2.0](LICENSE) · [Stone Arch Silicon](https://stone-arch-silicon.github.io/stone-arch-silicon/)
