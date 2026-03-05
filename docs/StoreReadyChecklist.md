# Store-Ready Checklist (v1.0.0)

## Required metadata
- Set a real support email in `docs/StoreListing.md` and `docs/Privacy.md`.
- (Optional) Add a public help URL / docs URL.

## Store assets
- Create screenshots on at least these display classes:
  - Round MIP 240x240 (e.g., `fenix7s`)
  - Round MIP 260x260 (e.g., `fr255`, `fr955`, `fenix7`)
  - Rectangular 320x360 (e.g., `venusq2`)
  - AMOLED 390x390 or 454x454 (e.g., `vivoactive5`, `venu3`)
- Capture:
  - Glance (Learning)
  - Glance (Forecast)
  - Detail page 1 (Learning)
  - Detail page 1 (Forecast)
  - Detail page 2 (Learned rates)
  - Detail page 3 (Next typical activity)

## QA (quick)
- Verify app settings apply correctly:
  - End of Day Time changes label and forecast behavior.
  - Sample Interval updates background schedule.
  - Reset learned data clears days collected + rates/pattern.
- Open/close widget multiple times (no crashes).
- Let one temporal event fire (background logging still works).

## Release build
- Run: `powershell -ExecutionPolicy Bypass -File .\scripts\build-release.ps1 -Clean`
- Upload `dist\BatteryBudget.iq` to the Connect IQ Store.