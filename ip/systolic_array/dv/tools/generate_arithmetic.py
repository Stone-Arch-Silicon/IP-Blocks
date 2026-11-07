#!/usr/bin/env python3
"""Generate vectors for arithmetic_tb using the selected sa_pkg.sv configuration.

This tool only writes stimulus and expected results. Compile and run the
SystemVerilog testbench separately with VCS. Only Python's standard library is
required; the independent FP oracle is in reference.py.
"""

import argparse
import json
import random
from pathlib import Path

from reference import fp_dot, read_config


def generate_arithmetic(config, destination, random_dots=20000, seed=20261105):
    """Exhaust FP16 encodings against +1, then test corner cases and random dots."""
    if config["NUMERIC_MODE"] != 1:
        raise ValueError("Set NUMERIC_MODE = FP16_MODE in rtl/sa_pkg.sv first.")
    if config["DATAFLOW"] not in (0, 1):
        raise ValueError("DATAFLOW must be OUTPUT_STATIONARY or WEIGHT_STATIONARY.")
    if config["FP_RESULT_W"] not in (16, 32):
        raise ValueError("FP_RESULT_W must be 16 or 32.")
    if random_dots < 0:
        raise ValueError("--random-dots must be nonnegative.")

    # Respect the number of terms used to size this package's FP accumulator.
    # The arithmetic bench exercises pe_os + finalize; the full-array bench
    # separately verifies the selected OS or WS dataflow.
    max_terms = config["MAX_K"] if config["DATAFLOW"] == 0 else config["ROWS"]
    if max_terms < 1:
        raise ValueError("The configured maximum number of terms must be positive.")

    result_width = config["FP_RESULT_W"]
    rng = random.Random(seed)
    directed = [
        ([0x3C00, 0xBC00], [0x3C00, 0x3C00]),
        ([0x7C00, 0xFC00], [0x3C00, 0x3C00]),
        ([0x3C00, 0x1000], [0x3C00, 0x3C00]),
        ([0x3C01, 0x1000], [0x3C00, 0x3C00]),
        ([0x0001], [0x3800]),
        ([0x0003], [0x3800]),
        ([0x7BFF], [0x4000]),
        ([0xFBFF], [0x4000]),
        ([0x7BFF, 0x7BFF], [0x7BFF, 0xFBFF]),
    ]
    directed = [(a, b) for a, b in directed if len(a) <= max_terms]
    length_choices = [n for n in (1, 2, 3, 7, 16, 31, 64, 128, 256)
                      if n <= max_terms]
    # Keep long tests bounded; include a non-power-of-two configured limit.
    tested_max_terms = min(max_terms, 256)
    if tested_max_terms not in length_choices:
        length_choices.append(tested_max_terms)
    total = 65536 + len(directed) + random_dots

    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    vector_path = destination / "vectors.txt"
    with vector_path.open("w") as stream:
        stream.write(f"{total}\n")

        def emit(a, b):
            result, flags = fp_dot(a, b, result_width)
            stream.write(f"{len(a)}\n")
            for activation, weight in zip(a, b):
                stream.write(f"{activation:x} {weight:x}\n")
            stream.write(f"{result:x} {flags:x}\n")

        for encoding in range(65536):
            emit([encoding], [0x3C00])
        for a, b in directed:
            emit(a, b)

        for index in range(random_dots):
            length = rng.choice(length_choices)

            def random_operand():
                value = rng.randrange(65536)
                if index % 4:
                    value = (value & 0x83FF) | (rng.randrange(31) << 10)
                return value

            a = [random_operand() for _ in range(length)]
            b = [random_operand() for _ in range(length)]
            if index % 7 == 0 and length > 1:
                a[1] = a[0] ^ 0x8000
                b[1] = b[0]
            emit(a, b)

    metadata = {
        "config": config,
        "seed": seed,
        "binary16_encodings": 65536,
        "directed_dots": len(directed),
        "random_dots": random_dots,
        "total_dots": total,
        "configured_max_terms": max_terms,
        "tested_max_terms": tested_max_terms,
        "vector_file": str(vector_path),
        "reference": "exact rational dot product, rounded once to nearest ties even",
    }
    (destination / "vectors.json").write_text(json.dumps(metadata, indent=2) + "\n")
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", default="rtl/sa_pkg.sv")
    parser.add_argument("--out", default="build/arithmetic")
    parser.add_argument("--random-dots", type=int, default=20000)
    parser.add_argument("--seed", type=int, default=20261105)
    args = parser.parse_args()
    try:
        metadata = generate_arithmetic(
            read_config(args.package), args.out, args.random_dots, args.seed
        )
    except ValueError as error:
        parser.error(str(error))
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
