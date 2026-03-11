import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

module BatteryBudget {
    
    class Forecaster {
        
        private static var _sharedInstance as Forecaster?;

        private var _storage as StorageManager;
        private var _drainLearner as DrainLearner;
        private var _patternLearner as PatternLearner;
        private const MIN_VALID_RATE_SAMPLES = 3;
        // Gap threshold for backfilling on startup (minutes)
        private const BACKFILL_THRESHOLD_MIN = 30;
        // Maximum gap to backfill; beyond 24 h the data is too stale to be reliable
        private const BACKFILL_MAX_GAP_MIN = 1440;

        function initialize() {
            _storage = StorageManager.getInstance();
            _drainLearner = new DrainLearner();
            _patternLearner = new PatternLearner();
            _backfillGapIfNeeded();
        }

        static function getSharedInstance() as Forecaster {
            if (_sharedInstance == null) {
                _sharedInstance = new Forecaster();
            }
            return _sharedInstance as Forecaster;
        }

        function getDisplayForecast() as ForecastResult {
            return hasMinimumConfidence() ? forecast() : getSimpleForecast();
        }
        
        // Generate forecast for end of day
        function forecast() as ForecastResult {
            var settings = _storage.getSettings();
            
            // Get current state - one call to getLocalTimeInfo() covers slot, weekday, and partial-slot math
            var nowBatt = getBatteryPercent();
            var localInfo = TimeUtil.getLocalTimeInfo();
            var nowMinutes = TimeUtil.getMinutesSinceMidnight(localInfo);
            var weekday = localInfo.day_of_week - 1;
            if (weekday < 0) { weekday = 0; }
            if (weekday > 6) { weekday = 6; }
            var currentSlot = TimeUtil.getSlotIndex(localInfo.hour, localInfo.min);
            var endOfDayMinutes = _storage.getEndOfDayMinutes();
            var endOfDaySlotRangeEnd = TimeUtil.getEndOfDaySlotRangeEnd(endOfDayMinutes);
            var remainingMinutes = endOfDayMinutes - nowMinutes;
            if (remainingMinutes < 0) {
                remainingMinutes = 0;
            }

            // Get learned rates
            var idleRate = getSafeIdleRate();
            var activityRate = getSafeActivityRate();

            // Read target level from settings (default: compile-time constant)
            var targetLevelSetting = settings[:targetLevel];
            var targetLevelVal = (targetLevelSetting instanceof Number)
                ? targetLevelSetting as Number
                : TARGET_LEVEL;

            // Get factors from settings
            var conservativeFactor = settings[:conservativeFactor] as Float;
            var optimisticFactor = settings[:optimisticFactor] as Float;

            // Calculate drain for remaining slots.
            // The current slot may be partially elapsed - only count remaining minutes.

            var totalDrainTypical = 0.0f;
            var solarMinutesRemaining = 0;

            if (remainingMinutes > 0) {
                for (var slot = currentSlot; slot < SLOTS_PER_DAY; slot++) {
                    var slotDurationMin = TimeUtil.getSlotOverlapMinutes(slot, nowMinutes, endOfDayMinutes);
                    if (slotDurationMin <= 0) {
                        continue;
                    }
                    solarMinutesRemaining += slotDurationMin;

                    var expectedActivityMin = _patternLearner.getExpectedActivityMinutes(weekday, slot);
                    // Scale proportionally when the slot is only partially remaining
                    if (slotDurationMin < SLOT_DURATION_MIN) {
                        expectedActivityMin = (expectedActivityMin * slotDurationMin / SLOT_DURATION_MIN);
                    }
                    var expectedIdleMin = slotDurationMin - expectedActivityMin;

                    // Ensure non-negative
                    if (expectedIdleMin < 0) {
                        expectedIdleMin = 0;
                        expectedActivityMin = slotDurationMin;
                    }

                    // Sleep-window: apply reduced idle rate when no significant activity is expected.
                    // Uses the shared sleep-window source (UserProfile > settings > constants).
                    // Pattern data takes priority: if the user habitually trains at night (e.g.
                    // night shift), learned activity minutes override the sleep discount.
                    var effectiveIdleRate = idleRate;
                    var isSleepSlot = TimeUtil.isWithinSleepWindow(slot, settings);
                    if (isSleepSlot && expectedActivityMin < 15) {
                        effectiveIdleRate = DEFAULT_RATE_SLEEP;
                    }

                    // Calculate drain for this slot
                    var slotDrain =
                        (expectedActivityMin.toFloat() / 60.0f) * activityRate +
                        (expectedIdleMin.toFloat() / 60.0f) * effectiveIdleRate;

                    totalDrainTypical += slotDrain;
                }
            }

            // Post-charge reset trigger: when the battery rose since the last recorded
            // snapshot a charge cycle just ended.  The recentSolar EMA stopped updating
            // during charging (charging segments are filtered by DrainLearner), so its
            // cached value may be stale or reflect plugged-in conditions rather than
            // real sun exposure.  Suppress the solar bonus for this one forecast cycle
            // so the drain curve resets cleanly from the verified post-charge battery.
            var lastSnap = _storage.getLastSnapshot();
            var isPostCharge = (lastSnap != null)
                && ((lastSnap[:state] == STATE_CHARGING)
                    || ((lastSnap[:battPct] as Number) < nowBatt));

            var solarBonusTypical = 0.0f;
            var solarBonusOptimistic = 0.0f;
            var rates = _storage.getDrainRates();
            var solarGainRate = rates[:solarGain] as Float;
            var recentSolar = rates[:recentSolar] as Number;
            if (!isPostCharge && solarGainRate > 0.0f && recentSolar > 10) {
                var solarFraction = recentSolar.toFloat() / 100.0f;
                var solarHoursRemaining = solarMinutesRemaining.toFloat() / 60.0f;
                var totalSolarGain = solarGainRate * solarFraction * solarHoursRemaining;
                solarBonusTypical = totalSolarGain * 0.5f;   // 50% of expected gain (typical)
                solarBonusOptimistic = totalSolarGain;        // full gain (optimistic)
                // conservative gets no solar bonus
            }

            // Calculate end of day battery levels
            var endBattTypical = nowBatt.toFloat() - totalDrainTypical + solarBonusTypical;
            var endBattConservative = nowBatt.toFloat() - (totalDrainTypical * conservativeFactor);
            var endBattOptimistic = nowBatt.toFloat() - (totalDrainTypical * optimisticFactor) + solarBonusOptimistic;

            // Clamp to 0-100
            endBattTypical = clampBattery(endBattTypical);
            endBattConservative = clampBattery(endBattConservative);
            endBattOptimistic = clampBattery(endBattOptimistic);
            
            // Calculate risk level
            var riskThresholdRed = settings[:riskThresholdRed] as Number;
            var riskThresholdYellow = settings[:riskThresholdYellow] as Number;
            var risk = calculateRisk(endBattConservative.toNumber(), riskThresholdRed, riskThresholdYellow);
            
            // Calculate confidence
            var confidence = calculateConfidence();
            
            // Find next activity window
            var nextWindow = _patternLearner.findNextActivityWindow(weekday, currentSlot, endOfDaySlotRangeEnd);
            var nextActivityTime = null;
            var nextActivityDuration = null;
            var nextActivityDrain = null;

            if (nextWindow != null) {
                nextActivityTime = nextWindow[:startSlot] as Number;
                nextActivityDuration = (nextWindow[:totalMinutes] as Number);
                nextActivityDrain = (nextActivityDuration.toFloat() / 60.0f) * activityRate;
            }

            // Activity Budget: minutes the user can still train before EOD battery drops to
            // targetLevelVal. Uses the last snapshot's profile for a profile-specific drain
            // rate and applies 50% of the current solar gain as a conservative compensation.
            var currentProfile = PROFILE_GENERIC;
            if (lastSnap != null) {
                currentProfile = lastSnap[:profile] as Profile;
            }
            var profileRate = getSafeProfileRate(currentProfile, activityRate);

            // Solar compensation: each hour of activity under sun reduces the net drain.
            // Suppressed post-charge for the same reason as solarBonusTypical above.
            // We credit only 50 % of the expected gain to stay conservative.
            var solarCompPerHour = 0.0f;
            if (!isPostCharge && solarGainRate > 0.0f && recentSolar > 20) {
                var solarFrac = recentSolar.toFloat() / 100.0f;
                solarCompPerHour = solarGainRate * solarFrac * 0.5f;
            }
            // Effective extra drain per hour of activity vs idle (never negative)
            var effectiveExtraPerHour = (profileRate - idleRate) - solarCompPerHour;
            if (effectiveExtraPerHour < 0.0f) { effectiveExtraPerHour = 0.0f; }

            var remainingActivityMinutes = calculateActivityBudget(
                nowBatt.toFloat(), totalDrainTypical, effectiveExtraPerHour,
                targetLevelVal, remainingMinutes);

            return {
                :typical => endBattTypical.toNumber(),
                :conservative => endBattConservative.toNumber(),
                :optimistic => endBattOptimistic.toNumber(),
                :risk => risk,
                :confidence => confidence,
                :nextActivityTime => nextActivityTime,
                :nextActivityDuration => nextActivityDuration,
                :nextActivityDrain => nextActivityDrain != null ? nextActivityDrain.toNumber() : null,
                :remainingActivityMinutes => remainingActivityMinutes,
                :solarSuppressed => isPostCharge
            } as ForecastResult;
        }

