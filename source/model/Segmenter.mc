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
            var gap = (curr[:tMin] as Number) - (prev[:tMin] as Number);

            // Backward or zero-gap: clock correction, duplicate snapshot, or stale data.
            if (gap <= 0) {
                _storage.setCurrentSegment(null);
                return;
            }

            // Large forward gap: the interval itself is invalid for learning, but any
            // previously accumulated segment up to `prev` is still valid and should be finalized.
            if (gap > MAX_LEARNING_GAP_MIN) {
                var existing = _storage.getCurrentSegment();
                if (existing != null) {
                    finalizeSegment(existing as Segment, prev);
                }
                _storage.setCurrentSegment(null);
                return;
            }

            var currentSegment = _storage.getCurrentSegment();
            var boundaryChanged = hasBoundaryChange(prev, curr);
            var shouldCreateNew = (currentSegment == null) || boundaryChanged;

            if (currentSegment != null && !shouldCreateNew) {
                // Segment duration cap (> 4 hours -> split for accuracy)
                var potentialDuration = (curr[:tMin] as Number) - (currentSegment[:startTMin] as Number);
                if (potentialDuration > 240) {
                    shouldCreateNew = true;
                }
            }

            if (shouldCreateNew) {
                if (currentSegment != null) {
                    finalizeSegment(currentSegment as Segment, prev);
                }

                // Transition pairs are ambiguous: we do not know when the change happened
                // within prev->curr, so seed the new state at `curr` and only learn from
                // the next stable interval instead of mislabeling the whole gap.
                var newSegment = boundaryChanged
                    ? createSeedSegment(curr)
                    : createStableIntervalSegment(prev, curr);
                _storage.setCurrentSegment(newSegment);
            } else {
                // Extend current segment (new object to avoid mutating cached reference)
                var seg = currentSegment as Segment;
                var existingDuration = (seg[:endTMin] as Number) - (seg[:startTMin] as Number);
                var intervalDuration = (curr[:tMin] as Number) - (seg[:endTMin] as Number);
                var intervalSolar = (((prev[:solarW] as Number) + (curr[:solarW] as Number)) / 2);
                var intervalHrDensity = (((prev[:hrDensity] as Number) + (curr[:hrDensity] as Number)) / 2);
                var extendedSegment = {
                    :startTMin => seg[:startTMin],
                    :endTMin => curr[:tMin],
                    :startBatt => seg[:startBatt],
                    :endBatt => curr[:battPct],
                    :state => seg[:state],
                    :profile => seg[:profile],
                    :solarW => mergeDurationWeightedAverage(
                        seg[:solarW] as Number,
                        existingDuration,
                        intervalSolar,
                        intervalDuration),
                    :hrDensity => mergeDurationWeightedAverage(
                        seg[:hrDensity] as Number,
                        existingDuration,
                        intervalHrDensity,
                        intervalDuration),
                    :broadcastCandidate => (seg[:broadcastCandidate] as Boolean) || (curr[:broadcastCandidate] as Boolean)
                } as Segment;
                _storage.setCurrentSegment(extendedSegment);
            }
        }

        private function hasBoundaryChange(prev as Snapshot, curr as Snapshot) as Boolean {
            if (prev[:state] != curr[:state] || prev[:profile] != curr[:profile]) {
                return true;
            }
            return (prev[:broadcastCandidate] != curr[:broadcastCandidate]);
        }

        private function createSeedSegment(snapshot as Snapshot) as Segment {
            return {
                :startTMin => snapshot[:tMin],
                :endTMin => snapshot[:tMin],
                :startBatt => snapshot[:battPct],
                :endBatt => snapshot[:battPct],
                :state => snapshot[:state],
                :profile => snapshot[:profile],
                :solarW => snapshot[:solarW],
                :hrDensity => snapshot[:hrDensity],
                :broadcastCandidate => snapshot[:broadcastCandidate]
            } as Segment;
        }

        private function createStableIntervalSegment(prev as Snapshot, curr as Snapshot) as Segment {
            return {
                :startTMin => prev[:tMin],
                :endTMin => curr[:tMin],
                :startBatt => prev[:battPct],
                :endBatt => curr[:battPct],
                :state => prev[:state],
                :profile => prev[:profile],
                :solarW => ((prev[:solarW] as Number) + (curr[:solarW] as Number)) / 2,
                :hrDensity => ((prev[:hrDensity] as Number) + (curr[:hrDensity] as Number)) / 2,
                :broadcastCandidate => (prev[:broadcastCandidate] as Boolean) || (curr[:broadcastCandidate] as Boolean)
            } as Segment;
        }

        private function mergeDurationWeightedAverage(existingAverage as Number,
                                                      existingDurationMin as Number,
                                                      intervalAverage as Number,
                                                      intervalDurationMin as Number) as Number {
            if (intervalDurationMin <= 0) {
                return existingAverage;
            }
            if (existingDurationMin <= 0) {
                return intervalAverage;
            }

            var totalDuration = existingDurationMin + intervalDurationMin;
            return ((existingAverage * existingDurationMin) + (intervalAverage * intervalDurationMin)) / totalDuration;
        }
        
        // Finalize a segment (update end values, trigger learning if valid)
        private function finalizeSegment(segment as Segment, endSnapshot as Snapshot) as Void {
            segment[:endTMin] = endSnapshot[:tMin];
            segment[:endBatt] = endSnapshot[:battPct];
            segment[:broadcastCandidate] = (segment[:broadcastCandidate] as Boolean) || (endSnapshot[:broadcastCandidate] as Boolean);

            segment = classifyBroadcastSegment(segment);

            if (isValidForPlanning(segment)) {
                if (segment[:state] != STATE_BROADCAST) {
                    _storage.recordUsageForSegment(segment[:state] as State,
                                                   segment[:startTMin] as Number,
                                                   segment[:endTMin] as Number);
                }
            }
            
            // Check if segment is valid for learning
            if (isValidForLearning(segment)) {
                if (segment[:state] == STATE_BROADCAST) {
                    _storage.incrementStat("totalBroadcastSegments");
                    _storage.enqueuePendingBroadcastEvent({
                        :startTMin => segment[:startTMin],
                        :endTMin => segment[:endTMin],
                        :durationMin => (segment[:endTMin] as Number) - (segment[:startTMin] as Number),
                        :battDrop => (segment[:startBatt] as Number) - (segment[:endBatt] as Number),
                        :drainRate => Segmenter.calculateDrainRate(segment),
                        :weekKey => TimeUtil.getCurrentWeekKey(),
                        :hrDensity => segment[:hrDensity] as Number
                    } as PendingBroadcastEvent);
                } else {
                    // Trigger learning
                    var drainLearner = new DrainLearner();
                    drainLearner.learnFromSegment(segment);
                }

                // Update pattern only for native activities
                if (segment[:state] == STATE_ACTIVITY) {
                    var patternLearner = new PatternLearner();
                    patternLearner.learnFromSegment(segment);
                }
            }
        }

        private function classifyBroadcastSegment(segment as Segment) as Segment {
            var state = segment[:state] as State;
            if (state != STATE_IDLE && state != STATE_SLEEP) {
                return segment;
            }

            if (!(segment[:broadcastCandidate] as Boolean)) {
                return segment;
            }

            var rate = Segmenter.calculateDrainRate(segment);
            if (rate <= 0.0f) {
                return segment;
            }

            var rates = _storage.getDrainRates();
            var idleRate = rates[:idle] as Float;
            var idleDensity = rates[:hrDensityIdle] as Float;
            if (idleDensity <= 0.0f) {
                idleDensity = DEFAULT_HR_DENSITY_IDLE;
            }

            var hasHeartRate = (segment[:hrDensity] as Number) > 0;
            if (BroadcastDetector.meetsSignalThreshold((segment[:hrDensity] as Number).toFloat(),
                                                       idleDensity,
                                                       hasHeartRate,
                                                       MIN_SEGMENT_DURATION_MIN)
                && BroadcastDetector.meetsDrainSpike(rate, idleRate)) {
                segment[:state] = STATE_BROADCAST;
            }

            return segment;
        }

        private function isValidForPlanning(segment as Segment) as Boolean {
            if (segment[:state] == STATE_CHARGING || segment[:state] == STATE_UNKNOWN) {
                return false;
            }

            var duration = (segment[:endTMin] as Number) - (segment[:startTMin] as Number);
            return duration >= MIN_SEGMENT_DURATION_MIN;
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
