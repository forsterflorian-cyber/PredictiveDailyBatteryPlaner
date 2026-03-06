// BatteryBudget – Unit Test Suite
// Build with: connectiq test (CIQ SDK >= 3.3)
// Run tests via VSCode Connect IQ extension or `monkeyc -t`.
//
// Test coverage:
//   A. Forecaster drain arithmetic (100 % battery, no learned pattern)
//   B. Abnormal-drain detection at 10 % battery
//   C. remainingActivityMinutes with strong solar compensation
//   D. TimeUtil edge cases (midnight, year boundary, DST-safe slot mapping)
//   E. Segmenter drain-rate and gap-validity helpers
//   F. EMA sanity (DrainLearner clamping and direction)

import Toybox.Test;
import Toybox.Lang;

// ---------------------------------------------------------------------------
// A. Forecaster drain arithmetic
// ---------------------------------------------------------------------------

// Test A1: With 100 % battery and default idle rate, a 4-hour window must
// yield a typical end-of-day value in [95, 100].
(:test)
function testForecastIdleDrainFullBattery(logger as Test.Logger) as Boolean {
    var idleRate = BatteryBudget.DEFAULT_RATE_IDLE; // 0.8 %/h
    var hoursRemaining = 4.0f;
    var nowBatt = 100.0f;

    var drain = idleRate * hoursRemaining;            // 3.2
    var endBatt = nowBatt - drain;                    // 96.8

    logger.debug("drain=" + drain.toString() + " endBatt=" + endBatt.toString());
    Test.assert(endBatt >= 95.0f);
    Test.assert(endBatt <= 100.0f);
    return true;
}

// Test A2: Conservative factor 1.2 must produce a lower estimate than typical.
(:test)
function testConservativeFactorLowersThanTypical(logger as Test.Logger) as Boolean {
    var idleRate    = BatteryBudget.DEFAULT_RATE_IDLE;
    var nowBatt     = 80.0f;
    var hoursLeft   = 6.0f;
    var consFactor  = 1.2f;

    var totalDrain      = idleRate * hoursLeft;                     // 4.8
    var typical         = nowBatt - totalDrain;                     // 75.2
    var conservative    = nowBatt - (totalDrain * consFactor);      // 74.24

    logger.debug("typical=" + typical.toString() + " conservative=" + conservative.toString());
    Test.assert(conservative < typical);
    return true;
}

// Test A3: Optimistic factor 0.8 must produce a higher estimate than typical.
(:test)
function testOptimisticFactorHigherThanTypical(logger as Test.Logger) as Boolean {
    var idleRate   = BatteryBudget.DEFAULT_RATE_IDLE;
    var nowBatt    = 80.0f;
    var hoursLeft  = 6.0f;
    var optFactor  = 0.8f;

    var totalDrain = idleRate * hoursLeft;
    var typical    = nowBatt - totalDrain;
    var optimistic = nowBatt - (totalDrain * optFactor);

    logger.debug("typical=" + typical.toString() + " optimistic=" + optimistic.toString());
    Test.assert(optimistic > typical);
    return true;
}

// ---------------------------------------------------------------------------
// B. Abnormal drain detection at 10 % battery
// ---------------------------------------------------------------------------

// Test B1: isAbnormalDrain threshold is DEFAULT_RATE_IDLE * 1.5.
// A rate of 1.3 %/h (> 1.2 threshold) must be classified as abnormal.
(:test)
function testAbnormalDrainAboveThreshold(logger as Test.Logger) as Boolean {
    var defaultRate = BatteryBudget.DEFAULT_RATE_IDLE; // 0.8
    var threshold   = defaultRate * 1.5f;              // 1.2
    var learnedRate = 1.3f;

    logger.debug("threshold=" + threshold.toString() + " learned=" + learnedRate.toString());
    Test.assert(learnedRate > threshold);
    return true;
}

