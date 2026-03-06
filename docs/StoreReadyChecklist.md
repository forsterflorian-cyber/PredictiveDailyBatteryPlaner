
# BatteryBudget - Final Release Checklist (v1.0.0)

Work through every section top-to-bottom before uploading the .iq file.
Mark each item [ ] -> [x] as you complete it.

---

## 1. Code Audit

### 1.1 Background annotations
- [ ] All classes instantiated in `BatteryBudgetServiceDelegate.onTemporalEvent()`
      carry `(:background)`: StorageManager, SnapshotLogger, Segmenter,
      DrainLearner, PatternLearner, TimeUtil, Types.
- [ ] `Forecaster` does NOT carry `(:background)` (foreground only); confirm it
      is never called from the service delegate.
- [ ] Background heap: simulator memory profiling confirms peak during
      `onTemporalEvent()` stays below 32 kB.

### 1.2 Memory / Dictionary passing
- [ ] `Forecaster.forecast()` creates a new ForecastResult dict each call; the
      old reference in `BatteryBudgetDetailView._forecast` is replaced (GC-eligible).
- [ ] `getProfileSampleCounts()` returns a shallow copy; internal sampleCounts
      dict is not mutated externally.

### 1.3 resetLearning() completeness (all fields cleared)
- [ ] `_drainRates` reset to defaults and persisted.
- [ ] `_pattern` reset to zero array and persisted.
- [ ] `totalActivitySegments`, `totalIdleSegments`, `slotsCovered` zeroed.
- [ ] `_currentSegment` cleared in memory and storage.
- [ ] `_lastSnapshot` cleared in memory and storage (fix applied in v1.0.0:
      `Storage.deleteValue(KEY_LAST_SNAPSHOT)` called in `resetLearning()`).
- [ ] `_batteryHistory` cleared in memory and storage.
- [ ] `firstDataDay` and `lastDecayTime` intentionally kept.
- [ ] `_settings` intentionally not cleared (user preferences).

### 1.4 Manifest & permissions
- [ ] `manifest.xml` version = `1.0.0`.
- [ ] `Background` permission present.
- [ ] `UserProfile` permission present (sleep/wake time lookup).
- [ ] All product IDs in `<iq:products>` are valid CIQ SDK device IDs.
- [ ] `minSdkVersion="3.3.0"` confirmed correct.

### 1.5 Resource files
- [ ] `resources/strings/strings.xml` - all runtime IDs present (AppName,
      Tonight, Risk*, Learning*, History*, Solar*, etc.).
- [ ] `resources-deu/strings/strings.xml` - German translations complete;
      no ID missing compared to English file.
- [ ] `resources/properties/properties.xml` - all keys match `loadSettings()`.
- [ ] `resources/settings/settings.xml` - every `<setting>` has Label + Prompt.
- [ ] `resources/drawables/drawables.xml` - `LauncherIcon` SVG file exists.

### 1.6 Display compatibility
- [ ] MIP round 240x240 and 260x260: round-inset guard active; no text clipped.
- [ ] AMOLED 390x390 / 454x454 (venu3, vivoactive5): black fill renders cleanly.
- [ ] Rectangular 320x360 (venusq2): page dots and all content fit height.

---

## 2. Functional QA

### 2.1 Learning flow
- [ ] Fresh install: widget shows "LEARNING", confidence = 0 %, days = 0.
- [ ] After 1 background event: snapshot written; `firstDataDay` set.
- [ ] After ~20 idle + 10 activity segments: confidence >= 50 %; full forecast
      appears automatically.

### 2.2 Forecast correctness
- [ ] 100 % battery, default rates, 4 h remaining: typical ~97 %.
- [ ] conservative <= typical <= optimistic always holds.
- [ ] All three values clamped to [0, 100].
- [ ] Risk = HIGH when conservative < 15 %; MED < 30 %; LOW otherwise.

### 2.3 Solar (Fenix/Epix only)
- [ ] `solarGainRate` non-null after one idle segment with solarW >= 20.
- [ ] Typical forecast >= conservative when solar active (recentSolar > 10).

### 2.4 Activity Planner (What-If)
- [ ] 60-min run reduces typical end-of-day by approx. (profileRate - idleRate) * 1 h.
- [ ] `remainingActivityMinutes` decremented; never below 0.
- [ ] Risk indicator reflects new conservative estimate.

