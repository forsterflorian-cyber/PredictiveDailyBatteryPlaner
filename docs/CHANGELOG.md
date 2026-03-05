# Changelog

All notable changes to this project are documented in this file.

The format is inspired by Keep a Changelog and follows semantic versioning where possible.

## [Unreleased]

### Fixed
- Avoided glance crash from `Rez` access in `BatteryBudgetGlanceView.updateData()` by using local risk label constants in the glance path.
- Restored missing `Toybox.Lang` import in `BatteryBudgetDetailDelegate.mc` that caused `Cannot resolve type 'Boolean'` compile errors.

### Changed
- Updated detail interaction:
  - `SELECT` / `KEY_ENTER` now cycles detail pages.
  - Forecast refresh is automatic on open and when stale (60s) during paging.
- Improved glance copy for readability:
  - `Now: X%`
  - `EOD HH:MM: ~Y%` (or learning state)
  - Risk/Learning status plus collected days
- Improved page 1 (Learning mode) layout to adapt on smaller/round screens by reducing optional elements when vertical space is tight.
- Improved page 3 (Next activity) layout to avoid round-screen clipping:
  - Adaptive title fallback (`Next Typical Activity` -> `Next Activity`)
  - Adaptive footer fallback (`Based on your weekly pattern` -> `Weekly pattern`)
  - Safe text width calculation near top/bottom round edges

### Notes
- Local compile still reports an existing parser/read issue in `source/BatteryBudgetApp.mc` on this machine and should be tracked separately from the UI fixes above.

