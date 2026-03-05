import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

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
            
            // Get current state
            var nowBatt = getBatteryPercent();
            var weekday = TimeUtil.getWeekday();
            var currentSlot = TimeUtil.getCurrentSlotIndex();
            var endOfDayMinutes = _storage.getEndOfDayMinutes();
            var endOfDaySlot = TimeUtil.getEndOfDaySlot(endOfDayMinutes);
            
            // Get learned rates
            var idleRate = _drainLearner.getIdleRate();
            var activityRate = _drainLearner.getActivityRate();
            
            // Get factors from settings
            var conservativeFactor = settings[:conservativeFactor] as Float;
            var optimisticFactor = settings[:optimisticFactor] as Float;
            
            
            // Calculate drain for remaining slots
            var totalDrainTypical = 0.0f;
            
            if (currentSlot < endOfDaySlot) {
                for (var slot = currentSlot; slot < endOfDaySlot && slot < SLOTS_PER_DAY; slot++) {
                    var expectedActivityMin = _patternLearner.getExpectedActivityMinutes(weekday, slot);
                    var expectedIdleMin = SLOT_DURATION_MIN - expectedActivityMin;
                    
                    // Ensure non-negative
                    if (expectedIdleMin < 0) {
                        expectedIdleMin = 0;
                        expectedActivityMin = SLOT_DURATION_MIN;
                    }
                    
                    // Calculate drain for this slot
                    var slotDrain = 
                        (expectedActivityMin.toFloat() / 60.0f) * activityRate +
                        (expectedIdleMin.toFloat() / 60.0f) * idleRate;
                    
                    totalDrainTypical += slotDrain;
                }
            }
            
            // Calculate end of day battery levels
            var endBattTypical = nowBatt.toFloat() - totalDrainTypical;
            var endBattConservative = nowBatt.toFloat() - (totalDrainTypical * conservativeFactor);
            var endBattOptimistic = nowBatt.toFloat() - (totalDrainTypical * optimisticFactor);
            
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
            
            return {
                :typical => endBattTypical.toNumber(),
                :conservative => endBattConservative.toNumber(),
                :optimistic => endBattOptimistic.toNumber(),
                :risk => risk,
                :confidence => confidence,
                :nextActivityTime => nextActivityTime,
                :nextActivityDuration => nextActivityDuration,
                :nextActivityDrain => nextActivityDrain != null ? nextActivityDrain.toNumber() : null
            } as ForecastResult;
        }
        
        // Get current battery percentage
        private function getBatteryPercent() as Number {
            var stats = System.getSystemStats();
            if (stats != null && stats has :battery) {
                var batt = stats.battery;
                if (batt != null) {
                    return batt.toNumber();
                }
            }
            return 50;
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
            var endBatt = clampBattery(nowBatt.toFloat() - drain);
            
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
                :nextActivityDrain => null
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
