import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:background)
module BatteryBudget {
    
    class PatternLearner {
        
        private var _storage as StorageManager;
        
        // Decay factor per week
        private const WEEKLY_DECAY = 0.9f;
        
        // Max activity minutes per slot (= full slot duration)
        private const MAX_SLOT_MINUTES = 60;
        
        function initialize() {
            _storage = StorageManager.getInstance();
        }
        
        // Learn from an activity segment
        function learnFromSegment(segment as Segment) as Void {
            if (segment[:state] != STATE_ACTIVITY) {
                return;
            }
            
            var startMin = segment[:startTMin] as Number;
            var endMin = segment[:endTMin] as Number;
            var pattern = _storage.getPattern();
            var didUpdate = false;
            
            // Distribute activity minutes across slots
            var currentMin = startMin;
            
            while (currentMin < endMin) {
                var weekday = TimeUtil.getWeekdayFromEpochMin(currentMin);
                var slotIndex = TimeUtil.getSlotFromEpochMin(currentMin);
                
                // Bounds check (day_of_week can occasionally be out of range)
                if (weekday < 0 || weekday >= 7 || slotIndex < 0 || slotIndex >= SLOTS_PER_DAY) {
                    currentMin = getSlotEndEpochMin(currentMin);
                    continue;
                }
                
                // Calculate minutes in this slot
                var slotEndMin = getSlotEndEpochMin(currentMin);
                var effectiveEndMin = slotEndMin;
                if (endMin < slotEndMin) {
                    effectiveEndMin = endMin;
                }
                var minutesInSlot = effectiveEndMin - currentMin;
                
                if (minutesInSlot > 0) {
                    updateSlotInMemory(pattern, weekday, slotIndex, minutesInSlot);
                    didUpdate = true;
                }
                
                // Move to next slot
                currentMin = slotEndMin;
            }
            
            if (didUpdate) {
                _storage.setPattern(pattern);
                updateSlotCoverage();
            }
        }
        
        // Epoch minute when the current 1-hour slot ends
        private function getSlotEndEpochMin(currentEpochMin as Number) as Number {
            var moment = new Time.Moment(currentEpochMin * 60);
            var info = Gregorian.info(moment, Time.FORMAT_SHORT);
            // Minutes remaining until the next whole hour
            return currentEpochMin + (60 - info.min.toNumber());
        }

        // Update a slot in the flat pattern array (EMA, capped at MAX_SLOT_MINUTES)
        private function updateSlotInMemory(pattern as Array<Number>, weekday as Number, slotIndex as Number, minutes as Number) as Void {
            if (weekday >= 0 && weekday < 7 && slotIndex >= 0 && slotIndex < SLOTS_PER_DAY) {
                var idx = weekday * SLOTS_PER_DAY + slotIndex;
                var current = pattern[idx].toFloat();
                var alpha = 0.3f;
                var newValue = (1.0f - alpha) * current + alpha * minutes.toFloat();
                if (newValue > MAX_SLOT_MINUTES.toFloat()) {
                    newValue = MAX_SLOT_MINUTES.toFloat();
                }
                pattern[idx] = newValue.toNumber();
            }
        }

        // Get expected activity minutes for a slot
        function getExpectedActivityMinutes(weekday as Number, slotIndex as Number) as Number {
            if (weekday >= 0 && weekday < 7 && slotIndex >= 0 && slotIndex < SLOTS_PER_DAY) {
                return _storage.getPattern()[weekday * SLOTS_PER_DAY + slotIndex];
            }
            return 0;
        }
        
        // Find the most significant upcoming activity window (by total minutes).
        function findNextActivityWindow(weekday as Number, startSlot as Number, endSlot as Number)
            as Dictionary? {
            if (weekday < 0 || weekday >= 7) {
                return null;
            }

            var pattern = _storage.getPattern();
            var dayOffset = weekday * SLOTS_PER_DAY;

            var bestWindowStart = -1;
            var bestWindowEnd = -1;
            var bestWindowMinutes = 0;

            var inWindow = false;
            var windowStart = startSlot;
            var windowMinutes = 0;

            // With 60-min slots, raise threshold to 15 min (vs 10 for 30-min slots)
            var threshold = 15;

            var maxSlot = endSlot;
            if (maxSlot > SLOTS_PER_DAY) {
                maxSlot = SLOTS_PER_DAY;
            }

            for (var i = startSlot; i < maxSlot; i++) {
                var slotMinutes = pattern[dayOffset + i];

                if (slotMinutes >= threshold) {
                    if (!inWindow) {
                        inWindow = true;
                        windowStart = i;
                        windowMinutes = slotMinutes;
                    } else {
                        windowMinutes += slotMinutes;
                    }
                } else {
                    if (inWindow) {
                        if (windowMinutes > bestWindowMinutes) {
                            bestWindowStart = windowStart;
                            bestWindowEnd = i;
                            bestWindowMinutes = windowMinutes;
                        }
                        inWindow = false;
                        windowMinutes = 0;
                    }
                }
            }

            if (inWindow && windowMinutes > bestWindowMinutes) {
                bestWindowStart = windowStart;
                bestWindowEnd = maxSlot;
                bestWindowMinutes = windowMinutes;
            }

            if (bestWindowStart >= 0 && bestWindowMinutes >= threshold) {
                return {
                    :startSlot => bestWindowStart,
                    :endSlot => bestWindowEnd,
                    :totalMinutes => bestWindowMinutes
                };
            }

            return null;
        }

        // Apply weekly decay to all pattern values
        function applyDecay() as Void {
            var pattern = _storage.getPattern();
            var total = 7 * SLOTS_PER_DAY;
            for (var i = 0; i < total; i++) {
                pattern[i] = (pattern[i].toFloat() * WEEKLY_DECAY).toNumber();
            }
            _storage.setPattern(pattern);
        }

        // Update slot coverage stats for confidence calculation
        private function updateSlotCoverage() as Void {
            var pattern = _storage.getPattern();
            var covered = 0;
            var total = 7 * SLOTS_PER_DAY;
            for (var i = 0; i < total; i++) {
                if (pattern[i] > 0) {
                    covered++;
                }
            }
            _storage.updateStats("slotsCovered", covered);
        }
        
        // Get pattern confidence
        function getPatternConfidence() as Float {
            var stats = _storage.getStats();
            var slotsCovered = stats.hasKey("slotsCovered") ? stats["slotsCovered"] as Number : 0;
            var totalActivitySegments = stats.hasKey("totalActivitySegments") ? stats["totalActivitySegments"] as Number : 0;
            
            // Need some slot coverage and activity segments
            var totalSlots = 7 * SLOTS_PER_DAY;
            var coverageRatio = slotsCovered.toFloat() / totalSlots.toFloat();
            
            var segmentConfidence = totalActivitySegments.toFloat() / 20.0f;
            if (segmentConfidence > 1.0f) {
                segmentConfidence = 1.0f;
            }
            
            return (coverageRatio * 0.5f + segmentConfidence * 0.5f);
        }
    }
}
