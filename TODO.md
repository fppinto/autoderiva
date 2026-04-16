# TODO

Improvements tracked here. Quick wins are handled inline as they come up.

---

## Content

### Investigate 190 INFs with no HWIDs
Many INFs in the inventory have an empty `HardwareIDs` column — the installer
matches drivers by HWID, so these are never selected or installed.

Most are chipset metadata or Extension INFs whose device IDs use formats the
current regex doesn't capture (e.g., string-reference `%DevDesc%` without an
inline `PCI\VEN_` literal, or `NTamd64.6.1`-scoped sections).

Tasks:
- Audit the 190 no-HWID rows and classify: genuinely no HWID (metadata-only)
  vs. regex gap (HWID present but not extracted)
- Extend `HWID_RE` in `generate_inventory.py` if patterns are missing
- Remove any INFs confirmed to have no HWIDs and no pnputil install value

---

## Installer UX

### Friendly display names in model selection menu
The interactive model menu currently shows raw folder names (`hp-255-g7`,
`leap-t304-sf20pa6w`, etc.). Technicians would benefit from human-readable
labels.

Options:
- Add an optional `display_name` mapping in `config.defaults.json`
  (e.g. `"ModelDisplayNames": { "hp-255-g7": "HP 255 G7", ... }`)
- Or derive the label by title-casing and replacing hyphens with spaces

### Clearer fallback when no model matches
When running on an uncatalogued machine and no model is selected / nothing
matches, the installer falls back to scanning all models silently.
Should instead:
- Print an explicit "No matching model found for this hardware" message
- Offer: [1] Scan all models anyway  [2] Exit

---

## Dev / Tooling

### Tests don't run on macOS
The test suite uses Pester (PowerShell-only), blocking local test runs during
macOS development. Options:
- Add lightweight Python unit tests for the two Python generators
  (`generate_inventory.py`, `generate_manifest.py`) covering edge cases:
  uppercase `.INF`, UTF-16 BOM, missing DriverVer, etc.
- Document how to spin up a Windows VM / GitHub Actions run for full Pester suite

### CI check: CSVs must stay in sync with drivers/
Nothing currently prevents a driver file being added without regenerating the
inventory and manifest CSVs, causing silent installer failures.

Add a CI step that:
1. Runs `python3 dev-scripts/generate_all.py`
2. Diffs the output against the committed CSVs
3. Fails the build if there are any differences

This ensures `exports/` is always consistent with `drivers/`.
