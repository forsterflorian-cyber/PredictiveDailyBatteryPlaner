import Toybox.Test;
import Toybox.Lang;

(:test)
function testWeeklyPlanStateResetsAcrossWeekBoundary(logger as Test.Logger) as Boolean {
    var staleState = BatteryBudgetTestHelper.makeWeeklyPlanStateMock(1000, 180, 90);
    var normalized = BatteryBudget.StorageManager.normalizeWeeklyPlanStateForWeek(staleState, 2000);

    logger.debug("normalizedWeekKey=" + (normalized[:weekKey] as Number).toString());
    Test.assertEqual(2000, normalized[:weekKey] as Number);
    Test.assertEqual(0, normalized[:nativeUsedMin] as Number);
    Test.assertEqual(0, normalized[:broadcastUsedMin] as Number);
    return true;
}

(:test)
function testPendingBroadcastEventsPersistAcrossRestart(logger as Test.Logger) as Boolean {
    BatteryBudget.StorageManager.resetInstanceForTests();
    var storage = BatteryBudget.StorageManager.getInstance();
    storage.resetAllData();

    var weekKey = BatteryBudget.TimeUtil.getCurrentWeekKey();
    storage.setWeeklyPlanState(BatteryBudgetTestHelper.makeWeeklyPlanStateMock(weekKey, 0, 0));
    storage.recordUsageForSegment(BatteryBudget.STATE_BROADCAST, weekKey + 60, weekKey + 120);
    storage.enqueuePendingBroadcastEvent(
        BatteryBudgetTestHelper.makePendingBroadcastEventMock(weekKey, 60, 60, 4, 4.0f)
    );
    storage.saveAll();

    BatteryBudget.StorageManager.resetInstanceForTests();
    storage = BatteryBudget.StorageManager.getInstance();

    var weekly = storage.getWeeklyPlanState();
    var pending = storage.getPendingBroadcastEvents();
    logger.debug("loadedBroadcastMin=" + (weekly[:broadcastUsedMin] as Number).toString()
        + " pending=" + pending.size().toString());

    Test.assertEqual(60, weekly[:broadcastUsedMin] as Number);
    Test.assertEqual(1, pending.size());

    var confirmed = storage.popNextPendingBroadcastEvent();
    Test.assertMessage(confirmed != null, "pending broadcast event should survive restart");
    storage.saveAll();

    BatteryBudget.StorageManager.resetInstanceForTests();
    storage = BatteryBudget.StorageManager.getInstance();

    var pendingAfterConfirm = storage.getPendingBroadcastEvents();
    var weeklyAfterConfirm = storage.getWeeklyPlanState();
    Test.assertEqual(0, pendingAfterConfirm.size());
    Test.assertEqual(60, weeklyAfterConfirm[:broadcastUsedMin] as Number);

    storage.resetAllData();
    BatteryBudget.StorageManager.resetInstanceForTests();
    return true;
}