        // Get current battery percentage
        private function getBatteryPercent() as Number {
            var stats = System.getSystemStats();
            if (stats has :battery) {
                var batt = stats.battery;
                if (batt != null) {
                    return batt.toNumber();
                }
            }
            return 50;
        }

        // Backfill the learning gap that arises after a watch restart or system update.
        // If the time since the last snapshot exceeds BACKFILL_THRESHOLD_MIN, synthetic
        // segments are constructed from PatternLearner historical averages and fed into
        // DrainLearner so that learned drain rates reflect the missed period.
        // PatternLearner itself is NOT updated — we must not reinforce the pattern with
        // synthetic data.
        private function _backfillGapIfNeeded() as Void {
            var lastSnap = _storage.getLastSnapshot();
            if (lastSnap == null) {
                return;
            }

            var nowTMin  = TimeUtil.nowEpochMinutes();
            var lastTMin = lastSnap[:tMin] as Number;
            var gapMin   = nowTMin - lastTMin;

            // Only backfill meaningful, believable gaps
            if (gapMin <= BACKFILL_THRESHOLD_MIN || gapMin > BACKFILL_MAX_GAP_MIN) {
                return;
            }

            var lastBatt = lastSnap[:battPct] as Number;
            var nowBatt  = getBatteryPercent();

            // Battery rose → charging session; skip (isPostCharge logic handles this)
            if (lastBatt <= nowBatt) {
                return;
            }

            var totalBattDelta = (lastBatt - nowBatt).toFloat();

            // Walk through each slot in the gap and sum up PatternLearner expectations.
            // We advance in SLOT_DURATION_MIN (60-min) steps; at most 24 iterations.
            var totalExpectedIdleMin     = 0;
            var totalExpectedActivityMin = 0;

            var curMin = lastTMin;
            while (curMin < nowTMin) {
                var weekday = TimeUtil.getWeekdayFromEpochMin(curMin);
                var slot    = TimeUtil.getSlotFromEpochMin(curMin);

                var nextMin = curMin + SLOT_DURATION_MIN;
                if (nextMin > nowTMin) { nextMin = nowTMin; }
                var slotActualMin = nextMin - curMin;

                // Prorate expected activity to the actual minutes we spent in this slot
                var expectedActMin = _patternLearner.getExpectedActivityMinutes(weekday, slot)
                                     * slotActualMin / SLOT_DURATION_MIN;
                if (expectedActMin > slotActualMin) { expectedActMin = slotActualMin; }
                if (expectedActMin < 0)             { expectedActMin = 0; }

                totalExpectedActivityMin += expectedActMin;
                totalExpectedIdleMin     += (slotActualMin - expectedActMin);

                curMin = nextMin;
            }

            // Estimate how the battery delta splits between idle and activity time,
            // weighted by their expected drain contributions.
            var idleRate = getSafeIdleRate();
            var actRate  = getSafeActivityRate();

            var expectedIdleDrain = idleRate * totalExpectedIdleMin.toFloat() / 60.0f;
            var expectedActDrain  = actRate  * totalExpectedActivityMin.toFloat() / 60.0f;
            var expectedTotal     = expectedIdleDrain + expectedActDrain;

            // Feed synthetic idle segment into DrainLearner
            if (totalExpectedIdleMin > 0) {
                var idleDelta = (expectedTotal > 0.0f)
                    ? totalBattDelta * (expectedIdleDrain / expectedTotal)
                    : totalBattDelta;
                var idleEndBatt = lastBatt - idleDelta.toNumber();
                if (idleEndBatt < 0)       { idleEndBatt = 0; }
                if (idleEndBatt < lastBatt) {
                    _drainLearner.learnFromSegment({
                        :startTMin => lastTMin,
                        :endTMin   => lastTMin + totalExpectedIdleMin,
                        :startBatt => lastBatt,
                        :endBatt   => idleEndBatt,
                        :state     => STATE_IDLE,
                        :profile   => PROFILE_GENERIC,
                        :solarW    => 0,
                        :hrDensity => 0,
                        :broadcastCandidate => false
                    } as Segment);
                }
            }

            // Feed synthetic activity segment only when meaningful activity is expected
            if (totalExpectedActivityMin >= 10 && expectedTotal > 0.0f) {
                var actDelta   = totalBattDelta * (expectedActDrain / expectedTotal);
                var actEndBatt = lastBatt - actDelta.toNumber();
                if (actEndBatt < 0)        { actEndBatt = 0; }
                if (actEndBatt < lastBatt) {
                    _drainLearner.learnFromSegment({
                        :startTMin => lastTMin,
                        :endTMin   => lastTMin + totalExpectedActivityMin,
                        :startBatt => lastBatt,
                        :endBatt   => actEndBatt,
                        :state     => STATE_ACTIVITY,
                        :profile   => PROFILE_GENERIC,
                        :solarW    => 0,
                        :hrDensity => 0,
                        :broadcastCandidate => false
                    } as Segment);
                }
            }
        }

