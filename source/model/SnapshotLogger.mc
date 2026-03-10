import Toybox.Lang;
import Toybox.System;
import Toybox.Activity;

(:background)
module BatteryBudget {
    
    class SnapshotLogger {
        
        private var _storage as StorageManager;
        
        function initialize() {
            _storage = StorageManager.getInstance();
        }
        
        // Take a snapshot of current battery state
        function takeSnapshot() as Snapshot {
            var tMin = TimeUtil.nowEpochMinutes();
            var battPct = getBatteryPercent();
            var activityInfo = getActivityInfoSafe();
            var isNativeActivity = hasNativeActivityStarted(activityInfo);
            var detector = new BroadcastDetector();
            var hrContext = detector.captureHeartRateContext();
            var state = detectCurrentState(isNativeActivity);
            var profile = detectCurrentProfile(state, activityInfo);
            var solarW = getSolarIntensity();

            var snapshot = {
                :tMin => tMin,
                :battPct => battPct,
                :state => state,
                :profile => profile,
                :solarW => solarW,
                :heartRate => hrContext[:heartRate] as Number,
                :hrDensity => hrContext[:hrDensity] as Number,
                :broadcastCandidate => (!isNativeActivity) && (hrContext[:broadcastCandidate] as Boolean)
            } as Snapshot;

            return snapshot;
        }
        
        // Log snapshot and potentially create segment
        function logSnapshot() as Void {
            var currentSnapshot = takeSnapshot();
            var lastSnapshot = _storage.getLastSnapshot();

            // Detect charging by battery increase
            if (lastSnapshot != null) {
                if (currentSnapshot[:battPct] > lastSnapshot[:battPct]) {
                    currentSnapshot[:state] = STATE_CHARGING;
                }
            }

            _storage.setLastSnapshot(currentSnapshot);
            _storage.recordFirstDataIfNeeded();

            // Append to compact history ring buffer (used for trend page)
            _storage.appendBatteryHistory(
                currentSnapshot[:tMin] as Number,
                currentSnapshot[:battPct] as Number);

            // Trigger segmenter if we have a previous snapshot
            if (lastSnapshot != null) {
                var segmenter = new Segmenter();
                segmenter.processSnapshotPair(lastSnapshot, currentSnapshot);
            }
        }
        
        // Get current battery percentage
        private function getBatteryPercent() as Number {
            var stats = System.getSystemStats();
            if (stats has :battery) {
                var batt = stats.battery;
                if (batt != null) {
                    return batt.toNumber();
                }
            }
            return 50; // Fallback
        }

        // Get solar intensity scaled to 0-100; returns 0 on unsupported devices
        private function getSolarIntensity() as Number {
            try {
                var stats = System.getSystemStats();
                if (stats has :solarIntensity) {
                    var solar = stats.solarIntensity;
                    if (solar instanceof Number) {
                        var v = (solar as Number).toNumber();
                        // Some devices return negative values when not charging from solar.
                        if (v < 0) { v = 0; }
                        if (v > 100) { v = 100; }
                        return v;
                    }
                }
            } catch (ex) {
                // solarIntensity not available on this device
            }
            return 0;
        }
        
        // Detect current state based on available APIs
        private function detectCurrentState(isNativeActivity as Boolean) as State {
            // Check if device is charging
            if (isCharging()) {
                return STATE_CHARGING;
            }
            
            // Check if in activity
            if (isNativeActivity) {
                return STATE_ACTIVITY;
            }
            
            // Check if sleep time (rough heuristic)
            if (isSleepTime()) {
                return STATE_SLEEP;
            }
            
            return STATE_IDLE;
        }
        
        // Check if device is charging
        private function isCharging() as Boolean {
            try {
                var stats = System.getSystemStats();
                if (stats has :charging) {
                    return stats.charging;
                }
            } catch (ex) {
                // API not available
            }
            return false;
        }
        
        // Check if currently in an activity
        private function hasNativeActivityStarted(info) as Boolean {
            if (info == null) {
                return false;
            }

            try {
                if (info has :startTime && info.startTime != null) {
                    return true;
                }
                if (info has :elapsedTime && info.elapsedTime != null && info.elapsedTime > 0) {
                    return true;
                }
            } catch (ex) {}
            return false;
        }

        private function getActivityInfoSafe() {
            try {
                return Activity.getActivityInfo();
            } catch (ex) {
                // API not available or not in activity
            }
            return null;
        }
        
        // Detect activity profile if in activity
        private function detectCurrentProfile(state as State, info) as Profile {
            if (state != STATE_ACTIVITY) {
                return PROFILE_GENERIC;
            }
            
            try {
                if (info != null && info has :sport) {
                    var sport = info.sport;
                    if (sport != null) {
                        return mapSportToProfile(sport);
                    }
                }
            } catch (ex) {
                // Can't determine profile
            }
            
            return PROFILE_GENERIC;
        }
        
        // Map Garmin sport type to our profile
        private function mapSportToProfile(sport as Number) as Profile {
            // Sport types from Activity module
            // Running = 1, Cycling = 2, Hiking = 16, etc.
            switch (sport) {
                case 1:  // Running
                case 10: // Trail Running
                    return PROFILE_RUN;
                case 2:  // Cycling
                    return PROFILE_BIKE;
                case 16: // Hiking
                case 11: // Walking
                    return PROFILE_HIKE;
                case 5:  // Swimming
                    return PROFILE_SWIM;
                default:
                    return PROFILE_OTHER;
            }
        }
        
        // Simple sleep time heuristic (rough)
        private function isSleepTime() as Boolean {
            return TimeUtil.isSleepTime(_storage.getSettings());
        }
        
        // Return an adaptive sample interval (minutes) based on the current state.
        // Active/charging sessions get shorter intervals for accurate drain curves;
        // idle/sleep get longer intervals to reduce background power consumption.
        function getAdaptiveInterval(state as State, broadcastCandidate as Boolean) as Number {
            var settings = _storage.getSettings();
            var base = settings[:sampleIntervalMin];
            var baseMin = (base instanceof Number) ? base as Number : 15;

            if (state == STATE_ACTIVITY || state == STATE_BROADCAST || state == STATE_CHARGING || broadcastCandidate) {
                // High-change states: sample at half the base interval, min 5 min
                var fast = baseMin / 2;
                return fast < 5 ? 5 : fast;
            }
            if (state == STATE_IDLE || state == STATE_SLEEP) {
                // Stable state: stretch to 1.5× base, max 30 min (safety cap)
                var slow = (baseMin * 3) / 2;
                return slow > 30 ? 30 : slow;
            }
            return baseMin;
        }

        // Get minimum interval between snapshots (minutes)
        function getMinSnapshotInterval() as Number {
            var settings = _storage.getSettings();
            var interval = settings[:sampleIntervalMin];
            return (interval != null) ? interval as Number : 15;
        }
        
        // Check if enough time has passed since last snapshot
        function shouldTakeSnapshot() as Boolean {
            var lastSnapshot = _storage.getLastSnapshot();
            if (lastSnapshot == null) {
                return true;
            }
            
            var nowMin = TimeUtil.nowEpochMinutes();
            var lastMin = lastSnapshot[:tMin];
            var minInterval = getMinSnapshotInterval();
            
            return (nowMin - lastMin) >= minInterval;
        }
    }
}
