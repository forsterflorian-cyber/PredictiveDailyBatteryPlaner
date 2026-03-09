import Toybox.Test;
import Toybox.Lang;

(:test)
function testCalculateRemainingDaysEmptyBudget(logger as Test.Logger) as Boolean {
    var mock = BatteryBudgetTestHelper.makeBatteryStatusMock(72, 1.0f, 8.0f, 3.0f, 0, 0);
    var result = BatteryBudget.Forecaster.computeRemainingDaysWithPlan(
        mock[:currentBattery] as Number,
        mock[:idleRate] as Float,
        mock[:nativeRate] as Float,
        mock[:broadcastRate] as Float,
        mock[:plannedNativeMinutes] as Number,
        mock[:plannedBroadcastMinutes] as Number
    );
    var expected = 72.0f / 24.0f;

    BatteryBudgetTestHelper.assertFloatClose(logger, result, expected, 0.001f,
        "empty weekly plan should fall back to idle-only days");
    return true;
}

(:test)
function testCalculateRemainingDaysOverdrawnBudgetClampsToZero(logger as Test.Logger) as Boolean {
    var result = BatteryBudget.Forecaster.calculateRemainingDays(20, 24.0f, 40.0f);

    logger.debug("overdrawnRemainingDays=" + result.toString());
    Test.assertEqual(0.0f, result);
    return true;
}

(:test)
function testCalculateRemainingDaysMatchesFormula(logger as Test.Logger) as Boolean {
    var mock = BatteryBudgetTestHelper.makeBatteryStatusMock(80, 1.0f, 8.0f, 3.0f, 120, 180);
    var result = BatteryBudget.Forecaster.computeRemainingDaysWithPlan(
        mock[:currentBattery] as Number,
        mock[:idleRate] as Float,
        mock[:nativeRate] as Float,
        mock[:broadcastRate] as Float,
        mock[:plannedNativeMinutes] as Number,
        mock[:plannedBroadcastMinutes] as Number
    );
    var plannedDrain = 16.0f + 9.0f;
    var expected = (80.0f - plannedDrain) / 24.0f;

    BatteryBudgetTestHelper.assertFloatClose(logger, result, expected, 0.001f,
        "remaining days should follow (battery - plannedDrain) / baseDrain");
    return true;
}

(:test)
function testCalculateRemainingDaysGuardsZeroBaseline(logger as Test.Logger) as Boolean {
    var result = BatteryBudget.Forecaster.calculateRemainingDays(80, 0.0f, 10.0f);

    logger.debug("zeroBaselineRemainingDays=" + result.toString());
    Test.assertEqual(0.0f, result);
    return true;
}
