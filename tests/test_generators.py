#!/usr/bin/env python3
"""
Unit tests for dev-scripts/generate_inventory.py and dev-scripts/generate_manifest.py.

Run with:
    python3 -m pytest tests/test_generators.py -v
or:
    python3 tests/test_generators.py
"""

import csv
import hashlib
import importlib.util
import io
import sys
import tempfile
import unittest
from pathlib import Path

# ---------------------------------------------------------------------------
# Load the two generator modules without executing their main() functions.
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
DEV_SCRIPTS = REPO_ROOT / "dev-scripts"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


inventory_mod = _load_module("generate_inventory", DEV_SCRIPTS / "generate_inventory.py")
manifest_mod  = _load_module("generate_manifest",  DEV_SCRIPTS / "generate_manifest.py")

parse_inf        = inventory_mod.parse_inf
find_associated_inf = manifest_mod.find_associated_inf


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _write(path: Path, content: str | bytes) -> None:
    if isinstance(content, bytes):
        path.write_bytes(content)
    else:
        path.write_text(content, encoding="utf-8")


def _utf16le(text: str) -> bytes:
    """Encode text as UTF-16 LE with BOM (matches DISM-exported INF files)."""
    return b'\xff\xfe' + text.encode('utf-16-le')


def _utf16be(text: str) -> bytes:
    """Encode text as UTF-16 BE with BOM."""
    return b'\xfe\xff' + text.encode('utf-16-be')


_SIMPLE_INF = """\
[Version]
Signature = "$Windows NT$"
Class     = Net
Provider  = %Mfg%
DriverVer = 01/01/2023, 1.2.3.4

[Manufacturer]
%Mfg% = Models, NTamd64

[Models.NTamd64]
%DevDesc% = Install, PCI\\VEN_8086&DEV_1234
"""


# ---------------------------------------------------------------------------
# Tests: parse_inf
# ---------------------------------------------------------------------------

class TestParseInfUtf8(unittest.TestCase):
    """parse_inf correctly handles plain UTF-8 INF files."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self.tmp.name)
        # Create a minimal drivers/ structure so InfPath extraction works
        self.drv_dir = self.tmpdir / "drivers" / "test-model"
        self.drv_dir.mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def _make_inf(self, name: str, content: str | bytes) -> Path:
        p = self.drv_dir / name
        _write(p, content)
        return p

    def test_basic_fields_extracted(self):
        p = self._make_inf("test.inf", _SIMPLE_INF)
        # Monkey-patch REPO_ROOT so InfPath is relative to our temp tree
        orig = inventory_mod.REPO_ROOT
        inventory_mod.REPO_ROOT = self.tmpdir
        try:
            row = parse_inf(p)
        finally:
            inventory_mod.REPO_ROOT = orig

        self.assertIsNotNone(row)
        self.assertEqual(row["FileName"], "test.inf")
        self.assertEqual(row["Class"], "Net")
        self.assertEqual(row["Provider"], "%Mfg%")
        self.assertEqual(row["Date"], "01/01/2023")
        self.assertEqual(row["Version"], "1.2.3.4")
        self.assertIn("PCI\\VEN_8086&DEV_1234", row["HardwareIDs"])
        self.assertEqual(row["ModelName"], "test-model")

    def test_uppercase_inf_extension(self):
        """Files ending in .INF (uppercase) are parsed the same as .inf."""
        p = self._make_inf("DRIVER.INF", _SIMPLE_INF)
        orig = inventory_mod.REPO_ROOT
        inventory_mod.REPO_ROOT = self.tmpdir
        try:
            row = parse_inf(p)
        finally:
            inventory_mod.REPO_ROOT = orig
        self.assertIsNotNone(row)
        self.assertEqual(row["Class"], "Net")

    def test_missing_driverver_returns_row(self):
        content = "[Version]\nClass=System\n"
        p = self._make_inf("nodriverver.inf", content)
        orig = inventory_mod.REPO_ROOT
        inventory_mod.REPO_ROOT = self.tmpdir
        try:
            row = parse_inf(p)
        finally:
            inventory_mod.REPO_ROOT = orig
        self.assertIsNotNone(row)
        self.assertIsNone(row["Date"])
        self.assertIsNone(row["Version"])

    def test_no_hwids_returns_empty_string(self):
        content = "[Version]\nClass=Extension\nDriverVer=02/02/2022, 5.0\n"
        p = self._make_inf("nohwid.inf", content)
        orig = inventory_mod.REPO_ROOT
        inventory_mod.REPO_ROOT = self.tmpdir
        try:
            row = parse_inf(p)
        finally:
            inventory_mod.REPO_ROOT = orig
        self.assertIsNotNone(row)
        self.assertEqual(row["HardwareIDs"], "")


class TestParseInfUtf16(unittest.TestCase):
    """parse_inf correctly handles UTF-16 LE and BE (DISM-exported INFs)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self.tmp.name)
        self.drv_dir = self.tmpdir / "drivers" / "test-model"
        self.drv_dir.mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def _make_inf(self, name: str, content: bytes) -> Path:
        p = self.drv_dir / name
        p.write_bytes(content)
        return p

    def test_utf16le_bom(self):
        p = self._make_inf("utf16le.inf", _utf16le(_SIMPLE_INF))
        orig = inventory_mod.REPO_ROOT
        inventory_mod.REPO_ROOT = self.tmpdir
        try:
            row = parse_inf(p)
        finally:
            inventory_mod.REPO_ROOT = orig
        self.assertIsNotNone(row)
        self.assertEqual(row["Class"], "Net")
        self.assertEqual(row["Version"], "1.2.3.4")
        self.assertIn("PCI\\VEN_8086&DEV_1234", row["HardwareIDs"])

    def test_utf16be_bom(self):
        p = self._make_inf("utf16be.inf", _utf16be(_SIMPLE_INF))
        orig = inventory_mod.REPO_ROOT
        inventory_mod.REPO_ROOT = self.tmpdir
        try:
            row = parse_inf(p)
        finally:
            inventory_mod.REPO_ROOT = orig
        self.assertIsNotNone(row)
        self.assertEqual(row["Class"], "Net")


