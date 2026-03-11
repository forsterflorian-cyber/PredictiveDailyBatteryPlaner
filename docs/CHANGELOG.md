# Changelog

## [1.0.0] - 2026-03-11

### Release hardening
- Stabilized the widget, glance, weekly plan, and background sampling flow for
  the `v1.0.0` release candidate.
- Kept storage compact by persisting only current state, learned rates,
  activity pattern, battery history, and pending broadcast confirmations.
- Aligned README, checklist, and store text with the current widget scope and
  supported device families.

### Prior fixes carried into release
- Hybrid HR broadcast detection and confirmation flow.
- Gap handling after restart and post-charge solar suppression.
- Relative layout scaling and legacy-safe dictionary parameter passing.
