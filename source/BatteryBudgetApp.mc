import Toybox.Application;
import Toybox.Application.Properties;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Background;
import Toybox.Time;

(:background :glance)
class BatteryBudgetApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        // Keep startup light on low-memory devices.
        BatteryBudget.StorageManager.getInstance();
        resetLearnedDataIfRequested();
        registerBackgroundEvents();
    }

    function onStop(state as Dictionary?) as Void {
        BatteryBudget.StorageManager.getInstance().saveAll();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new BatteryBudgetDetailView();
        var delegate = new BatteryBudgetDetailDelegate(view);
        return [view, delegate];
    }

    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new BatteryBudgetGlanceView()];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new BatteryBudgetServiceDelegate()];
    }

    function onBackgroundData(data as Application.PersistableType) as Void {
        // No-op: background delegate handles logging + scheduling.
    }

    private function resetLearnedDataIfRequested() as Void {
        try {
            var resetValue = Properties.getValue("resetData");
            if (resetValue instanceof Boolean && (resetValue as Boolean)) {
                BatteryBudget.StorageManager.getInstance().resetAllData();
                Properties.setValue("resetData", false);
            }
        } catch (ex) {
            // Ignore (settings not available on all platforms)
        }
    }

    private function registerBackgroundEvents() as Void {
        try {
            var settings = BatteryBudget.StorageManager.getInstance().getSettings();
            var intervalMin = settings[:sampleIntervalMin];
            if (intervalMin == null || !(intervalMin instanceof Number)) {
                intervalMin = 15;
            }
            var interval = intervalMin as Number;

            // Garmin limits minimum interval to 5 minutes
            if (interval < 5) { interval = 5; }

            var duration = new Time.Duration(interval * 60);
            var now = Time.now();
            var lastTime = Background.getLastTemporalEventTime();
            var nextTime;

            if (lastTime != null) {
                // Schedule next event relative to last run, but never in the past
                nextTime = lastTime.add(duration);
                if (nextTime.value() <= now.value()) {
                    nextTime = now.add(duration);
                }
            } else {
                // First registration - schedule for intervalMin from now
                nextTime = now.add(duration);
            }

            Background.registerForTemporalEvent(nextTime);
        } catch (ex) {
            // Background not supported or permission denied
        }
    }

    function onSettingsChanged() as Void {
        BatteryBudget.StorageManager.getInstance().reloadSettings();
        resetLearnedDataIfRequested();
        registerBackgroundEvents();
        WatchUi.requestUpdate();
    }
}
