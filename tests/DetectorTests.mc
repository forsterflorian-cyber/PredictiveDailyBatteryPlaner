import Toybox.Test;
import Toybox.Lang;

(:test)
function testBroadcastFalsePositiveWithoutDrainSpike(logger as Test.Logger) as Boolean {
    var mock = BatteryBudgetTestHelper.makeSensorHistoryMock(125, 7, 6.0f, 1.0f, 0.8f, false);
    var result = BatteryBudget.BroadcastDetector.shouldTrigger(
        mock[:hrDensity] as Float,
        mock[:idleDensity] as Float,
        mock[:heartRate] as Number,
        mock[:sampleCount] as Number,
        mock[:drainRate] as Float,
        mock[:idleRate] as Float,
        mock[:hasNativeActivity] as Boolean
    );

    logger.debug("falsePositiveGuard=" + result.toString());
    Test.assertMessage(!result, "dense HR without a real drain spike must not classify as broadcast");
    return true;
}

(:test)
function testBroadcastBlockedByNativeActivity(logger as Test.Logger) as Boolean {
    var mock = BatteryBudgetTestHelper.makeSensorHistoryMock(132, 7, 6.0f, 2.5f, 0.8f, true);
    var result = BatteryBudget.BroadcastDetector.shouldTrigger(
        mock[:hrDensity] as Float,
        mock[:idleDensity] as Float,
        mock[:heartRate] as Number,
        mock[:sampleCount] as Number,
        mock[:drainRate] as Float,
        mock[:idleRate] as Float,
        mock[:hasNativeActivity] as Boolean
    );

    logger.debug("nativeActivityBlocks=" + result.toString());
    Test.assertMessage(!result, "native Garmin activity must block broadcast detection");
    return true;
}

(:test)
function testBroadcastTriggersOnSignalAndSpike(logger as Test.Logger) as Boolean {
    var mock = BatteryBudgetTestHelper.makeSensorHistoryMock(118, 7, 6.0f, 2.5f, 0.8f, false);
    var result = BatteryBudget.BroadcastDetector.shouldTrigger(
        mock[:hrDensity] as Float,
        mock[:idleDensity] as Float,
        mock[:heartRate] as Number,
        mock[:sampleCount] as Number,
        mock[:drainRate] as Float,
        mock[:idleRate] as Float,
        mock[:hasNativeActivity] as Boolean
    );

    logger.debug("broadcastTrigger=" + result.toString());
    Test.assertMessage(result, "high HR density with a drain spike should classify as broadcast");
    return true;
}
