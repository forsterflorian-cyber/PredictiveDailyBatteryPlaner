# Release Checklist

- [ ] Run the unit tests (`monkeyc -t`).
- [ ] Build the reference device and store package (`.\scripts\build-release.ps1`).
- [ ] Spot-check one modern simulator and one legacy/button-focused simulator.
- [ ] Verify English and German strings plus the store listing text.
- [ ] Confirm no widget memory or argument-limit regressions in simulator logs.
