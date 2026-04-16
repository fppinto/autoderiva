#!/usr/bin/env python3
"""
Regenerate both export CSVs in one command.

Usage:
    python3 dev-scripts/generate_all.py

Runs, in order:
    1. generate_inventory.py  → exports/driver_inventory.csv
    2. generate_manifest.py   → exports/driver_file_manifest.csv
"""

import subprocess
import sys
from pathlib import Path

SCRIPTS = [
    Path(__file__).parent / "generate_inventory.py",
    Path(__file__).parent / "generate_manifest.py",
]


def main() -> None:
    for script in SCRIPTS:
        print(f"\n{'='*60}")
        print(f"Running {script.name} ...")
        print('='*60)
        result = subprocess.run([sys.executable, str(script)], check=False)
        if result.returncode != 0:
            print(f"\nERROR: {script.name} failed (exit {result.returncode})", file=sys.stderr)
            sys.exit(result.returncode)

    print("\n✓ All exports regenerated successfully.")


if __name__ == "__main__":
    main()