# ---------------------------------------------------------------------------
# Tests: HWID_RE bus prefixes
# ---------------------------------------------------------------------------

class TestHwidRegex(unittest.TestCase):
    """HWID_RE captures all expected bus prefixes."""

    def _hwids_from(self, text: str) -> list[str]:
        return list({m.upper() for m in inventory_mod.HWID_RE.findall(text)})

    def test_pci(self):
        self.assertTrue(any("PCI" in h for h in self._hwids_from("PCI\\VEN_8086&DEV_1234")))

    def test_usb(self):
        self.assertTrue(any("USB" in h for h in self._hwids_from("USB\\VID_ABCD&PID_1234")))

    def test_acpi(self):
        self.assertTrue(any("ACPI" in h for h in self._hwids_from("ACPI\\INT3400")))

    def test_hid(self):
        self.assertTrue(any("HID" in h for h in self._hwids_from("HID\\VEN_ABCD")))

    def test_bthenum(self):
        # BTHENUM IDs use GUID-style format with curly braces
        self.assertTrue(any("BTHENUM" in h for h in self._hwids_from(
            "BTHENUM\\{00001101-0000-1000-8000-00805F9B34FB}_LOCALMFG&0000"
        )))

    def test_root(self):
        self.assertTrue(any("ROOT" in h for h in self._hwids_from("ROOT\\ACPI_HAL")))

    def test_hdaudio(self):
        self.assertTrue(any("HDAUDIO" in h for h in self._hwids_from("HDAUDIO\\FUNC_01&VEN_10EC")))

    def test_case_insensitive(self):
        self.assertTrue(any("PCI" in h for h in self._hwids_from("pci\\ven_8086&dev_1234")))


# ---------------------------------------------------------------------------
# Tests: find_associated_inf
# ---------------------------------------------------------------------------