        // Calculate activity budget: how many minutes of activity the user can still do
        // before the typical end-of-day battery would fall below targetLevel.
        // effectiveExtraPerHour = (profileRate - idleRate) already adjusted for solar gain.
        private function calculateActivityBudget(nowBatt as Float, totalDrain as Float,
                                                 effectiveExtraPerHour as Float,
                                                 targetLevel as Number,
                                                 remainingMinutes as Number) as Number {
            if (remainingMinutes <= 0) {
                return 0;
            }

            var headroom = nowBatt - totalDrain - targetLevel.toFloat();
            if (headroom <= 0.0f) {
                return 0;
            }

            var maxMin = remainingMinutes;
            if (effectiveExtraPerHour <= 0.0f) {
                return maxMin;
            }

            var extraPerMinute = effectiveExtraPerHour / 60.0f;
            if (extraPerMinute <= 0.0f) {
                // Activity costs no more than idle (e.g. strong solar) – unconstrained
                return maxMin;
            }

            var budgetMin = (headroom / extraPerMinute).toNumber();
            if (budgetMin > maxMin) { budgetMin = maxMin; }
            if (budgetMin < 0)      { budgetMin = 0; }
            return budgetMin;
        }

        static function calculateRemainingPlannedMinutes(plannedMinutes as Number, usedMinutes as Number) as Number {
            var remaining = plannedMinutes - usedMinutes;
            if (remaining < 0) {
                return 0;
            }
            return remaining;
        }

