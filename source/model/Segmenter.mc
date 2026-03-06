import Toybox.Lang;

(:background)
module BatteryBudget {
    
    class Segmenter {
        
        private var _storage as StorageManager;
        
        function initialize() {
            _storage = StorageManager.getInstance();
        }
        
        // Process a pair of snapshots and potentially create/extend the current segment
        function processSnapshotPair(prev as Snapshot, curr as Snapshot) as Void {
            var currentSegment = _storage.getCurrentSegment();
            var shouldCreateNew = false;
            var isGapBreak = false;  // true when the break is caused by a time gap (not state change)

            if (currentSegment == null) {
                shouldCreateNew = true;
            } else {
                // Check for state/profile change (also covers charging transitions)
                if (prev[:state] != curr[:state] || prev[:profile] != curr[:profile]) {
                    shouldCreateNew = true;
                }

                // Check for time gap or backward time.
                // Gaps larger than MAX_LEARNING_GAP_MIN mean the watch was off / rebooted /
                // had a clock jump – the interval is invalid for learning.
                var gap = curr[:tMin] - prev[:tMin];
                if (gap <= 0 || gap > MAX_LEARNING_GAP_MIN) {
                    shouldCreateNew = true;
                    isGapBreak = true;
                }

                // Check if segment duration would be too long (> 4 hours)
                if (!shouldCreateNew) {
                    var potentialDuration = curr[:tMin] - (currentSegment[:startTMin] as Number);
                    if (potentialDuration > 240) {
                        shouldCreateNew = true;
                    }
                }
            }

            if (shouldCreateNew) {
                // Finalize previous segment if exists
                if (currentSegment != null) {
                    finalizeSegment(currentSegment as Segment, prev);
                }

                if (isGapBreak) {
                    // The interval prev→curr spans a large gap and must not be learned from.
                    // Reset to null; the next pair will start a fresh segment.
                    _storage.setCurrentSegment(null);
                    return;
                }

                // Start new segment (represents the interval prev->curr with curr state)
                var newSegment = {
                    :startTMin => prev[:tMin],
                    :endTMin => curr[:tMin],
                    :startBatt => prev[:battPct],
                    :endBatt => curr[:battPct],
                    :state => curr[:state],
                    :profile => curr[:profile],
                    :solarW => ((prev[:solarW] as Number) + (curr[:solarW] as Number)) / 2
                } as Segment;

                _storage.setCurrentSegment(newSegment);
            } else {
                // Extend current segment (create new to avoid mutating cached reference)
                var seg = currentSegment as Segment;
                var extendedSegment = {
                    :startTMin => seg[:startTMin],
                    :endTMin => curr[:tMin],
                    :startBatt => seg[:startBatt],
                    :endBatt => curr[:battPct],
                    :state => seg[:state],
                    :profile => seg[:profile],
                    :solarW => ((seg[:solarW] as Number) + (curr[:solarW] as Number)) / 2
                } as Segment;
                _storage.setCurrentSegment(extendedSegment);
            }
        }
        
        // Finalize a segment (update end values, trigger learning if valid)
        private function finalizeSegment(segment as Segment, endSnapshot as Snapshot) as Void {
            segment[:endTMin] = endSnapshot[:tMin];
            segment[:endBatt] = endSnapshot[:battPct];
            
            // Check if segment is valid for learning
            if (isValidForLearning(segment)) {
                // Trigger learning
                var drainLearner = new DrainLearner();
                drainLearner.learnFromSegment(segment);
                
                // Update pattern if activity
                if (segment[:state] == STATE_ACTIVITY) {
                    var patternLearner = new PatternLearner();
                    patternLearner.learnFromSegment(segment);
                }
            }
        }
        
        // Check if segment is valid for drain rate learning
        private function isValidForLearning(segment as Segment) as Boolean {
            // Must have battery drop (not charging)
            if (segment[:endBatt] >= segment[:startBatt]) {
                return false;
            }
            
            // Must not be charging state
            if (segment[:state] == STATE_CHARGING) {
                return false;
            }
            
            // Must have minimum duration
            var duration = segment[:endTMin] - segment[:startTMin];
            if (duration < MIN_SEGMENT_DURATION_MIN) {
                return false;
            }
            
            return true;
        }
        
        // Returns true when the time gap between two consecutive snapshots is small enough
        // that the interval can be trusted for drain-rate and pattern learning.
        static function isGapValid(prevTMin as Number, currTMin as Number) as Boolean {
            var gap = currTMin - prevTMin;
            return gap > 0 && gap <= MAX_LEARNING_GAP_MIN;
        }

        // Calculate drain rate for a segment (%/hour)
        static function calculateDrainRate(segment as Segment) as Float {
            var durationMin = segment[:endTMin] - segment[:startTMin];
            if (durationMin <= 0) {
                return 0.0f;
            }
            
            var battDrop = segment[:startBatt] - segment[:endBatt];
            if (battDrop <= 0) {
                return 0.0f;
            }
            
            var durationHours = durationMin.toFloat() / 60.0f;
            return battDrop.toFloat() / durationHours;
        }
    }
}