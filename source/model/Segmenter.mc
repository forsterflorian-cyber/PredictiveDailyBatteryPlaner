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

            // ── Time-integrity guards ────────────────────────────────────────────────
            // Backward or zero-gap: clock correction (GPS sync, DST fall-back) or
            // duplicate snapshot.  Epoch-minute data in the current in-progress segment
            // may already be based on the wrong (fast) clock, so discard it entirely
            // without learning and wait for a fresh forward-going pair.
            if (gap <= 0) {
                _storage.setCurrentSegment(null);
                return;
            }

            // Large forward gap: device was off, rebooted, or had a GPS-sync jump that
            // advanced the clock by more than MAX_LEARNING_GAP_MIN.  The interval
            // prev→curr is invalid for learning, but the in-progress segment up to
            // `prev` was recorded before the jump and its data is valid – finalise it.
            if (gap > MAX_LEARNING_GAP_MIN) {
                var existing = _storage.getCurrentSegment();
                if (existing != null) {
                    finalizeSegment(existing as Segment, prev);
                }
                _storage.setCurrentSegment(null);
                return;
            }
            // ────────────────────────────────────────────────────────────────────────

            var currentSegment = _storage.getCurrentSegment();
            var shouldCreateNew = (currentSegment == null);

            if (currentSegment != null) {
                // State or profile change (also covers charging transitions)
                if (prev[:state] != curr[:state] || prev[:profile] != curr[:profile]) {
                    shouldCreateNew = true;
                }

                // Split idle/sleep periods when the HR-broadcast signature changes.
                if (!shouldCreateNew && (prev[:broadcastCandidate] != curr[:broadcastCandidate])) {
                    shouldCreateNew = true;
                }

                // Segment duration cap (> 4 hours → split for accuracy)
                if (!shouldCreateNew) {
                    var potentialDuration = (curr[:tMin] as Number) - (currentSegment[:startTMin] as Number);
                    if (potentialDuration > 240) {
                        shouldCreateNew = true;
                    }
                }
            }

            if (shouldCreateNew) {
                if (currentSegment != null) {
                    finalizeSegment(currentSegment as Segment, prev);
                }

                // Start new segment representing the interval prev→curr
                var newSegment = {
                    :startTMin => prev[:tMin],
                    :endTMin => curr[:tMin],
                    :startBatt => prev[:battPct],
                    :endBatt => curr[:battPct],
                    :state => curr[:state],
                    :profile => curr[:profile],
                    :solarW => ((prev[:solarW] as Number) + (curr[:solarW] as Number)) / 2,
                    :hrDensity => ((prev[:hrDensity] as Number) + (curr[:hrDensity] as Number)) / 2,
                    :broadcastCandidate => (prev[:broadcastCandidate] as Boolean) || (curr[:broadcastCandidate] as Boolean)
                } as Segment;
                _storage.setCurrentSegment(newSegment);
            } else {
                // Extend current segment (new object to avoid mutating cached reference)
                var seg = currentSegment as Segment;
                var extendedSegment = {
                    :startTMin => seg[:startTMin],
                    :endTMin => curr[:tMin],
                    :startBatt => seg[:startBatt],
                    :endBatt => curr[:battPct],
                    :state => seg[:state],
                    :profile => seg[:profile],
                    :solarW => ((seg[:solarW] as Number) + (curr[:solarW] as Number)) / 2,
                    :hrDensity => ((seg[:hrDensity] as Number) + (curr[:hrDensity] as Number)) / 2,
                    :broadcastCandidate => (seg[:broadcastCandidate] as Boolean) || (curr[:broadcastCandidate] as Boolean)
                } as Segment;
                _storage.setCurrentSegment(extendedSegment);
            }
        }
        
        // Finalize a segment (update end values, trigger learning if valid)
        private function finalizeSegment(segment as Segment, endSnapshot as Snapshot) as Void {
            segment[:endTMin] = endSnapshot[:tMin];
            segment[:endBatt] = endSnapshot[:battPct];
            segment[:hrDensity] = (((segment[:hrDensity] as Number) + (endSnapshot[:hrDensity] as Number)) / 2);
            segment[:broadcastCandidate] = (segment[:broadcastCandidate] as Boolean) || (endSnapshot[:broadcastCandidate] as Boolean);

            segment = classifyBroadcastSegment(segment);

            if (isValidForPlanning(segment)) {
                _storage.recordUsageForSegment(segment[:state] as State,
                                               segment[:startTMin] as Number,
                                               segment[:endTMin] as Number);
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