### 2.5 Settings round-trip
- [ ] End of Day Time change in GCM: forecast horizon updates on next open.
- [ ] Reset toggle: after GCM sync + widget open, rates at defaults, days = 0.

### 2.6 Background service
- [ ] Event fires; snapshot timestamp advances by ~sampleIntervalMin.
- [ ] During STATE_ACTIVITY: next event in sampleIntervalMin / 2.
- [ ] During STATE_IDLE: next event in sampleIntervalMin * 1.5 (capped 30 min).

### 2.7 Edge cases
- [ ] Widget opened at 23:58: remaining slots 0 or 1; no crash.
- [ ] Battery increases between snapshots: segment = CHARGING, excluded from EMA.
- [ ] Watch off > 1 h: gap discarded (isGapBreak = true); fresh segment on next pair.

---

## 3. Unit Tests

Run in simulator:
```bash
monkeyc -f monkey.jungle -o dist/BatteryBudgetTests.prg \
        -y <developer_key> -d fr955 -t
monkeydo dist/BatteryBudgetTests.prg fr955
```

- [ ] All 18 tests pass:
  - A1 testForecastIdleDrainFullBattery
  - A2 testConservativeFactorLowersThanTypical
  - A3 testOptimisticFactorHigherThanTypical
  - B1 testAbnormalDrainAboveThreshold
  - B2 testNormalDrainBelowThreshold
  - B3 testRiskHighAtLowBattery
  - C1 testSolarZerosEffectiveExtra
  - C2 testSolarReducesEffectiveExtra
  - C3 testActivityBudgetZeroWhenBelowTarget
  - D1 testParseTimeStringMidnight
  - D2 testParseTimeStringEndOfDay
  - D3 testParseTimeStringInvalidFallback
  - D4 testGetSlotIndex
  - D5 testGetEndOfDaySlotClamp
  - D6 testGetMinutesUntilTimePassed
  - E1 testCalculateDrainRate
  - E2 testCalculateDrainRateZeroDuration
  - E3 testIsGapValidLargeGap
  - E4 testIsGapValidExactLimit
  - E5 testIsGapValidBackwardTime
  - F1 testEMAClampHighRate
  - F2 testEMAClampLowRate
  - F3 testEMAConvergesToSample

---

## 4. Store Assets

- [ ] App icon: 70x70 px and 260x260 px PNG exported from launcher_icon.svg.
- [ ] Screenshots (minimum coverage):
  - Round MIP 260x260 (fr955 / fenix7): Glance learning, Glance forecast,
    Detail p1 forecast, Detail p2 rates, Detail p3 next activity.
  - Round MIP 240x240 (fenix7s): Detail p1.
  - Rectangular 320x360 (venusq2): Glance + Detail p1.
  - AMOLED 390x390 (venu3): Glance + Detail p1.
- [ ] All screenshots in sRGB; short side >= 270 px; no personal data visible.

---

## 5. Store Metadata

- [ ] English description from `docs/StoreListing.md` entered in Developer Portal.
- [ ] German description entered in Developer Portal.
- [ ] Keywords entered: battery life, battery forecast, battery planner,
      power management, energy monitor.
- [ ] "What's New" v1.0.0 text entered.
- [ ] Support email / URL set.
- [ ] Privacy Policy URL set.
- [ ] Category: Health & Fitness (or Tools & Utilities).

---

## 6. Release Build

```powershell
monkeyc -f monkey.jungle `
        -o dist/BatteryBudget.iq `
        -y $env:USERPROFILE\.Garmin\ConnectIQ\developer_key `
        -r -w

Get-Item dist\BatteryBudget.iq
```

- [ ] Build: 0 errors, 0 warnings.
- [ ] .iq file size < 500 kB.
- [ ] Sideload smoke test on physical watch: all 4 pages open; no crash.
- [ ] One background temporal event fires; snapshot timestamp advances.
- [ ] Upload `dist/BatteryBudget.iq` to Developer Portal.
- [ ] Version set to `1.0.0`; release notes match "What's New".
- [ ] Submitted for review.

---

## 7. Post-Release

- [ ] `git tag v1.0.0 && git push --tags`
- [ ] GitHub release created with `docs/CHANGELOG.md` content.
- [ ] Monitor Store reviews for first 7 days.
- [ ] Crash follow-up build within 14 days if needed.
