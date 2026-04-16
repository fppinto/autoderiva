# TODO

Improvements tracked here. Quick wins are handled inline as they come up.

---

## Content

### Investigate remaining 19 INFs with no HWIDs
After fixing UTF-16 encoding in `generate_inventory.py`, the no-HWID count
dropped from 190 → 19. The remaining 19 are expected:

- **17 `AmdDMicExtTuningAPO_*` / `AmdDMicExt_Hp.inf`** — Extension class APO
  tuning INFs; they target devices via `TargetComputer*` directives, not
  standard HWID lines. Windows installs them as extensions automatically once
  the parent audio driver is installed.
- **1 `HPSetup.inf`** — metadata/setup INF, no installable device.
- **1 `PieComponent.INF`** — SoftwareComponent (triggers a Store app install);
  cannot be installed via pnputil.

Tasks:
- Confirm APO Extension INFs are auto-applied after the base Realtek/AMD audio
  driver installs, or document that they can be ignored.
- Remove `HPSetup.inf` and `PieComponent.INF` if confirmed to have no install
  value (no HWID, no pnputil path).
