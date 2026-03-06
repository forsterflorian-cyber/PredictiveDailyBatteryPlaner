# BatteryBudget – Garmin Connect IQ Widget

Predictive end-of-day battery forecast based entirely on on-device history.

---

## Build & Install

### Prerequisites
- [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) >= 3.3.0
- VSCode + Connect IQ extension, **or** `monkeyc` CLI
- Developer key (`~/.Garmin/ConnectIQ/developer_key`)

### Build (release)
```bash
monkeyc -f monkey.jungle -o dist/BatteryBudget.prg \
        -y ~/.Garmin/ConnectIQ/developer_key \
        -d fr955 -r
```
Or use the VSCode command palette: **Connect IQ: Build for Device**.

### Sideload to watch
```bash
monkeydo dist/BatteryBudget.prg fr955
```

### Run unit tests
```bash
monkeyc -f monkey.jungle -o dist/BatteryBudgetTests.prg \
        -y ~/.Garmin/ConnectIQ/developer_key \
        -d fr955 -t
monkeydo dist/BatteryBudgetTests.prg fr955
```

---

## How Learning Works

BatteryBudget collects data entirely on the watch. No cloud or Garmin Connect
data is involved.

1. **Snapshots** are written every ~15 minutes by a background service (or every
   time you open the widget if background is disabled).
2. **Segments** are built from consecutive snapshots with the same state and
   activity profile. Charging segments are automatically excluded.
3. **EMA learning** updates idle and activity drain rates from each finalized
   segment (`alpha = 0.2`, range clamped to `0.1–25 %/h`).
4. **Pattern learning** records how many minutes of activity occur in each
   weekday × hour slot (7 x 24 grid). Values decay 10 % per week to stay
   current.
5. **Forecast** combines current battery, remaining slots until end-of-day,
   learned rates, and solar gain (on supported hardware) into three estimates:
   typical / conservative / optimistic.

---

## Using the What-If Planner

The Activity Planner lets you check the battery impact of a training session
**before** you start it.

### Step-by-step

1. Open the BatteryBudget widget on your watch.
2. Swipe or scroll to **Page 4 – Activity Planner** (the rightmost page, icon: runner).
3. Tap the **activity type** selector and pick the sport that matches your
   planned session (Run / Bike / Hike / Generic).
4. Use the **+** and **−** buttons to set the planned duration in minutes.
5. The display updates immediately and shows:

   ```
   Tonight (with session): 34 %
   Range: 27 – 41 %
   Risk: LOW
   Budget remaining: 48 min
   ```

6. Adjust the duration until you find a scenario you are comfortable with.

### What the numbers mean

| Value | Explanation |
|---|---|
| **Tonight (with session)** | Typical end-of-day battery if you complete the planned session. |
| **Range** | Conservative (pessimistic) to optimistic end-of-day battery. |
| **Risk** | LOW / MED / HIGH based on the conservative estimate vs. your configured thresholds. |
| **Budget remaining** | How many additional activity minutes are still available before the typical estimate would fall below your target level (default: 15 %). |

### Tips
- The drain rate used for the calculation is your **personally learned** rate
  for that sport. If you have fewer than 3 sessions of a particular type, the
  generic activity rate is used instead.
- Solar watches: the planner already credits 50 % of the expected solar gain
  during the session, so the estimate stays conservative on cloudy days.
- After the session, open the widget once to let it log the actual battery
  change and refine the learned rate.

---

## Settings (Garmin Connect Mobile)

| Setting | Default | Description |
|---|---|---|
| End of Day Time | 22:00 | Target time for the end-of-day forecast. |
| Yellow Risk Threshold | 30 % | Battery % below which risk turns medium. |
| Red Risk Threshold | 15 % | Battery % below which risk turns high. |
| Conservative Factor | 1.20 | Drain multiplier for the pessimistic estimate. |
| Optimistic Factor | 0.80 | Drain multiplier for the best-case estimate. |
| Sample Interval | 15 min | Background logging interval. |
| Learning Window | 14 days | How many days of history the model uses. |
| Target Battery Level | 15 % | Minimum battery to keep at end of day (used for activity budget). |
| Sleep Start Hour | 22 | Hour when the sleep-reduced drain rate begins. |
| Sleep End Hour | 6 | Hour when normal drain rate resumes. |
| Reset learned data | off | Turn on once to wipe all learned rates and patterns. |

