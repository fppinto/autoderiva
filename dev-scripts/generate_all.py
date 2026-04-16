#!/usr/bin/env python3
"""
Regenerate both export CSVs in one command and keep the readme badge in sync.

Usage:
    python3 dev-scripts/generate_all.py

Runs, in order:
    1. generate_inventory.py  → exports/driver_inventory.csv
    2. generate_manifest.py   → exports/driver_file_manifest.csv
    3. Updates the Drivers-N badge in readme.md
"""

import csv
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
INVENTORY  = REPO_ROOT / "exports" / "driver_inventory.csv"
README     = REPO_ROOT / "readme.md"
BADGE_RE   = re.compile(r'(!\[Driver Count\]\(https://img\.shields\.io/badge/Drivers-)\d+(-blue[^)]*\))')

SCRIPTS = [
    Path(__file__).parent / "generate_inventory.py",
    Path(__file__).parent / "generate_manifest.py",
]


def _count_inventory_rows() -> int:
    if not INVENTORY.exists():
        return 0
    csv.field_size_limit(10 ** 7)
    with INVENTORY.open(encoding="utf-8") as f:
        return sum(1 for _ in csv.DictReader(f))


def _update_badge(count: int) -> bool:
    """Rewrite the driver count badge in readme.md. Returns True if changed."""
    if not README.exists():
        return False
    text = README.read_text(encoding="utf-8")
    new_text, n = BADGE_RE.subn(rf'\g<1>{count}\g<2>', text)
    if n == 0:
        print("  WARN: driver count badge not found in readme.md", file=sys.stderr)
        return False
    if new_text == text:
        return False
    README.write_text(new_text, encoding="utf-8")
    return True


def main() -> None:
    for script in SCRIPTS:
        print(f"\n{'='*60}")
        print(f"Running {script.name} ...")
        print('='*60)
        result = subprocess.run([sys.executable, str(script)], check=False)
        if result.returncode != 0:
            print(f"\nERROR: {script.name} failed (exit {result.returncode})", file=sys.stderr)
            sys.exit(result.returncode)

    count = _count_inventory_rows()
    if _update_badge(count):
        print(f"\n✓ readme.md badge updated → Drivers-{count}")
    else:
        print(f"\n  readme.md badge already up to date (Drivers-{count})")

    print("\n✓ All exports regenerated successfully.")


if __name__ == "__main__":
    main()
