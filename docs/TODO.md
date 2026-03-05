# TODO

Use this list for short-term execution planning. Keep tasks specific and verifiable.

## P0 - Must Fix
- [ ] Resolve `monkeyc` compile blocker: `Error occurred while reading Monkey C file: source/BatteryBudgetApp.mc`.
- [ ] Rebuild and validate on `fr955` after compile blocker is fixed.

## P1 - Next
- [ ] Verify detail page layouts on round devices (`fr955`, `fenix7`) and touch devices (`venu2`, `vivoactive5`) with real/sim screenshots.
- [ ] Verify glance readability across different widths and locales (ENG/DEU), especially long labels and time strings.
- [ ] Add a lightweight manual test checklist for:
  - [ ] Glance data correctness (now, EOD, risk, days)
  - [ ] Detail page navigation (`SELECT`, up/down, swipe)
  - [ ] Learning mode layout fit
  - [ ] Next activity page fit

## P2 - Later
- [ ] Re-introduce localized risk labels in glance without triggering resource access issues.
- [ ] Decide whether forecast should refresh on every page switch or only when stale.
- [ ] Add release process note for updating `docs/CHANGELOG.md` per shipped version.

## Done Recently (2026-03-05)
- [x] Fixed glance crash related to `Rez` symbol access in glance update path.
- [x] Switched `SELECT`/`ENTER` to page navigation and added stale-based auto refresh.
- [x] Fixed detail page 1 learning-mode overflow on small/round screens.
- [x] Fixed detail page 3 top/bottom clipping with adaptive text fitting for round screens.

