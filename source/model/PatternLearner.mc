import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:background)
module BatteryBudget {
    
    class PatternLearner {
        
        private var _storage as StorageManager;
        
        // Decay factor per week
        private const WEEKLY_DECAY = 0.9f;
        
        // Max activity minutes per slot (for normalization)
        private const MAX_SLOT_MINUTES = 30;
        
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
        
        // Get the epoch minute when the current slot ends
        private function getSlotEndEpochMin(currentEpochMin as Number) as Number {
            var moment = new Time.Moment(currentEpochMin * 60);
            var info = Gregorian.info(moment, Time.FORMAT_SHORT);
            var minutesIntoSlot = info.min.toNumber() % 30;
            
            // Minutes until slot ends
            return currentEpochMin + (30 - minutesIntoSlot);
        }
        
        // Update a slot in memory (caller must call setPattern + updateSlotCoverage after)
        private function updateSlotInMemory(pattern as Array<Array<Number>>, weekday as Number, slotIndex as Number, minutes as Number) as Void {
            if (weekday >= 0 && weekday < 7 && slotIndex >= 0 && slotIndex < SLOTS_PER_DAY) {
                // EMA update for the slot
                var current = pattern[weekday][slotIndex].toFloat();
                var alpha = 0.3f; // Faster learning for pattern
                var newValue = (1.0f - alpha) * current + alpha * minutes.toFloat();
                
                // Cap at max slot duration
                if (newValue > MAX_SLOT_MINUTES.toFloat()) {
                    newValue = MAX_SLOT_MINUTES.toFloat();
                }
                
                pattern[weekday][slotIndex] = newValue.toNumber();
            }
        }
        
        // Get expected activity minutes for a slot
        function getExpectedActivityMinutes(weekday as Number, slotIndex as Number) as Number {
            var pattern = _storage.getPattern();
            
            if (weekday >= 0 && weekday < 7 && slotIndex >= 0 && slotIndex < SLOTS_PER_DAY) {
                return pattern[weekday][slotIndex];
            }
            
            return 0;
        }
        
        // Get expected activity minutes for remaining day
        function getExpectedActivityToEndOfDay(weekday as Number, startSlot as Number, endSlot as Number) as Number {
            var total = 0;
            var pattern = _storage.getPattern();
            
            if (weekday >= 0 && weekday < 7) {
                var maxSlot = endSlot;
                if (maxSlot > SLOTS_PER_DAY) {
                    maxSlot = SLOTS_PER_DAY;
                }
                for (var i = startSlot; i < maxSlot; i++) {
                    total += pattern[weekday][i];
                }
            }
            
            return total;
        }
        
        // Find next significant activity window
        function findNextActivityWindow(weekday as Number, startSlot as Number, endSlot as Number) 
            as Dictionary? {
            var pattern = _storage.getPattern();
            
            if (weekday < 0 || weekday >= 7) {
                return null;
            }
            
            var bestWindowStart = -1;
            var bestWindowEnd = -1;
            var bestWindowMinutes = 0;
            
            var inWindow = false;
            var windowStart = startSlot;
            var windowMinutes = 0;
            
            // Threshold for "significant" activity
            var threshold = 10; // minutes
            
            var maxSlot = endSlot;
            if (maxSlot > SLOTS_PER_DAY) {
                maxSlot = SLOTS_PER_DAY;
            }
            
            for (var i = startSlot; i < maxSlot; i++) {
                var slotMinutes = pattern[weekday][i];
                
                if (slotMinutes >= threshold) {
                    if (!inWindow) {
                        // Start new window
                        inWindow = true;
                        windowStart = i;
                        windowMinutes = slotMinutes;
                    } else {
                        // Extend window
                        windowMinutes += slotMinutes;
                    }
                } else {
                    if (inWindow) {
                        // End window
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
            
            // Check if window extends to end
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
            
            for (var day = 0; day < 7; day++) {
                for (var slot = 0; slot < SLOTS_PER_DAY; slot++) {
                    var current = pattern[day][slot].toFloat();
                    pattern[day][slot] = (current * WEEKLY_DECAY).toNumber();
                }
            }
            
            _storage.setPattern(pattern);
        }
        
        // Update slot coverage stats for confidence calculation
        private function updateSlotCoverage() as Void {
            var pattern = _storage.getPattern();
            var covered = 0;
            
            for (var day = 0; day < 7; day++) {
                for (var slot = 0; slot < SLOTS_PER_DAY; slot++) {
                    if (pattern[day][slot] > 0) {
                        covered++;
                    }
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