        static function computeRemainingDaysWithPlan(currentBattery as Number,
                                                     idleRate as Float,
                                                     nativeRate as Float,
                                                     broadcastRate as Float,
                                                     plannedNativeMinutes as Number,
                                                     plannedBroadcastMinutes as Number) as Float {
            var baselineDailyDrain = idleRate * 24.0f;
            var plannedDrain = (plannedNativeMinutes.toFloat() / 60.0f) * nativeRate
                             + (plannedBroadcastMinutes.toFloat() / 60.0f) * broadcastRate;
            return Forecaster.calculateRemainingDays(currentBattery, baselineDailyDrain, plannedDrain);
        }

        static function calculateRemainingDays(currentBattery as Number,
                                               baselineDailyDrain as Float,
                                               plannedDrain as Float) as Float {
            if (baselineDailyDrain <= 0.0f) {
                return 0.0f;
            }

            var remaining = (currentBattery.toFloat() - plannedDrain) / baselineDailyDrain;
            if (remaining < 0.0f) {
                return 0.0f;
            }
            return remaining;
        }

        // Clamp battery to 0-100
        private function clampBattery(value as Float) as Float {
            if (value < 0.0f) {
                return 0.0f;
            }
            if (value > 100.0f) {
                return 100.0f;
            }
            return value;
        }
        
