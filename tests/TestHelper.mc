import Toybox.Test;
import Toybox.Lang;

module BatteryBudgetTestHelper {

    function makeBatteryStatusMock(currentBattery as Number, idleRate as Float,
                                   nativeRate as Float, broadcastRate as Float,
                                   plannedNativeMinutes as Number,
                                   plannedBroadcastMinutes as Number) as Dictionary {
        return {
            :currentBattery => currentBattery,
            :idleRate => idleRate,
            :nativeRate => nativeRate,
            :broadcastRate => broadcastRate,
            :plannedNativeMinutes => plannedNativeMinutes,
            :plannedBroadcastMinutes => plannedBroadcastMinutes
        };
    }

    function makeSensorHistoryMock(heartRate as Number, sampleCount as Number,
                                   idleDensity as Float, drainRate as Float,
                                   idleRate as Float, hasNativeActivity as Boolean) as Dictionary {
        return {
            :heartRate => heartRate,
            :sampleCount => sampleCount,
            :hrDensity => sampleCount.toFloat() * 6.0f,
            :idleDensity => idleDensity,
            :drainRate => drainRate,
            :idleRate => idleRate,
            :hasNativeActivity => hasNativeActivity
        };
    }

    function makeWeeklyPlanStateMock(weekKey as Number, nativeUsedMin as Number,
                                     broadcastUsedMin as Number) as BatteryBudget.WeeklyPlanState {
        return {
            :weekKey => weekKey,
            :nativeUsedMin => nativeUsedMin,
            :broadcastUsedMin => broadcastUsedMin
        } as BatteryBudget.WeeklyPlanState;
    }

    function makePendingBroadcastEventMock(weekKey as Number, startOffsetMin as Number,
                                           durationMin as Number, battDrop as Number,
                                           drainRate as Float) as BatteryBudget.PendingBroadcastEvent {
        return {
            :startTMin => weekKey + startOffsetMin,
            :endTMin => weekKey + startOffsetMin + durationMin,
            :durationMin => durationMin,
            :battDrop => battDrop,
            :drainRate => drainRate,
            :weekKey => weekKey,
            :hrDensity => 42
        } as BatteryBudget.PendingBroadcastEvent;
    }

    function assertFloatClose(logger as Test.Logger, actual as Float, expected as Float,
                              tolerance as Float, message as String) as Void {
        logger.debug(message + " actual=" + actual.toString() + " expected=" + expected.toString());
        Test.assertMessage(absFloat(actual - expected) <= tolerance, message);
    }

    function absFloat(value as Float) as Float {
        return value < 0.0f ? -value : value;
    }
}
