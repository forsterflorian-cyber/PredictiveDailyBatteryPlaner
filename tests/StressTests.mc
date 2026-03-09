import Toybox.Test;
import Toybox.Lang;

(:test)
function testPerfectStormClampKeepsIdleDaysPositive(logger as Test.Logger) as Boolean {
    var remainingBroadcastMinutes = BatteryBudget.Forecaster.calculateRemainingPlannedMinutes(5 * 60, 8 * 60);
    var idleOnlyDays = BatteryBudget.Forecaster.computeRemainingDaysWithPlan(
        5,
        1.0f,
        8.0f,
        3.0f,
        0,
        remainingBroadcastMinutes
    );

    logger.debug("remainingBroadcastMinutes=" + remainingBroadcastMinutes.toString()
        + " idleOnlyDays=" + idleOnlyDays.toString());
    Test.assertEqual(0, remainingBroadcastMinutes);
    Test.assertMessage(idleOnlyDays > 0.0f, "idle-only lifetime must stay positive after budget overrun clamp");
    Test.assertMessage(idleOnlyDays < 2.0f, "clamped chaos-case forecast must still be critical for the UI");
    return true;
}

(:test)
function testPerfectStormPendingSurvivesCrashAndKeepsCriticalForecast(logger as Test.Logger) as Boolean {
    BatteryBudget.StorageManager.resetInstanceForTests();
    var storage = BatteryBudget.StorageManager.getInstance();
    storage.resetAllData();

    var weekKey = BatteryBudget.TimeUtil.getCurrentWeekKey();
    storage.setWeeklyPlanState(BatteryBudgetTestHelper.makeWeeklyPlanStateMock(weekKey, 0, 6 * 60));
    storage.recordUsageForSegment(BatteryBudget.STATE_BROADCAST, weekKey + 60, weekKey + 180);
    storage.enqueuePendingBroadcastEvent(
        BatteryBudgetTestHelper.makePendingBroadcastEventMock(weekKey, 60, 120, 5, 4.0f)
    );
    storage.saveAll();

    BatteryBudget.StorageManager.resetInstanceForTests();
    storage = BatteryBudget.StorageManager.getInstance();

    var weekly = storage.getWeeklyPlanState();
    var pending = storage.getPendingBroadcastEvents();
    var remainingBroadcastMinutes = BatteryBudget.Forecaster.calculateRemainingPlannedMinutes(5 * 60,
        weekly[:broadcastUsedMin] as Number);
    var daysWithPlan = BatteryBudget.Forecaster.computeRemainingDaysWithPlan(
        5,
        1.0f,
        8.0f,
        3.0f,
        0,
        remainingBroadcastMinutes
    );

    logger.debug("broadcastUsedMin=" + (weekly[:broadcastUsedMin] as Number).toString()
        + " pending=" + pending.size().toString()
        + " daysWithPlan=" + daysWithPlan.toString());
    Test.assertEqual(8 * 60, weekly[:broadcastUsedMin] as Number);
    Test.assertEqual(1, pending.size());
    Test.assertEqual(120, (pending[0] as BatteryBudget.PendingBroadcastEvent)[:durationMin] as Number);
    Test.assertEqual(0, remainingBroadcastMinutes);
    Test.assertMessage(daysWithPlan < 2.0f, "forecast must stay critical immediately after reboot with pending event");

    storage.resetAllData();
    BatteryBudget.StorageManager.resetInstanceForTests();
    return true;
}

(:test)
function testPerfectStormZeroBaseDrainCannotDivideByZero(logger as Test.Logger) as Boolean {
    var result = BatteryBudget.Forecaster.calculateRemainingDays(5, 0.0f, 999.0f);

    logger.debug("zeroBaseDrainResult=" + result.toString());
    Test.assertEqual(0.0f, result);
    return true;
}
