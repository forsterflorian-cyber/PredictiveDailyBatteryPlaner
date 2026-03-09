# BatteryBudget

BatteryBudget is a Garmin Connect IQ widget that learns how your watch really
uses power and turns that data into a practical forecast: not just "How much
battery will I have tonight?", but "Will my battery still be ready for training
on Friday?"

The current alpha baseline is validated with **48 unit tests** covering forecast
math, broadcast detection, storage persistence, and stress scenarios.

## Smart Forecast

BatteryBudget uses a dual model for planned and detected load:

- **Native Garmin activities**: workouts with a real activity session on the
  watch, typically including GPS and higher overall power draw.
- **External HR broadcast sessions**: cases such as Zwift or trainer sessions
  where the watch stays outside a native activity but still drives the heart
  rate sensor and radio stack at elevated cost.

This separation makes the forecast much more useful than a single generic drain
curve. The app can learn, display, and budget both types independently.

## Why It Feels Personal

BatteryBudget learns on-device from your own usage history:

- **EMA drain learning** continuously adapts idle, activity, and broadcast
  drain rates using exponential moving averages.
- **Confidence logic** starts conservatively, then rises as the watch collects
  enough usable segments to trust the model.
- **Pattern learning** tracks when you usually train across a weekly time grid,
  so the forecast reflects your actual routine instead of a static assumption.

The result is a forecast that becomes more precise over time while still
remaining stable in noisy edge cases.

## Weekly Budget Planning

The planning model is built around a simple user question:

**Do I have enough battery left for the sessions I still want to do this week?**

BatteryBudget supports separate weekly budgets for:

- **Native hours**
- **Broadcast / Zwift hours**

The week-plan view shows how much of each budget is already consumed and how
many planned days remain under the current battery level. If a broadcast event
is detected automatically, the weekly budget is updated immediately and can be
confirmed on the next app start.

## Visual Feedback

The UI is designed to communicate battery risk quickly:

- forecast and footer warnings turn **red** when planned runtime becomes
  critical
- weekly budget bars clamp cleanly at **100%**
- overdrawn budgets are shown as exhausted instead of overflowing the layout

The week-plan layout uses a **relative, mathematically scaled design** rather
than fixed pixel anchors. That means the same logic adapts across round Garmin
displays without hard-coded FR955-only spacing.

## Local-Only by Design

BatteryBudget does not require cloud sync, an account, or a companion backend.

- all learning happens **directly on the watch**
- all history is stored in **local Application.Storage**
- no battery or behaviour data is sent to third parties

The runtime is intentionally lightweight. Background snapshots are compact, the
rendering path is optimized for low overhead, and the widget stays useful even
on memory-constrained devices.

## Stability and Test Coverage

The core engine is backed by **48 unit tests** with focused coverage for:

- forecast arithmetic and clamp behaviour
- broadcast signal and drain-spike discrimination
- weekly budget rollover and persistence
- pending-event survival across restart
- zero-drain and over-budget stress cases

The latest stress suite includes a "perfect storm" scenario with low battery,
budget overrun, a new pending broadcast event, and reboot persistence.

## Feature Overview

- End-of-day battery forecast with typical / conservative / optimistic values
- Dual activity model for native Garmin sessions and HR broadcast sessions
- Weekly battery budgeting for upcoming workouts
- Confidence-driven learning phase with EMA-based adaptation
- Automatic abnormal-drain and broadcast-event detection
- On-watch confirmation flow for detected broadcast sessions
- Responsive, relative UI that scales across display sizes
- Local-only storage and processing

## Build

### Prerequisites

- Garmin Connect IQ SDK
- `monkeyc`
- Garmin developer key

### App build

```powershell
monkeyc -f monkey.jungle -o dist\BatteryBudget.prg -y developer_key.der -d fr955 -w
```

### Test build

```powershell
monkeyc -f monkey.jungle -o dist\BatteryBudgetTests.prg -y developer_key.der -d fr955 -t -w
```

### Simulator run

```powershell
monkeydo dist\BatteryBudgetTests.prg fr955
```

## Project Structure

| File | Responsibility |
|---|---|
| `source/model/Forecaster.mc` | forecast math, budgets, confidence handling |
| `source/model/BroadcastDetector.mc` | HR/broadcast anomaly detection |
| `source/model/Segmenter.mc` | snapshot segmentation and planning usage |
| `source/model/Storage.mc` | persistent state, weekly counters, pending events |
| `source/BatteryBudgetDetailView.mc` | multi-page widget UI and week-plan rendering |
| `tests/` | unit and stress tests for forecast, detector, and storage logic |

## Privacy

BatteryBudget is fully local. No cloud dependency, no account, no telemetry.

