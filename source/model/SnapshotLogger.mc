import Toybox.Lang;
import Toybox.System;
import Toybox.Activity;
import Toybox.ActivityMonitor;

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
            var state = detectCurrentState();
            var profile = detectCurrentProfile(state);
            
            var snapshot = {
                :tMin => tMin,
                :battPct => battPct,
                :state => state,
                :profile => profile
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
                    // Battery increased - charging detected
                    currentSnapshot[:state] = STATE_CHARGING;
                }
            }
            
            _storage.setLastSnapshot(currentSnapshot);
            _storage.recordFirstDataIfNeeded();
            
            // Trigger segmenter if we have a previous snapshot
            if (lastSnapshot != null) {
                var segmenter = new Segmenter();
                segmenter.processSnapshotPair(lastSnapshot, currentSnapshot);
            }
        }
        
        // Get current battery percentage
        private function getBatteryPercent() as Number {
            var stats = System.getSystemStats();
            if (stats != null && stats has :battery) {
                var batt = stats.battery;
                if (batt != null) {
                    return batt.toNumber();
                }
            }
            return 50; // Fallback
        }
        
        // Detect current state based on available APIs
        private function detectCurrentState() as State {
            // Check if device is charging
            if (isCharging()) {
                return STATE_CHARGING;
            }
            
            // Check if in activity
            if (isInActivity()) {
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
                if (stats != null && stats has :charging) {
                    return stats.charging;
                }
            } catch (ex) {
                // API not available
            }
            return false;
        }
        
        // Check if currently in an activity
        private function isInActivity() as Boolean {
            try {
                // Method 1: Check Activity.getActivityInfo()
                var info = Activity.getActivityInfo();
                if (info != null) {
                    // If we have activity info with elapsed time, we're in an activity
                    if (info has :elapsedTime && info.elapsedTime != null && info.elapsedTime > 0) {
                        return true;
                    }
                }
            } catch (ex) {
                // API not available or not in activity
            }
            
            try {
                // Method 2: Check ActivityMonitor for recent activity
                var actInfo = ActivityMonitor.getInfo();
                if (actInfo != null && actInfo has :moveBarLevel) {
                    // High move bar could indicate activity, but not reliable
                    // This is a weak signal, so we don't rely on it alone
                }
            } catch (ex) {
                // API not available
            }
            
            return false;
        }
        
        // Detect activity profile if in activity
        private function detectCurrentProfile(state as State) as Profile {
            if (state != STATE_ACTIVITY) {
                return PROFILE_GENERIC;
            }
            
            try {
                var info = Activity.getActivityInfo();
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
            var info = TimeUtil.getLocalTimeInfo();
            var hour = info.hour;
            // Consider 23:00 - 06:00 as potential sleep time
            return (hour >= 23 || hour < 6);
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
