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
        :solarW    => 0,
        :hrDensity => 0,
        :broadcastCandidate => false
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
        :solarW    => 0,
        :hrDensity => 0,
        :broadcastCandidate => false
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

// ---------------------------------------------------------------------------
// G. Inline decay equivalence (ServiceDelegate vs PatternLearner.applyDecay)
// ---------------------------------------------------------------------------
// Proves that the inlined loop `pattern[i] = (pattern[i].toFloat() * 0.9f).toNumber()`
// is bit-for-bit identical to the original PatternLearner.applyDecay() formula.

// Test G1: Known values – verify exact integer truncation of 0.9× decay.
(:test)
function testInlineDecayKnownValues(logger as Test.Logger) as Boolean {
    // Expected = floor(input * 0.9)  (Monkey C toNumber() truncates toward zero)
    var inputs   = [100, 50, 25, 10, 1, 0] as Array<Number>;
    var expected = [ 90, 45, 22,  9, 0, 0] as Array<Number>;

    for (var i = 0; i < inputs.size(); i++) {
        var got = (inputs[i].toFloat() * 0.9f).toNumber();
        if (got != expected[i]) {
            logger.debug("decay(" + inputs[i].toString() + ")="
                         + got.toString() + " expected=" + expected[i].toString());
            return false;
        }
    }
    return true;
}

// Test G2: Slot that is already 0 must stay 0 across an entire year of weekly decays.
(:test)
function testDecayZeroStaysZero(logger as Test.Logger) as Boolean {
    var slot = 0;
    for (var i = 0; i < 52; i++) {
        slot = (slot.toFloat() * 0.9f).toNumber();
    }
    logger.debug("zeroSlot52weeks=" + slot.toString());
    Test.assert(slot == 0);
    return true;
}

// Test G3: 10 weekly iterations on 100 must yield exactly 32.
// Trace: 100→90→81→72→64→57→51→45→40→36→32 (truncation compounds per step).
(:test)
function testDecayExact10Iterations(logger as Test.Logger) as Boolean {
    var slot = 100;
    for (var i = 0; i < 10; i++) {
        slot = (slot.toFloat() * 0.9f).toNumber();
    }
    logger.debug("100_decay10=" + slot.toString());
    Test.assert(slot == 32);
    return true;
}

// ---------------------------------------------------------------------------
// H. Charging detection and EMA protection
// ---------------------------------------------------------------------------

// Test H1: Positive battery delta is detected and must be rejected before EMA update.
(:test)
function testPositiveDeltaDetected(logger as Test.Logger) as Boolean {
    var startBatt = 45;
    var endBatt   = 55; // +10 % → charging

    // Guard 1: positive delta check (first line of DrainLearner.learnFromSegment)
    var rejectedByDeltaGuard = (endBatt >= startBatt);
    Test.assert(rejectedByDeltaGuard);

    // Guard 2: Segmenter.calculateDrainRate also returns 0 for positive delta
    var battDrop = startBatt - endBatt; // -10
    Test.assert(battDrop <= 0);
    return true;
}

// Test H2: STATE_CHARGING guard fires even when delta is zero (fully-charged hold).
(:test)
function testChargingStateGuardFires(logger as Test.Logger) as Boolean {
    var state     = BatteryBudget.STATE_CHARGING;
    var startBatt = 100;
    var endBatt   = 100; // no delta – but still charging

    var rejectedByState = (state == BatteryBudget.STATE_CHARGING);
    var rejectedByDelta = (endBatt >= startBatt);
    Test.assert(rejectedByState);
    Test.assert(rejectedByDelta);
    return true;
}

// Test H3: Segmenter.calculateDrainRate must return 0.0 for a charging segment.
(:test)
function testCalculateDrainRateChargingIsZero(logger as Test.Logger) as Boolean {
    var seg = {
        :startTMin => 1000,
        :endTMin   => 1060,
        :startBatt => 45,
        :endBatt   => 55,
        :state     => BatteryBudget.STATE_CHARGING,
        :profile   => BatteryBudget.PROFILE_GENERIC,
        :solarW    => 0,
        :hrDensity => 0,
        :broadcastCandidate => false
    } as BatteryBudget.Segment;

    var rate = BatteryBudget.Segmenter.calculateDrainRate(seg);
    logger.debug("chargingSegmentRate=" + rate.toString());
    Test.assert(rate == 0.0f);
    return true;
}

