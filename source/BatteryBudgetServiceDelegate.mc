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
        var logger = new BatteryBudget.SnapshotLogger();

        logger.logSnapshot();
        storage.saveAll();

        var settings = storage.getSettings();
        var windowDays = settings[:learningWindowDays];
        if (windowDays == null || !(windowDays instanceof Number)) { windowDays = 14; }
        storage.cleanupOldSegments(windowDays as Number);

        // Apply pattern decay weekly; inline to avoid PatternLearner allocation.
        applyWeeklyDecayIfNeeded(storage);

        // Temporal background events are one-shot; reuse logger instance.
        scheduleNextTemporalEvent(storage, logger);

        Background.exit({"status" => "ok", "time" => Time.now().value()});
    }

    // Temporal events are one-shot; schedule the next one.
    // Reuses the already-allocated logger to determine the adaptive interval.
    private function scheduleNextTemporalEvent(storage as BatteryBudget.StorageManager,
                                               logger as BatteryBudget.SnapshotLogger) as Void {
        try {
            var lastSnapshot = storage.getLastSnapshot();
            var currentState = BatteryBudget.STATE_IDLE as BatteryBudget.State;
            if (lastSnapshot != null) {
                currentState = lastSnapshot[:state] as BatteryBudget.State;
            }

            var broadcastCandidate = (lastSnapshot != null) && (lastSnapshot[:broadcastCandidate] == true);
            var interval = logger.getAdaptiveInterval(currentState, broadcastCandidate);
            if (interval < 5) { interval = 5; }

            var nextTime = Time.now().add(new Time.Duration(interval * 60));
            Background.registerForTemporalEvent(nextTime);
        } catch (ex) {
            // Background not supported or permission denied
        }
    }

    // Apply weekly decay to the pattern array without allocating a PatternLearner.
    private function applyWeeklyDecayIfNeeded(storage as BatteryBudget.StorageManager) as Void {
        var stats = storage.getStats();
        var lastDecayTime = stats.hasKey("lastDecayTime") ? stats["lastDecayTime"] as Number : 0;
        var nowSec = Time.now().value().toNumber();

        if (lastDecayTime == 0 || (nowSec - lastDecayTime) >= (7 * 24 * 60 * 60)) {
            var pattern = storage.getPattern();
            for (var i = 0; i < pattern.size(); i++) {
                pattern[i] = (pattern[i].toFloat() * 0.9f).toNumber();
            }
            storage.setPattern(pattern);
            storage.updateStats("lastDecayTime", nowSec);
        }
    }
}
