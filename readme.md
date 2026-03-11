# BatteryBudget

BatteryBudget is a Garmin Connect IQ widget for forecasting end-of-day battery availability from learned idle, activity, and HR broadcast drain. The current codebase is centered on `fr955` as the reference device and packaged for the supported Garmin families listed below.

## Main Features

- Learns idle, activity, and broadcast drain rates on-device
- Forecasts end-of-day battery and remaining activity budget
- Tracks weekly native Garmin activity load versus HR broadcast load
- Provides widget, glance, and background sampling support in one Connect IQ app

## Garmin Connect IQ Store

[BatteryBudget on Garmin Connect IQ Store](https://apps.garmin.com/en-US/search?keyword=BatteryBudget)

## Supported Device Families

- Forerunner: `fr165`, `fr165m`, `fr255`, `fr255m`, `fr255s`, `fr255sm`, `fr265`, `fr265s`, `fr57042mm`, `fr57047mm`, `fr745`, `fr955`, `fr965`, `fr970`
- Fenix / Epix / MARQ: `epix2`, `epix2pro42mm`, `epix2pro47mm`, `epix2pro51mm`, `fenix7`, `fenix7pro`, `fenix7pronowifi`, `fenix7s`, `fenix7spro`, `fenix7x`, `fenix7xpro`, `fenix7xpronowifi`, `fenix843mm`, `fenix847mm`, `fenix8pro47mm`, `fenix8solar47mm`, `fenix8solar51mm`, `fenixe`, `marq2`, `marq2aviator`
- Instinct: `instinct3amoled45mm`, `instinct3amoled50mm`, `instinct3solar45mm`, `instinctcrossover`, `instinctcrossoveramoled`, `instincte40mm`, `instincte45mm`
- Venu / Vivoactive: `venu2`, `venu2plus`, `venu2s`, `venu3`, `venu3s`, `venusq2`, `venusq2m`, `venux1`, `vivoactive4`, `vivoactive4s`, `vivoactive5`

## Build

- Release build: `.\scripts\build-release.ps1`
- Manual device build: `monkeyc -f monkey.jungle -o dist\BatteryBudget.prg -y developer_key.der -d fr955 -w`
- Store package output: `dist\BatteryBudget.iq`
