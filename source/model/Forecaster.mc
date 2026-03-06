import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.UserProfile;
import Toybox.WatchUi;

module BatteryBudget {
    
    class Forecaster {
        
        private var _storage as StorageManager;
        private var _drainLearner as DrainLearner;
        private var _patternLearner as PatternLearner;
        
        function initialize() {
            _storage = StorageManager.getInstance();
            _drainLearner = new DrainLearner();
            _patternLearner = new PatternLearner();
        }
        
        // Generate forecast for end of day
        function forecast() as ForecastResult {
            var settings = _storage.getSettings();
            
            // Get current state - one call to getLocalTimeInfo() covers slot, weekday, and partial-slot math
            var nowBatt = getBatteryPercent();
            var localInfo = TimeUtil.getLocalTimeInfo();
            var weekday = localInfo.day_of_week - 1;
            if (weekday < 0) { weekday = 0; }
            if (weekday > 6) { weekday = 6; }
            var currentSlot = TimeUtil.getSlotIndex(localInfo.hour, localInfo.min);
            // With 60-min slots, remaining = full minutes left in the current hour
            var remainingInCurrentSlot = SLOT_DURATION_MIN - localInfo.min;
            var endOfDayMinutes = _storage.getEndOfDayMinutes();
            var endOfDaySlot = TimeUtil.getEndOfDaySlot(endOfDayMinutes);

            // Get learned rates
            var idleRate = _drainLearner.getIdleRate();
            var activityRate = _drainLearner.getActivityRate();

            // Resolve dynamic sleep window (UserProfile > app settings > compile-time constant)
            var sleepStartHour = resolveSleepStartHour();
            var sleepEndHour   = resolveSleepEndHour();

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

            if (currentSlot < endOfDaySlot) {
                for (var slot = currentSlot; slot < endOfDaySlot && slot < SLOTS_PER_DAY; slot++) {
                    var slotDurationMin = (slot == currentSlot) ? remainingInCurrentSlot : SLOT_DURATION_MIN;
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
                    // Uses dynamically resolved hours (UserProfile > settings > constants).
                    // Pattern data takes priority: if the user habitually trains at night (e.g.
                    // night shift), learned activity minutes override the sleep discount.
                    var effectiveIdleRate = idleRate;
                    var isSleepSlot = (slot >= sleepStartHour || slot < sleepEndHour);
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

            // Apply solar gain correction (only when learned and recent solar is meaningful)
            var solarBonusTypical = 0.0f;
            var solarBonusOptimistic = 0.0f;
            var rates = _storage.getDrainRates();
            var solarGainRate = rates[:solarGainRate];
            var recentSolar = rates[:recentSolar] as Number;
            if (solarGainRate != null && recentSolar > 10) {
                var solarFraction = recentSolar.toFloat() / 100.0f;
                var solarHoursRemaining = solarMinutesRemaining.toFloat() / 60.0f;
                var totalSolarGain = (solarGainRate as Float) * solarFraction * solarHoursRemaining;
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
            var nextWindow = _patternLearner.findNextActivityWindow(weekday, currentSlot, endOfDaySlot);
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
            var lastSnapshot = _storage.getLastSnapshot();
            if (lastSnapshot != null) {
                currentProfile = lastSnapshot[:profile] as Profile;
            }
            var profileRate = _drainLearner.getProfileRate(currentProfile);

            // Solar compensation: each hour of activity under sun reduces the net drain.
            // We credit only 50 % of the expected gain to stay conservative.
            var solarCompPerHour = 0.0f;
            if (solarGainRate != null && recentSolar > 20) {
                var solarFrac = recentSolar.toFloat() / 100.0f;
                solarCompPerHour = (solarGainRate as Float) * solarFrac * 0.5f;
            }
            // Effective extra drain per hour of activity vs idle (never negative)
            var effectiveExtraPerHour = (profileRate - idleRate) - solarCompPerHour;
            if (effectiveExtraPerHour < 0.0f) { effectiveExtraPerHour = 0.0f; }

            var remainingActivityMinutes = calculateActivityBudget(
                nowBatt.toFloat(), totalDrainTypical, effectiveExtraPerHour,
                targetLevelVal, endOfDaySlot, currentSlot);

            var abnormalDrain = _drainLearner.isAbnormalDrain();
            var dataPointsPerProfile = _drainLearner.getProfileSampleCounts();

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
                :abnormalDrain => abnormalDrain,
                :dataPointsPerProfile => dataPointsPerProfile
            } as ForecastResult;
        }

        // "What-If" planner: compute the forecast impact of adding a hypothetical activity.
        // Returns a modified ForecastResult showing EOD battery after the planned session.
        // The extra drain = (profileRate - idleRate) × durationMinutes / 60,
        // because the activity replaces idle time that would have been spent anyway.
        function forecastWithPlannedActivity(profile as Profile, durationMinutes as Number) as ForecastResult {
            var base = hasMinimumConfidence() ? forecast() : getSimpleForecast();

            var idleRate = _drainLearner.getIdleRate();
            var profileRate = _drainLearner.getProfileRate(profile);

            // Net extra drain vs just being idle
            var extraPerHour = profileRate - idleRate;
            if (extraPerHour < 0.0f) { extraPerHour = 0.0f; }
            var extraDrain = extraPerHour * durationMinutes.toFloat() / 60.0f;

            var settings = _storage.getSettings();
            var riskThresholdRed = settings[:riskThresholdRed] as Number;
            var riskThresholdYellow = settings[:riskThresholdYellow] as Number;
            var conservativeFactor = settings[:conservativeFactor] as Float;
            var optimisticFactor = settings[:optimisticFactor] as Float;

            var newTypical     = clampBattery((base[:typical] as Number).toFloat()      - extraDrain);
            var newConservative = clampBattery((base[:conservative] as Number).toFloat() - extraDrain * conservativeFactor);
            var newOptimistic  = clampBattery((base[:optimistic] as Number).toFloat()    - extraDrain * optimisticFactor);
            var newRisk = calculateRisk(newConservative.toNumber(), riskThresholdRed, riskThresholdYellow);

            var remainingBudget = base[:remainingActivityMinutes] as Number;
            remainingBudget -= durationMinutes;
            if (remainingBudget < 0) { remainingBudget = 0; }

            return {
                :typical => newTypical.toNumber(),
                :conservative => newConservative.toNumber(),
                :optimistic => newOptimistic.toNumber(),
                :risk => newRisk,
                :confidence => base[:confidence],
                :nextActivityTime => base[:nextActivityTime],
                :nextActivityDuration => base[:nextActivityDuration],
                :nextActivityDrain => base[:nextActivityDrain],
                :remainingActivityMinutes => remainingBudget,
                :abnormalDrain => base[:abnormalDrain],
                :dataPointsPerProfile => base[:dataPointsPerProfile]
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
        
        // Calculate activity budget: how many minutes of activity the user can still do
        // before the typical end-of-day battery would fall below targetLevel.
        // effectiveExtraPerHour = (profileRate - idleRate) already adjusted for solar gain.
        private function calculateActivityBudget(nowBatt as Float, totalDrain as Float,
                                                 effectiveExtraPerHour as Float,
                                                 targetLevel as Number,
                                                 endSlot as Number, currentSlot as Number) as Number {
            var headroom = nowBatt - totalDrain - targetLevel.toFloat();
            if (headroom <= 0.0f) {
                return 0;
            }

            var extraPerMinute = effectiveExtraPerHour / 60.0f;
            if (extraPerMinute <= 0.0f) {
                // Activity costs no more than idle (e.g. strong solar) – unconstrained
                return (endSlot - currentSlot) * SLOT_DURATION_MIN;
            }

            var budgetMin = (headroom / extraPerMinute).toNumber();
            var maxMin = (endSlot - currentSlot) * SLOT_DURATION_MIN;
            if (budgetMin > maxMin) { budgetMin = maxMin; }
            if (budgetMin < 0)      { budgetMin = 0; }
            return budgetMin;
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
            var idleRate = _drainLearner.getIdleRate();
            
            var endOfDayMinutes = _storage.getEndOfDayMinutes();
            var minutesRemaining = TimeUtil.getMinutesUntilTime(endOfDayMinutes);
            var hoursRemaining = minutesRemaining.toFloat() / 60.0f;
            
            var drain = idleRate * hoursRemaining;

            // Apply solar gain (typical only; simple forecast is conservative by nature)
            var solarBonus = 0.0f;
            var simplRates = _storage.getDrainRates();
            var simplSolarGainRate = simplRates[:solarGainRate];
            var simplRecentSolar = simplRates[:recentSolar] as Number;
            if (simplSolarGainRate != null && simplRecentSolar > 10) {
                var solarFraction = simplRecentSolar.toFloat() / 100.0f;
                solarBonus = (simplSolarGainRate as Float) * solarFraction * hoursRemaining * 0.5f;
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
                :abnormalDrain => _drainLearner.isAbnormalDrain(),
                :dataPointsPerProfile => _drainLearner.getProfileSampleCounts()
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
        private function resolveSleepStartHour() as Number {
            try {
                var profile = UserProfile.getProfile();
                if (profile has :sleepTime) {
                    var st = profile.sleepTime;
                    if (st instanceof Time.Duration) {
                        // Duration.value() = seconds; convert to hour-of-day
                        return ((st as Time.Duration).value() / 3600).toNumber();
                    }
                }
            } catch (ex) {}
            var settings = _storage.getSettings();
            var h = settings[:sleepStartHour];
            return (h instanceof Number) ? h as Number : SLEEP_START_HOUR;
        }

        // Resolve sleep-window end hour (wake time).
        private function resolveSleepEndHour() as Number {
            try {
                var profile = UserProfile.getProfile();
                if (profile has :wakeTime) {
                    var wt = profile.wakeTime;
                    if (wt instanceof Time.Duration) {
                        return ((wt as Time.Duration).value() / 3600).toNumber();
                    }
                }
            } catch (ex) {}
            var settings = _storage.getSettings();
            var h = settings[:sleepEndHour];
            return (h instanceof Number) ? h as Number : SLEEP_END_HOUR;
        }

        // Get current battery for display
        function getCurrentBattery() as Number {
            return getBatteryPercent();
        }
        
        // Get learned rates for display
        function getLearnedRatesDisplay() as Dictionary {
            var rates = _storage.getDrainRates();
            return {
                :idle => rates[:idle],
                :activity => rates[:activityGeneric],
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