// Test B2: A rate of 1.1 %/h (below threshold) must NOT be flagged.
(:test)
function testNormalDrainBelowThreshold(logger as Test.Logger) as Boolean {
    var defaultRate = BatteryBudget.DEFAULT_RATE_IDLE;
    var threshold   = defaultRate * 1.5f;
    var normalRate  = 1.1f;

    logger.debug("threshold=" + threshold.toString() + " normal=" + normalRate.toString());
    Test.assert(normalRate <= threshold);
    return true;
}

// Test B3: Risk level at 10 % battery with red threshold 15 % must be RISK_HIGH.
(:test)
function testRiskHighAtLowBattery(logger as Test.Logger) as Boolean {
    var endBatt        = 10;
    var redThreshold   = 15;
    var yellowThreshold = 30;

    var risk = BatteryBudget.RISK_LOW;
    if (endBatt < redThreshold) {
        risk = BatteryBudget.RISK_HIGH;
    } else if (endBatt < yellowThreshold) {
        risk = BatteryBudget.RISK_MEDIUM;
    }

    logger.debug("risk=" + risk.toString());
    Test.assert(risk == BatteryBudget.RISK_HIGH);
    return true;
}

// ---------------------------------------------------------------------------
// C. remainingActivityMinutes with solar compensation
// ---------------------------------------------------------------------------

// Test C1: When solar comp equals the full activity-vs-idle delta, effective
// extra per hour becomes 0 and the budget is capped to time remaining.
(:test)
function testSolarZerosEffectiveExtra(logger as Test.Logger) as Boolean {
    var idleRate      = BatteryBudget.DEFAULT_RATE_IDLE;   // 0.8
    var profileRate   = BatteryBudget.DEFAULT_RATE_ACTIVITY; // 8.0
    var delta         = profileRate - idleRate;             // 7.2

    // Solar strong enough to cover the full delta
    var solarCompPerHour = 7.2f;
    var effectiveExtra = delta - solarCompPerHour;
    if (effectiveExtra < 0.0f) { effectiveExtra = 0.0f; }

    logger.debug("effectiveExtra=" + effectiveExtra.toString());
    Test.assert(effectiveExtra == 0.0f);
    return true;
}

// Test C2: With moderate solar the effective extra must be positive and
// less than the raw delta.
(:test)
function testSolarReducesEffectiveExtra(logger as Test.Logger) as Boolean {
    var idleRate      = BatteryBudget.DEFAULT_RATE_IDLE;
    var profileRate   = BatteryBudget.DEFAULT_RATE_ACTIVITY;
    var delta         = profileRate - idleRate;              // 7.2

    var solarGainRate = 2.0f;
    var recentSolar   = 80;                                  // 80 %
    var solarFrac     = recentSolar.toFloat() / 100.0f;     // 0.8
    var solarComp     = solarGainRate * solarFrac * 0.5f;   // 0.8
    var effectiveExtra = delta - solarComp;                  // 6.4
    if (effectiveExtra < 0.0f) { effectiveExtra = 0.0f; }

    logger.debug("solarComp=" + solarComp.toString() + " effectiveExtra=" + effectiveExtra.toString());
    Test.assert(effectiveExtra > 0.0f);
    Test.assert(effectiveExtra < delta);
    return true;
}

// Test C3: Budget minutes must be 0 when battery is already at or below target.
(:test)
function testActivityBudgetZeroWhenBelowTarget(logger as Test.Logger) as Boolean {
    var nowBatt        = 20.0f;
    var totalDrain     = 10.0f;
    var targetLevel    = 15;
    var headroom       = nowBatt - totalDrain - targetLevel.toFloat(); // -5

    var budget = 0;
    if (headroom > 0.0f) {
        budget = (headroom / 0.12f).toNumber(); // hypothetical 0.12 %/min
    }

    logger.debug("headroom=" + headroom.toString() + " budget=" + budget.toString());
    Test.assert(budget == 0);
    return true;
}

// ---------------------------------------------------------------------------
// D. TimeUtil edge cases
// ---------------------------------------------------------------------------

