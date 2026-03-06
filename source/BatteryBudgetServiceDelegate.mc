import Toybox.Lang;
import Toybox.System;
import Toybox.Background;
import Toybox.Time;

(:background)
class BatteryBudgetServiceDelegate extends System.ServiceDelegate {
    
    function initialize() {
        ServiceDelegate.initialize();
    }
    
    // Called when temporal event fires
    function onTemporalEvent() as Void {
        var storage = BatteryBudget.StorageManager.getInstance();

        // Take snapshot in background
        var logger = new BatteryBudget.SnapshotLogger();
        logger.logSnapshot();

        // Save data
        storage.saveAll();

        // Cleanup old segments periodically
        var settings = storage.getSettings();
        var windowDays = settings[:learningWindowDays];
        if (windowDays == null || !(windowDays instanceof Number)) { windowDays = 14; }

        storage.cleanupOldSegments(windowDays as Number);

        // Apply pattern decay weekly (check if it's been a week)
        applyWeeklyDecayIfNeeded();

        // Temporal background events are one-shot; schedule next run now.
        scheduleNextTemporalEvent(settings);

        // Return status to app
        Background.exit({"status" => "ok", "time" => Time.now().value()});
    }
    
    // Temporal events are one-shot; schedule the next one.
    // Uses the adaptive interval from SnapshotLogger so high-drain states
    // (activity, charging) are sampled more frequently than idle/sleep.
    private function scheduleNextTemporalEvent(settings as Dictionary) as Void {
        try {
            var storage = BatteryBudget.StorageManager.getInstance();
            var lastSnapshot = storage.getLastSnapshot();
            var currentState = BatteryBudget.STATE_IDLE as BatteryBudget.State;
            if (lastSnapshot != null) {
                currentState = lastSnapshot[:state] as BatteryBudget.State;
            }

            var logger = new BatteryBudget.SnapshotLogger();
            var interval = logger.getAdaptiveInterval(currentState);

            // Garmin minimum temporal event interval is 5 minutes
            if (interval < 5) { interval = 5; }

            var nextTime = Time.now().add(new Time.Duration(interval * 60));
            Background.registerForTemporalEvent(nextTime);
        } catch (ex) {
            // Background not supported or permission denied
        }
    }

    // Apply weekly decay to pattern if needed
    private function applyWeeklyDecayIfNeeded() as Void {
        var storage = BatteryBudget.StorageManager.getInstance();
        var stats = storage.getStats();
        
        var lastDecayTime = stats.hasKey("lastDecayTime") ? stats["lastDecayTime"] as Number : 0;
        var nowSec = Time.now().value().toNumber();
        var weekSeconds = 7 * 24 * 60 * 60;

        if (lastDecayTime == 0 || (nowSec - lastDecayTime) >= weekSeconds) {
            var patternLearner = new BatteryBudget.PatternLearner();
            patternLearner.applyDecay();
            storage.updateStats("lastDecayTime", nowSec);
        }
    }
}