class TestFindAssociatedInf(unittest.TestCase):
    """find_associated_inf walks up to the nearest parent INF."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self.tmp.name)
        # Simulate: <tmp>/drivers/my-model/audio/driver.inf
        #                                        data/firmware.bin
        #                                        nested/deep/file.cat
        self.drivers = self.tmpdir / "drivers"
        self.model   = self.drivers / "my-model"
        self.audio   = self.model / "audio"
        self.audio.mkdir(parents=True)
        self.inf = self.audio / "driver.inf"
        self.inf.write_text("[Version]\nClass=Media\n", encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def _find(self, path: Path) -> str | None:
        orig_root   = manifest_mod.REPO_ROOT
        orig_drivers = manifest_mod.DRIVERS_DIR
        manifest_mod.REPO_ROOT   = self.tmpdir
        manifest_mod.DRIVERS_DIR = self.drivers
        try:
            return find_associated_inf(path)
        finally:
            manifest_mod.REPO_ROOT   = orig_root
            manifest_mod.DRIVERS_DIR = orig_drivers

    def test_sibling_file_finds_inf(self):
        sibling = self.audio / "firmware.bin"
        sibling.write_bytes(b"\x00\x01")
        result = self._find(sibling)
        self.assertIsNotNone(result)
        self.assertIn("driver.inf", result)

    def test_nested_file_walks_up(self):
        nested = self.audio / "sub" / "deep.cat"
        nested.parent.mkdir(parents=True)
        nested.write_bytes(b"\x00")
        result = self._find(nested)
        self.assertIsNotNone(result)
        self.assertIn("driver.inf", result)

    def test_file_above_drivers_returns_none(self):
        """Files that never find an INF before reaching drivers/ return None."""
        orphan_dir = self.model / "orphan"
        orphan_dir.mkdir()
        orphan = orphan_dir / "readme.txt"
        orphan.write_text("no inf here")
        # Remove the INF so nothing is found
        self.inf.unlink()
        result = self._find(orphan)
        self.assertIsNone(result)

    def test_inf_file_itself_not_associated_with_itself(self):
        """The INF file itself gets associated with itself (consistent with manifest logic)."""
        result = self._find(self.inf)
        # The INF is in same directory as itself — should return it
        self.assertIsNotNone(result)
        self.assertIn("driver.inf", result)


# ---------------------------------------------------------------------------
# Tests: real inventory CSV sanity checks
# ---------------------------------------------------------------------------

class TestInventoryCsv(unittest.TestCase):
    """Smoke-test the committed exports/driver_inventory.csv."""

    CSV_PATH = REPO_ROOT / "exports" / "driver_inventory.csv"

    def setUp(self):
        if not self.CSV_PATH.exists():
            self.skipTest("exports/driver_inventory.csv not found")
        csv.field_size_limit(10 ** 7)
        with self.CSV_PATH.open(encoding="utf-8") as f:
            self.rows = list(csv.DictReader(f))

    def test_has_rows(self):
        self.assertGreater(len(self.rows), 0)

    def test_required_columns_present(self):
        expected = {"FileName", "InfPath", "ModelName", "Class", "Provider", "Date", "Version", "HardwareIDs"}
        actual = set(self.rows[0].keys())
        self.assertTrue(expected.issubset(actual), f"Missing columns: {expected - actual}")

    def test_no_hwid_count_under_threshold(self):
        """After the UTF-16 fix, at most 25 INFs should have empty HWIDs."""
        empty = [r for r in self.rows if not r["HardwareIDs"]]
        self.assertLessEqual(
            len(empty), 25,
            f"Too many no-HWID INFs ({len(empty)}); UTF-16 fix may be missing or HWID_RE needs extension"
        )

    def test_all_rows_have_model_name(self):
        missing = [r for r in self.rows if not r.get("ModelName")]
        self.assertEqual(missing, [], f"{len(missing)} rows missing ModelName")

    def test_all_rows_have_inf_path(self):
        missing = [r for r in self.rows if not r.get("InfPath")]
        self.assertEqual(missing, [], "Some rows are missing InfPath")


# ---------------------------------------------------------------------------
# Tests: real manifest CSV sanity checks
# ---------------------------------------------------------------------------

class TestManifestCsv(unittest.TestCase):
    """Smoke-test the committed exports/driver_file_manifest.csv."""

    CSV_PATH = REPO_ROOT / "exports" / "driver_file_manifest.csv"

    def setUp(self):
        if not self.CSV_PATH.exists():
            self.skipTest("exports/driver_file_manifest.csv not found")
        with self.CSV_PATH.open(encoding="utf-8") as f:
            self.rows = list(csv.DictReader(f))

    def test_has_rows(self):
        self.assertGreater(len(self.rows), 0)

    def test_required_columns_present(self):
        expected = {"RelativePath", "Size", "Sha256", "AssociatedInf"}
        actual = set(self.rows[0].keys())
        self.assertTrue(expected.issubset(actual), f"Missing columns: {expected - actual}")

    def test_sha256_format(self):
        """All Sha256 values should be 64-character hex strings."""
        bad = [r for r in self.rows if len(r.get("Sha256", "")) != 64]
        self.assertEqual(bad, [], f"{len(bad)} rows have malformed Sha256")

    def test_size_bytes_positive(self):
        bad = [r for r in self.rows if not r.get("Size", "").isdigit() or int(r["Size"]) < 0]
        self.assertEqual(bad, [], f"{len(bad)} rows have invalid Size")

    def test_most_files_have_associated_inf(self):
        """At least 95% of files should have an AssociatedInf."""
        total = len(self.rows)
        with_inf = sum(1 for r in self.rows if r.get("AssociatedInf"))
        pct = with_inf / total * 100
        self.assertGreaterEqual(pct, 95.0, f"Only {pct:.1f}% of files have AssociatedInf")


# ---------------------------------------------------------------------------

if __name__ == "__main__":
    unittest.main(verbosity=2)
