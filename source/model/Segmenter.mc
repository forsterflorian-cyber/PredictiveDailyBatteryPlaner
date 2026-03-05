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
            
            if (currentSegment == null) {
                shouldCreateNew = true;
            } else {
                // Check for state/profile change
                if (prev[:state] != curr[:state] || prev[:profile] != curr[:profile]) {
                    shouldCreateNew = true;
                }
                
                // Check for charging transition
                if (prev[:state] != STATE_CHARGING && curr[:state] == STATE_CHARGING) {
                    shouldCreateNew = true;
                }
                if (prev[:state] == STATE_CHARGING && curr[:state] != STATE_CHARGING) {
                    shouldCreateNew = true;
                }
                
                // Check for time gap (more than 2 hours) or backward time
                var gap = curr[:tMin] - prev[:tMin];
                if (gap <= 0 || gap > 120) {
                    shouldCreateNew = true;
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
                
                // Start new segment (represents the interval prev->curr with curr state)
                var newSegment = {
                    :startTMin => prev[:tMin],
                    :endTMin => curr[:tMin],
                    :startBatt => prev[:battPct],
                    :endBatt => curr[:battPct],
                    :state => curr[:state],
                    :profile => curr[:profile]
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
                    :profile => seg[:profile]
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