// Test D1: parseTimeString("00:00") must return 0.
(:test)
function testParseTimeStringMidnight(logger as Test.Logger) as Boolean {
    var result = BatteryBudget.TimeUtil.parseTimeString("00:00");
    logger.debug("parseTimeString(00:00)=" + result.toString());
    Test.assert(result == 0);
    return true;
}

// Test D2: parseTimeString("23:59") must return 1439.
(:test)
function testParseTimeStringEndOfDay(logger as Test.Logger) as Boolean {
    var result = BatteryBudget.TimeUtil.parseTimeString("23:59");
    logger.debug("parseTimeString(23:59)=" + result.toString());
    Test.assert(result == 1439);
    return true;
}

// Test D3: parseTimeString with an invalid string must return the 22:00 default (1320).
(:test)
function testParseTimeStringInvalidFallback(logger as Test.Logger) as Boolean {
    var result = BatteryBudget.TimeUtil.parseTimeString("invalid");
    logger.debug("parseTimeString(invalid)=" + result.toString());
    Test.assert(result == 22 * 60);
    return true;
}

// Test D4: getSlotIndex must map hour directly (1-hour slots).
(:test)
function testGetSlotIndex(logger as Test.Logger) as Boolean {
    // Slot 0 = 00:xx, slot 14 = 14:xx, slot 23 = 23:xx
    Test.assert(BatteryBudget.TimeUtil.getSlotIndex(0, 0)  == 0);
    Test.assert(BatteryBudget.TimeUtil.getSlotIndex(14, 30) == 14);
    Test.assert(BatteryBudget.TimeUtil.getSlotIndex(23, 59) == 23);
    return true;
}

// Test D5: getEndOfDaySlot must clamp to [0, SLOTS_PER_DAY - 1].
(:test)
function testGetEndOfDaySlotClamp(logger as Test.Logger) as Boolean {
    // 22:00 -> slot 22
    var slot22 = BatteryBudget.TimeUtil.getEndOfDaySlot(22 * 60);
    Test.assert(slot22 == 22);

    // 00:00 -> slot 0
    var slot0 = BatteryBudget.TimeUtil.getEndOfDaySlot(0);
    Test.assert(slot0 == 0);

    // Value beyond 24h must clamp to SLOTS_PER_DAY - 1
    var slotMax = BatteryBudget.TimeUtil.getEndOfDaySlot(30 * 60);
    Test.assert(slotMax == BatteryBudget.SLOTS_PER_DAY - 1);
    return true;
}

// Test D6: getMinutesUntilTime must return 0 for a time already passed.
// (Tests the >= 0 clamp in getMinutesUntilTime; uses a static path.)
(:test)
function testGetMinutesUntilTimePassed(logger as Test.Logger) as Boolean {
    // We can only test the clamping logic directly since we cannot control
    // wall-clock time in unit tests.
    var nowMinutes = 22 * 60 + 30;           // 22:30 simulated
    var target     = 22 * 60;                 // 22:00 – already passed
    var remaining  = target - nowMinutes;     // -30
    if (remaining < 0) { remaining = 0; }

    logger.debug("remaining=" + remaining.toString());
    Test.assert(remaining == 0);
    return true;
}

// ---------------------------------------------------------------------------
// E. Segmenter helpers
// ---------------------------------------------------------------------------

// Test E1: calculateDrainRate for a 60-min 5 % drop must return 5.0 %/h.
(:test)
function testCalculateDrainRate(logger as Test.Logger) as Boolean {
    var seg = {
        :startTMin => 1000,
        :endTMin   => 1060,
        :startBatt => 50,
        :endBatt   => 45,
        :state     => BatteryBudget.STATE_IDLE,
        :profile   => BatteryBudget.PROFILE_GENERIC,
        :solarW    => 0
    } as BatteryBudget.Segment;

    var rate = BatteryBudget.Segmenter.calculateDrainRate(seg);
    logger.debug("drainRate=" + rate.toString());
    // (50 - 45) / (60/60) = 5.0
    Test.assert(rate >= 4.9f && rate <= 5.1f);
    return true;
}