        // Calculate risk level
        private function calculateRisk(conservativeBatt as Number, redThreshold as Number, yellowThreshold as Number) as RiskLevel {
            if (conservativeBatt < redThreshold) {
                return RISK_HIGH;
            }
            if (conservativeBatt < yellowThreshold) {
                return RISK_MEDIUM;
            }
            return RISK_LOW;
        }
        
        // Calculate overall confidence
        private function calculateConfidence() as Float {
            var ratesConfidence = _drainLearner.getRatesConfidence();
            var patternConfidence = _patternLearner.getPatternConfidence();
            
            // Weight rates slightly higher
            return (ratesConfidence * 0.6f + patternConfidence * 0.4f);
        }
        
        // Check if we have enough confidence for full forecast
        function hasMinimumConfidence() as Boolean {
            return calculateConfidence() >= CONFIDENCE_THRESHOLD;
        }
        
        // Get simple idle-only forecast (for low confidence mode)
        function getSimpleForecast() as ForecastResult {
            var nowBatt = getBatteryPercent();
            var idleRate = getSafeIdleRate();
            
            var endOfDayMinutes = _storage.getEndOfDayMinutes();
            var minutesRemaining = TimeUtil.getMinutesUntilTime(endOfDayMinutes);
            var hoursRemaining = minutesRemaining.toFloat() / 60.0f;
            
            var drain = idleRate * hoursRemaining;

            // Apply solar gain (typical only; simple forecast is conservative by nature).
            // Same post-charge suppression as in forecast(): recentSolar may be stale
            // after a charging cycle, so suppress the bonus until we have a fresh reading.
            var solarBonus = 0.0f;
            var simplRates = _storage.getDrainRates();
            var simplSolarGainRate = simplRates[:solarGain] as Float;
            var simplRecentSolar = simplRates[:recentSolar] as Number;
            var simplLastSnap = _storage.getLastSnapshot();
            var simplIsPostCharge = (simplLastSnap != null)
                && ((simplLastSnap[:state] == STATE_CHARGING)
                    || ((simplLastSnap[:battPct] as Number) < nowBatt));
            if (!simplIsPostCharge && simplSolarGainRate > 0.0f && simplRecentSolar > 10) {
                var solarFraction = simplRecentSolar.toFloat() / 100.0f;
                solarBonus = simplSolarGainRate * solarFraction * hoursRemaining * 0.5f;
            }

            var endBatt = clampBattery(nowBatt.toFloat() - drain + solarBonus);
            
            var settings = _storage.getSettings();
            var riskThresholdRed = settings[:riskThresholdRed] as Number;
            var riskThresholdYellow = settings[:riskThresholdYellow] as Number;
            var risk = calculateRisk(endBatt.toNumber(), riskThresholdRed, riskThresholdYellow);
            var confidence = calculateConfidence();
            
            return {
                :typical => endBatt.toNumber(),
                :conservative => endBatt.toNumber(),
                :optimistic => endBatt.toNumber(),
                :risk => risk,
                :confidence => confidence,
                :nextActivityTime => null,
                :nextActivityDuration => null,
                :nextActivityDrain => null,
                :remainingActivityMinutes => 0,
                :solarSuppressed => simplIsPostCharge
            } as ForecastResult;
        }
        