---

## FAQ

**Q: Why does the app show "LEARNING" instead of a forecast?**

BatteryBudget needs enough data before it can make a reliable prediction.
During the first 24–48 hours after installation the confidence score is below
0.5 and the app shows a rough idle-only estimate labelled "LEARNING". The
display also shows how many days of data have been collected and a progress bar.
Once confidence reaches 50 %+ (typically after 7–14 days of regular use), the
full three-value forecast appears automatically.

**Q: Why are the first few days of data less accurate than later?**

The EMA learning algorithm starts from conservative default rates
(`idle = 0.8 %/h`, `activity = 8.0 %/h`). Each new segment nudges the rates
by 20 % toward the actual observed value. After roughly 10–15 segments the
rates converge to your watch's real behaviour. The weekly activity pattern
needs at least one full week before it reflects your actual schedule.

**Q: Why does my forecast change significantly from day to day at first?**

With few data points, each new segment has a larger relative weight in the EMA.
This is intentional — it helps the model adapt quickly in the beginning. The
variance decreases as more data accumulates.

**Q: The app showed "LEARNING" again after I reset it. Why?**

"Reset learned data" in the settings wipes all drain rates, the activity
pattern, and the battery history back to defaults. The app effectively starts
fresh. The learning phase repeats for the same reason as a fresh install.

**Q: Does the app drain my battery?**

The background service is designed to consume as little power as possible:
- It runs for only a few milliseconds every 15–30 minutes.
- It uses less than 32 kB of RAM during a background event.
- Sampling intervals are automatically stretched during idle and sleep
  (up to 30 minutes) and shortened during active/charging states (down to
  5–7 minutes).

**Q: What happens if I forget to open the widget for several days?**

If background permissions are granted, the service logs snapshots
automatically and no data is lost. If background is disabled, no snapshots
are written while the widget is closed, and those hours are simply not learned
from. Open the widget daily for best accuracy.

**Q: The forecast is too pessimistic / too optimistic. Can I adjust it?**

Yes. In Garmin Connect Mobile settings, increase the **Conservative Factor**
(e.g. to 1.3) for a more pessimistic range, or decrease the **Optimistic
Factor** (e.g. to 0.7) for a tighter spread. Adjusting thresholds for Yellow
and Red risk changes when the risk indicator fires.

**Q: I just upgraded watch firmware. Should I reset?**

A firmware update can change the hardware's power profile. If you notice the
forecast drifting significantly after an update, use "Reset learned data" in
settings. The app will re-learn your new drain rates within a week.

**Q: Does BatteryBudget send any data online?**

No. All data is stored exclusively on the watch using Garmin's local
Application.Storage API. Nothing is transmitted to any server.

---

## Architecture (brief)

```
Background service (every ~15 min)
  └─ SnapshotLogger.logSnapshot()
       ├─ reads battery %, solar intensity, activity state
       ├─ writes compact snapshot to Storage
       └─ Segmenter.processSnapshotPair()
            ├─ DrainLearner.learnFromSegment()   (EMA drain rates)
            └─ PatternLearner.learnFromSegment() (weekly slots)

Widget opens
  └─ Forecaster.forecast()
       ├─ iterates remaining hourly slots to end-of-day
       ├─ applies learned rates + pattern + solar bonus
       └─ returns { typical, conservative, optimistic, risk, confidence, ... }
```

Key source files:

| File | Responsibility |
|---|---|
| [source/model/Forecaster.mc](source/model/Forecaster.mc) | Forecast and What-If calculation |
| [source/model/DrainLearner.mc](source/model/DrainLearner.mc) | EMA drain rate learning |
| [source/model/PatternLearner.mc](source/model/PatternLearner.mc) | Weekly activity pattern |
| [source/model/Segmenter.mc](source/model/Segmenter.mc) | Snapshot-to-segment conversion |
| [source/model/SnapshotLogger.mc](source/model/SnapshotLogger.mc) | Battery snapshot capture |
| [source/model/Storage.mc](source/model/Storage.mc) | Persistent storage manager |
| [source/util/TimeUtil.mc](source/util/TimeUtil.mc) | Time helpers and slot mapping |
| [tests/Tests.mc](tests/Tests.mc) | Unit test suite |