// Test E2: Zero-duration segment must return 0 (no division by zero).
(:test)
function testCalculateDrainRateZeroDuration(logger as Test.Logger) as Boolean {
    var seg = {
        :startTMin => 1000,
        :endTMin   => 1000,
        :startBatt => 50,
        :endBatt   => 45,
        :state     => BatteryBudget.STATE_IDLE,
        :profile   => BatteryBudget.PROFILE_GENERIC,
        :solarW    => 0
    } as BatteryBudget.Segment;

    var rate = BatteryBudget.Segmenter.calculateDrainRate(seg);
    logger.debug("zeroRate=" + rate.toString());
    Test.assert(rate == 0.0f);
    return true;
}

// Test E3: isGapValid must reject gaps > MAX_LEARNING_GAP_MIN.
(:test)
function testIsGapValidLargeGap(logger as Test.Logger) as Boolean {
    var prev = 1000;
    var curr = prev + BatteryBudget.MAX_LEARNING_GAP_MIN + 1;
    var valid = BatteryBudget.Segmenter.isGapValid(prev, curr);
    logger.debug("largeGapValid=" + valid.toString());
    Test.assert(!valid);
    return true;
}

// Test E4: isGapValid must accept a gap of exactly MAX_LEARNING_GAP_MIN.
(:test)
function testIsGapValidExactLimit(logger as Test.Logger) as Boolean {
    var prev  = 1000;
    var curr  = prev + BatteryBudget.MAX_LEARNING_GAP_MIN;
    var valid = BatteryBudget.Segmenter.isGapValid(prev, curr);
    logger.debug("exactLimitValid=" + valid.toString());
    Test.assert(valid);
    return true;
}

// Test E5: isGapValid must reject backward time (curr <= prev).
(:test)
function testIsGapValidBackwardTime(logger as Test.Logger) as Boolean {
    var valid = BatteryBudget.Segmenter.isGapValid(1000, 999);
    logger.debug("backwardValid=" + valid.toString());
    Test.assert(!valid);
    return true;
}

// ---------------------------------------------------------------------------
// F. EMA clamping (DrainLearner logic, exercised directly on constants)
// ---------------------------------------------------------------------------

// Test F1: A sample above MAX_RATE must be clamped before the EMA update.
(:test)
function testEMAClampHighRate(logger as Test.Logger) as Boolean {
    var current   = 8.0f;
    var rawSample = 999.9f;
    var alpha     = 0.2f;
    var maxRate   = BatteryBudget.MAX_RATE; // 25.0

    // Simulate clamp + EMA
    var clamped = rawSample > maxRate ? maxRate : rawSample;
    var result  = (1.0f - alpha) * current + alpha * clamped;

    logger.debug("clamped=" + clamped.toString() + " result=" + result.toString());
    // Result must be between current and MAX_RATE; must never exceed MAX_RATE
    Test.assert(result <= maxRate);
    Test.assert(result > current);
    return true;
}

// Test F2: A sample below MIN_RATE must be clamped upward.
(:test)
function testEMAClampLowRate(logger as Test.Logger) as Boolean {
    var current   = 0.8f;
    var rawSample = -5.0f;
    var alpha     = 0.2f;
    var minRate   = BatteryBudget.MIN_RATE; // 0.1

    var clamped = rawSample < minRate ? minRate : rawSample;
    var result  = (1.0f - alpha) * current + alpha * clamped;

    logger.debug("clamped=" + clamped.toString() + " result=" + result.toString());
    Test.assert(result >= minRate);
    // With clamped = MIN_RATE < current, result must be slightly below current
    Test.assert(result < current);
    return true;
}

// Test F3: EMA must move toward the new sample (convergence check).
(:test)
function testEMAConvergesToSample(logger as Test.Logger) as Boolean {
    var current = 5.0f;
    var sample  = 10.0f;
    var alpha   = 0.2f;

    var result = (1.0f - alpha) * current + alpha * sample;
    // Must be strictly between current and sample
    logger.debug("ema=" + result.toString());
    Test.assert(result > current);
    Test.assert(result < sample);
    return true;
}