        // Get days of data collected
        function getDaysCollected() as Number {
            var stats = _storage.getStats();
            var firstDataDay = stats.hasKey("firstDataDay") ? stats["firstDataDay"] as Number : 0;
            
            if (firstDataDay == 0) {
                return 0;
            }
            
            var nowMin = TimeUtil.nowEpochMinutes();
            var daysDiff = (nowMin - firstDataDay) / (24 * 60);
            return daysDiff.toNumber();
        }
        
        // Resolve sleep-window start hour.
        // Priority: UserProfile (if device exposes sleepTime as Duration) → app Setting → constant.
        // Get current battery for display
        function getCurrentBattery() as Number {
            return getBatteryPercent();
        }

        private function getSampleCountSafe(key as Symbol) as Number {
            try {
                var rates = _storage.getDrainRates();
                var counts = rates[:sampleCounts];
                if (counts != null && counts.hasKey(key) && counts[key] instanceof Number) {
                    return counts[key] as Number;
                }
            } catch (ex) {}
            return 0;
        }

        private function getSafeIdleRate() as Float {
            if (getSampleCountSafe(:idle) < MIN_VALID_RATE_SAMPLES) {
                return DEFAULT_RATE_IDLE;
            }

            try {
                var rate = _drainLearner.getIdleRate();
                if (rate >= MIN_RATE && rate <= MAX_RATE) {
                    return rate;
                }
            } catch (ex) {}
            return DEFAULT_RATE_IDLE;
        }

        private function getSafeActivityRate() as Float {
            try {
                var rate = _drainLearner.getActivityRate();
                if (rate >= MIN_RATE && rate <= MAX_RATE) {
                    return rate;
                }
            } catch (ex) {}
            return DEFAULT_RATE_ACTIVITY;
        }

        private function getSafeProfileRate(profile as Profile, fallback as Float) as Float {
            try {
                var rate = _drainLearner.getProfileRate(profile);
                if (rate >= MIN_RATE && rate <= MAX_RATE) {
                    return rate;
                }
            } catch (ex) {}
            return fallback;
        }
        
        // Get learned rates for display
        function getLearnedRatesDisplay() as Dictionary {
            var rates = _storage.getDrainRates();
            return {
                :idle => rates[:idle],
                :activity => rates[:activityGeneric],
                :broadcast => rates[:broadcast],
                :run => rates[:run],
                :bike => rates[:bike],
                :hike => rates[:hike]
            };
        }
        
        // Format risk level as string
        static function riskToString(risk as RiskLevel) as String {
            switch (risk) {
                case RISK_LOW:
                    return WatchUi.loadResource(Rez.Strings.RiskLow) as String;
                case RISK_MEDIUM:
                    return WatchUi.loadResource(Rez.Strings.RiskMedium) as String;
                case RISK_HIGH:
                    return WatchUi.loadResource(Rez.Strings.RiskHigh) as String;
                default:
                    return "?";
            }
        }
        
        // Get risk color
        static function riskToColor(risk as RiskLevel) as Number {
            switch (risk) {
                case RISK_LOW:
                    return 0x00FF00; // Green
                case RISK_MEDIUM:
                    return 0xFFFF00; // Yellow
                case RISK_HIGH:
                    return 0xFF0000; // Red
                default:
                    return 0xFFFFFF; // White
            }
        }
    }
}