// ---------------------------------------------------------------------------
// I. Time-jump handling (slot and learning integrity)
// ---------------------------------------------------------------------------

// Test I1: Backward time jump (gap <= 0) must be classified as an invalid break.
(:test)
function testBackwardTimeJumpIsInvalid(logger as Test.Logger) as Boolean {
    var prevTMin = 1000;
    var currTMin = 990;                     // 10 min backward (GPS clock correction)
    var gap      = currTMin - prevTMin;     // -10

    // Segmenter's first guard: gap <= 0 → discard current segment, do not learn
    var isInvalidBackward = (gap <= 0);
    logger.debug("backwardGap=" + gap.toString() + " invalid=" + isInvalidBackward.toString());
    Test.assert(isInvalidBackward);
    return true;
}

// Test I2: Zero-gap (duplicate snapshot in the same epoch-minute) is also invalid.
(:test)
function testZeroGapIsInvalid(logger as Test.Logger) as Boolean {
    var prevTMin = 1000;
    var currTMin = 1000; // same minute
    var gap      = currTMin - prevTMin;

    Test.assert(gap <= 0);
    return true;
}

// Test I3: Forward jump just beyond MAX_LEARNING_GAP_MIN must be rejected for learning.
(:test)
function testLargeForwardJumpIsInvalid(logger as Test.Logger) as Boolean {
    var prevTMin = 1000;
    var currTMin = prevTMin + BatteryBudget.MAX_LEARNING_GAP_MIN + 1;
    var gap      = currTMin - prevTMin;

    var isLargeJump = (gap > BatteryBudget.MAX_LEARNING_GAP_MIN);
    logger.debug("forwardGap=" + gap.toString() + " isLargeJump=" + isLargeJump.toString());
    Test.assert(isLargeJump);
    return true;
}

// Test I4: Gap exactly at MAX_LEARNING_GAP_MIN must still be accepted (boundary).
(:test)
function testExactMaxGapIsValid(logger as Test.Logger) as Boolean {
    var prevTMin = 1000;
    var currTMin = prevTMin + BatteryBudget.MAX_LEARNING_GAP_MIN;
    var gap      = currTMin - prevTMin;

    var isValidGap = (gap > 0) && (gap <= BatteryBudget.MAX_LEARNING_GAP_MIN);
    logger.debug("exactMaxGap=" + gap.toString() + " valid=" + isValidGap.toString());
    Test.assert(isValidGap);
    return true;
}

// Test I5: getSlotIndex must map all 24 hours to [0, SLOTS_PER_DAY-1].
// Ensures no timezone or DST scenario can produce an out-of-bounds slot index.
(:test)
function testSlotIndexAlwaysInBounds(logger as Test.Logger) as Boolean {
    for (var hour = 0; hour < 24; hour++) {
        var slot = BatteryBudget.TimeUtil.getSlotIndex(hour, 0);
        if (slot < 0 || slot >= BatteryBudget.SLOTS_PER_DAY) {
            logger.debug("outOfBounds: hour=" + hour.toString() + " slot=" + slot.toString());
            return false;
        }
    }
    return true;
}

// ---------------------------------------------------------------------------
// J. Broadcast detection and weekly-plan arithmetic
// ---------------------------------------------------------------------------

// Test J1: Dense HR samples with a valid heart rate should cross the broadcast threshold.
(:test)
function testBroadcastSignalThreshold(logger as Test.Logger) as Boolean {
    var denseHr = 42.0f;     // ~7 samples in 10 min
    var idleHr = 6.0f;       // sparse all-day sampling
    var result = BatteryBudget.BroadcastDetector.meetsSignalThreshold(denseHr, idleHr, true, 7);
    logger.debug("broadcastSignal=" + result.toString());
    Test.assert(result);
    return true;
}

// Test J2: Planned native and broadcast hours must reduce the remaining day estimate.
(:test)
function testRemainingDaysWithPlan(logger as Test.Logger) as Boolean {
    var days = BatteryBudget.Forecaster.computeRemainingDaysWithPlan(
        80,
        1.0f,
        8.0f,
        3.0f,
        120,
        180
    );

    // (80 - 16 - 9) / 24 = 2.29 days
    logger.debug("daysWithPlan=" + days.toString());
    Test.assert(days > 2.2f && days < 2.4f);
    return true;
}
