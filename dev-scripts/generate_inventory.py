#!/usr/bin/env python3
"""
Generate driver_inventory.csv from all .inf files under drivers/.

Usage:
    python3 dev-scripts/generate_inventory.py

Outputs: exports/driver_inventory.csv
"""

import csv
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DRIVERS_DIR = REPO_ROOT / "drivers"
OUTPUT_FILE = REPO_ROOT / "exports" / "driver_inventory.csv"

HWID_RE = re.compile(
    r'(?:PCI|USB|ACPI|HID|HDAUDIO|BTH|BTHENUM|DISPLAY|INTELAUDIO|ROOT)\\[A-Za-z0-9_&{}.\\-]+',
    re.IGNORECASE,
)

INF_VALUE_RE = re.compile(r'^\s*{key}\s*=\s*(.*)$', re.MULTILINE)

FIELDNAMES = ["FileName", "InfPath", "ModelName", "Class", "Provider", "Date", "Version", "HardwareIDs"]


def get_inf_value(text: str, key: str) -> str | None:
    m = re.search(rf'(?m)^\s*{re.escape(key)}\s*=\s*(.*)$', text)
    if m:
        return m.group(1).strip().strip('"')
    return None


def parse_inf(inf_path: Path) -> dict | None:
    try:
        raw = inf_path.read_bytes()
        if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
            text = raw.decode('utf-16', errors='replace')
        else:
            text = raw.decode('utf-8', errors='replace')
    except Exception as e:
        print(f"  WARN: could not read {inf_path.name}: {e}", file=sys.stderr)
        return None

    driver_ver_raw = get_inf_value(text, "DriverVer")
    date = version = None
    if driver_ver_raw:
        parts = driver_ver_raw.split(",", 1)
        date = parts[0].strip()
        if len(parts) > 1:
            version = parts[1].strip()

    hwids = sorted({m.upper() for m in HWID_RE.findall(text)})

    inf_rel = inf_path.relative_to(REPO_ROOT)
    parts = inf_rel.parts  # e.g. ('drivers', 'sp12345-audio', 'oem.inf')
    model_name = parts[1] if len(parts) >= 2 and parts[0] == "drivers" else None

    return {
        "FileName":    inf_path.name,
        "InfPath":     str(inf_rel),
        "ModelName":   model_name,
        "Class":       get_inf_value(text, "Class"),
        "Provider":    get_inf_value(text, "Provider"),
        "Date":        date,
        "Version":     version,
        "HardwareIDs": ";".join(hwids),
    }


def main() -> None:
    if not DRIVERS_DIR.exists():
        print(f"ERROR: drivers directory not found: {DRIVERS_DIR}", file=sys.stderr)
        sys.exit(1)

    # Use case-insensitive match — rglob("*.inf") misses uppercase .INF files on
    # case-sensitive filesystems (Linux CI) and on macOS with Python ≥ 3.12.
    inf_files = sorted(
        f for f in DRIVERS_DIR.rglob("*")
        if f.is_file() and f.suffix.lower() == ".inf"
    )
    print(f"Scanning {len(inf_files)} .inf files in {DRIVERS_DIR} ...")

    rows = []
    for inf in inf_files:
        print(f"  {inf.name}", end="\r")
        row = parse_inf(inf)
        if row:
            rows.append(row)

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_FILE.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDNAMES)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nDone. {len(rows)} INFs written to {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
