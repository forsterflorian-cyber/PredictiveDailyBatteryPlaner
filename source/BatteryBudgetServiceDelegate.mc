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
        // Take snapshot in background
        var logger = new BatteryBudget.SnapshotLogger();
        logger.logSnapshot();
        
        // Save data
        BatteryBudget.StorageManager.getInstance().saveAll();
        
        // Cleanup old segments periodically
        var settings = BatteryBudget.StorageManager.getInstance().getSettings();
        var windowDays = settings[:learningWindowDays];
        if (windowDays == null || !(windowDays instanceof Number)) { windowDays = 14; }
        
        BatteryBudget.StorageManager.getInstance().cleanupOldSegments(windowDays as Number);
        
        // Apply pattern decay weekly (check if it's been a week)
        applyWeeklyDecayIfNeeded();
        
        // Temporal background events are one-shot; schedule next run now.
        scheduleNextTemporalEvent(settings);
        
        // Return status to app
        Background.exit({"status" => "ok", "time" => Time.now().value()});
    }
    
    // Temporal events are one-shot; schedule the next one.
    private function scheduleNextTemporalEvent(settings as Dictionary) as Void {
        try {
            var intervalMin = settings[:sampleIntervalMin];
            if (intervalMin == null || !(intervalMin instanceof Number)) {
                intervalMin = 15;
            }
            var interval = intervalMin as Number;

            // Garmin minimum interval is 5 minutes
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
        var nowSec = Time.now().value();
        var weekSeconds = 7 * 24 * 60 * 60;
        
        if (lastDecayTime == 0 || (nowSec - lastDecayTime) >= weekSeconds) {
            var patternLearner = new BatteryBudget.PatternLearner();
            patternLearner.applyDecay();
            storage.updateStats("lastDecayTime", nowSec);
        }
    }
}
