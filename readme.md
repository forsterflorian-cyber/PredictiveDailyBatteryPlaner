# BatteryBudget

BatteryBudget is a Garmin Connect IQ widget that learns usage patterns
to provide a practical battery forecast. It answers: "Will my battery
last until my training session on Friday?"

## Core Features
- Smart Dual-Model: Separates native Garmin activities from external 
  HR broadcast sessions (e.g. Zwift).
- EMA Learning: Continuously adapts to idle and activity drain rates.
- Weekly Budget: Plan hours for native and broadcast loads.
- Responsive UI: Mathematically scaled layout for all display sizes.

## Build & Installation
Build a device PRG (for testing):
.\scripts\build-release.ps1

Manual build:
monkeyc -f monkey.jungle -o bin/BatteryBudget.prg -y dev_key.der -d fr955 -w