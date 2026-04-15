#!/usr/bin/env python3
"""
Generate driver_file_manifest.csv from all files under drivers/.

For each file, computes SHA256 and associates it with the nearest parent
.inf file(s) in the same or a parent directory (stopping at drivers/).

Usage:
    python3 dev-scripts/generate_manifest.py

Outputs: exports/driver_file_manifest.csv
"""

import csv
import hashlib
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DRIVERS_DIR = REPO_ROOT / "drivers"
OUTPUT_FILE = REPO_ROOT / "exports" / "driver_file_manifest.csv"

FIELDNAMES = ["RelativePath", "Size", "Sha256", "AssociatedInf"]


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def find_associated_inf(file_path: Path) -> str | None:
    """
    Walk up from file_path's directory to DRIVERS_DIR looking for *.inf files.
    Returns semicolon-joined repo-relative paths, or None if none found.
    """
    current = file_path.parent
    while True:
        # Case-insensitive: glob("*.inf") misses uppercase .INF on some systems.
        infs = sorted(f for f in current.iterdir() if f.is_file() and f.suffix.lower() == ".inf")
        if infs:
            return ";".join(
                str(inf.relative_to(REPO_ROOT)).replace("\\", "/") for inf in infs
            )
        if current == DRIVERS_DIR:
            break
        parent = current.parent
        if parent == current or not str(current).startswith(str(DRIVERS_DIR)):
            break
        current = parent
    return None


def main() -> None:
    if not DRIVERS_DIR.exists():
        print(f"ERROR: drivers directory not found: {DRIVERS_DIR}", file=sys.stderr)
        sys.exit(1)

    # Exclude hidden/OS metadata files (.DS_Store, .gitkeep, etc.) — they are
    # not driver files and not fetched by the installer.
    files = sorted(
        f for f in DRIVERS_DIR.rglob("*")
        if f.is_file() and not f.name.startswith(".")
    )
    print(f"Scanning {len(files)} files in {DRIVERS_DIR} ...")

    rows = []
    for i, f in enumerate(files):
        if i % 50 == 0:
            print(f"  {i}/{len(files)}...", end="\r")
        rel = str(f.relative_to(REPO_ROOT)).replace("\\", "/")
        try:
            digest = sha256_of(f)
        except Exception as e:
            print(f"  WARN: SHA256 failed for {f.name}: {e}", file=sys.stderr)
            digest = None
        assoc = find_associated_inf(f)
        rows.append({
            "RelativePath":  rel,
            "Size":          f.stat().st_size,
            "Sha256":        digest,
            "AssociatedInf": assoc,
        })

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_FILE.open("w", newline="", encoding="utf-8") as fout:
        writer = csv.DictWriter(fout, fieldnames=FIELDNAMES)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nDone. {len(rows)} files written to {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
