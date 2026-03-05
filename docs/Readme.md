# BatteryBudget

A Garmin Connect IQ widget for compatible Garmin watches that predicts your end-of-day battery level based on learned usage patterns.

## What It Does

BatteryBudget answers: **"How much battery will I have tonight?"**

It learns from your actual usage:
- How fast your battery drains when idle
- How fast it drains during activities (running, cycling, etc.)
- When you typically exercise (day of week + time)

Then it predicts your battery level at end of day with:
- **Typical estimate**: Based on your patterns
- **Conservative/Optimistic range**: Best and worst case
- **Risk indicator**: Green/Yellow/Red warning

## Requirements

- A compatible Garmin watch (see `manifest.xml` for the current product list)
- Connect IQ SDK 3.3.0+
- Garmin Connect Mobile app (for settings)

## Installation

### From Connect IQ Store

1. Search "BatteryBudget" in the Connect IQ store
2. Install to your watch

### Build from Source

```powershell
# Build both a device PRG (for testing) and a store package IQ
.\scripts\build-release.ps1
```

Manual commands:

```bash
# Device build (for sideload/simulator) - pick any supported device id
monkeyc -f monkey.jungle -o bin/BatteryBudget.prg -y developer_key.der -d fr955 -w

# Store package (.iq)
monkeyc -f monkey.jungle -o dist/BatteryBudget.iq -y developer_key.der -e -r -w
```

## Usage

### Widget glance

Shows a quick summary:

```text
Now 58% | Tonight 31% (24-36) | Risk MED
```

### Detail view (tap to enter)

- Page 1: Full forecast with big numbers
- Page 2: Learned drain rates (Idle, Activity, per-sport)
- Page 3: Next predicted activity window
- Swipe up/down to change pages

## Project Tracking

- Change history: `docs/CHANGELOG.md`
- Open work items: `docs/TODO.md`

## Learning period

The widget needs ~14 days to learn your patterns. During this time it:

- Shows a "Learning" indicator
- Gives rough estimates based on idle drain only
- Shows a confidence percentage (progress)

## Settings (Garmin Connect Mobile)

- End of Day Time: When to predict battery for (default 22:00)
- Risk Thresholds: Yellow at 30%, Red at 15%
- Conservative Factor: Worst-case multiplier (default 1.2)
- Optimistic Factor: Best-case multiplier (default 0.8)
- Learning Window: Days of history to use (default 14)
- Sample Interval: Snapshot interval in minutes (default 15; only if background is supported)
- Reset learned data: Clear all on-watch history and start fresh

## How it works

- Logging: Battery % recorded every 15 minutes (background) or when you open the widget
- Segmentation: Continuous periods grouped by state (idle/activity/charging)
- Learning: Drain rates learned using exponential moving average
- Pattern: Activity times tracked by weekday + 30-min slot
- Forecast: Combines learned rates + patterns to predict tonight's battery

## Privacy

All data stays on your watch. Nothing is sent to any server.

## Troubleshooting

### "Learning" never completes

- Open the widget at least once daily
- Make sure background permissions are enabled
- Wait 14 days for full pattern learning

### Predictions seem wrong

- Check if your recent usage differs from typical
- Confidence < 50% means limited data
- Rates will adjust over time

### Widget slow to open

- Normal on first open after data update
- Should be <500ms after initial load

## Contributing

Pull requests welcome! Please see `docs/Spec.md` for technical details.
