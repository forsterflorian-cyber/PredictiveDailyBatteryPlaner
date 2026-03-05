# BatteryBudget - Connect IQ Store Listing Draft

## Short description
Predict your end-of-day battery from on-watch usage patterns.

## Description
BatteryBudget is a Garmin Connect IQ **widget** for compatible Garmin watches (Forerunner, Fenix/Epix, Venu, Vivoactive, and more) that answers:

"How much battery will I have tonight?"

It learns on-device from your actual usage:
- Battery drain while idle
- Battery drain during activities
- Your typical weekly activity times (weekday + 30-minute slots)

Then it forecasts your battery at a configurable end-of-day time (default **22:00**) and shows:
- Typical estimate
- Conservative / optimistic range
- Risk indicator (LOW / MED / HIGH)

### Supported devices (v1.0.0)
- Forerunner: 255/255S, 265/265S, 955, 965
- Fenix/Epix: fenix 7 family, epix (Gen 2) family
- Venu/Vivoactive: Venu 2/3, Venu Sq 2, vivoactive 5

(Older low-memory models like FR55/FR245/fenix 6 are excluded in v1.)

### How to use
- Add the widget to your glances.
- Open it once per day (learning works faster if background logging is enabled).
- Optionally adjust settings in Garmin Connect Mobile.
- Use **Reset learned data** in Settings to start fresh at any time.

### Notes / limitations
- This is a forecast based on your history; it can be wrong if your day differs from your usual routine.
- Charging periods are detected and excluded from drain learning.

## Permissions
- **Background**: used to log periodic snapshots in the background (if supported/enabled). If disabled, BatteryBudget still works but learns more slowly.

## Privacy
All processing and data storage happens **on your watch**. BatteryBudget does not transmit data to any server.

## What's new (v1.0.0)
- Initial release.