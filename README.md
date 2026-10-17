# Stone Arch Silicon — IP Library

**One block at a time. Built together. Reused everywhere.**

Stone Arch Silicon develops **one reusable SystemVerilog IP block at a time**, with the whole organization contributing. Completed blocks remain here for future FPGA, ASIC, and SoC projects.

**Active IP:** _To be selected — update this line when the project starts._

## Structure

```text
sasi_<ip_name>/
│
├── docs/                       # IP documentation
│   ├── specification.md
│   ├── architecture.md
│   ├── verification_plan.md
│   ├── physical_design.md
│   └── integration_guide.md
│
├── rtl/                        # RTL Design
│   ├── src/                    # Synthesizable SystemVerilog
│   ├── include/                # Packages, defines, interfaces
│   └── filelist.f
│
├── dv/                         # Design Verification
│   ├── tb/                     # Testbench and environment
│   ├── tests/                  # Directed and random tests
│   ├── assertions/             # SystemVerilog Assertions
│   ├── formal/                 # Formal verification
│   ├── coverage/               # Coverage configuration
│   └── scripts/                # Simulation scripts
│
├── pd/                         # Physical Design
│   ├── synthesis/              # Synthesis scripts
│   ├── constraints/            # SDC timing constraints
│   ├── floorplan/              # Floorplanning configurations
│   ├── placement/              # Placement configurations
│   ├── cts/                    # Clock Tree Synthesis
│   ├── routing/                # Routing configurations
│   ├── sta/                    # Static Timing Analysis
│   ├── signoff/                # DRC, LVS, IR drop, etc.
│   └── platforms/              # PDK-specific configurations
│
├── integration/                # SoC Integration
│   ├── example_soc/            # Example SoC using the IP
│   ├── software/               # Drivers and test software
│   └── tests/                  # Integration tests
│
├── releases/                   # Versioned IP Deliverables
│   └── v1.0.0/
│       ├── rtl/                # Released RTL
│       ├── netlist/            # Gate-level netlists
│       ├── gds/                # GDSII layouts
│       ├── lef/                # Abstract physical views
│       ├── lib/                # Liberty timing/power models
│       ├── parasitics/         # SPEF files
│       ├── constraints/        # SDC files
│       ├── reports/            # PPA and signoff reports
│       └── manifest.yaml       # Version and configuration
│
├── scripts/                    # Shared automation
│
├── .github/
│   └── workflows/
│       └── ci.yml              # Continuous integration
│
├── Makefile                    # Standard build/test commands
├── Bender.yml                  # RTL dependencies and file manifest
├── README.md                   # Project overview and setup
├── LICENSE                     # Licensing
├── CHANGELOG.md                # Version history
└── CODEOWNERS                  # RTL/DV/PD maintainers
```

## Workflow

**Select IP → agree on spec → assign GitHub issues → design and verify → review → release → repeat.**

Get started: [Contributing](CONTRIBUTING.md) · [SystemVerilog style](docs/SYSTEMVERILOG_STYLE.md) · [Verification](docs/VERIFICATION.md).

**License:** [Apache 2.0](LICENSE) · [Stone Arch Silicon](https://stone-arch-silicon.github.io/stone-arch-silicon/)
