# Technical Specification

## Forecast Formula
RemainingDays = (BatteryLevel - PlannedWeeklyDrain) / BaseDrainRate

## Detection Logic
Broadcast is detected if:
1. HeartRate > Threshold (10 min average)
2. Battery Drain Spike > 0.5%/h anomalous increase
3. No native Garmin activity is active (Activity.getActivityInfo().startTime)

## Learning Algorithm
Uses EMA (Exponential Moving Average) with a decay factor to prioritize 
recent usage while maintaining long-term patterns over 52 weeks.