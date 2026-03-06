import Toybox.Lang;

(:background)
module BatteryBudget {
    
    class DrainLearner {
        
        private var _storage as StorageManager;
        
        // EMA smoothing factor
        private const ALPHA = 0.2f;
        
        function initialize() {
            _storage = StorageManager.getInstance();
        }
        
        // Learn from a finalized segment
        function learnFromSegment(segment as Segment) as Void {
            // Calculate drain rate
            var rate = Segmenter.calculateDrainRate(segment);
            
            // Sanity check rate
            if (rate < MIN_RATE || rate > MAX_RATE) {
                return; // Outlier, skip
            }
            
            var rates = _storage.getDrainRates();
            var counts = rates[:sampleCounts];
            if (counts == null) {
                counts = {} as Dictionary<Symbol, Number>;
            }
            
            // Update appropriate rate based on state
            var state = segment[:state] as State;
            
            if (state == STATE_IDLE) {
                rates[:idle] = updateEMA(rates[:idle] as Float, rate);
                incrementCount(counts, :idle);
                _storage.incrementStat("totalIdleSegments");

                // Estimate solar gain rate from idle segments where solar is meaningful.
                // If measured drain is less than the default idle rate, solar is compensating.
                var solarW = segment[:solarW] as Number;
                if (solarW >= 20) {
                    var solarFraction = solarW.toFloat() / 100.0f;
                    var estimatedGain = DEFAULT_RATE_IDLE - rate;
                    if (estimatedGain > 0.0f) {
                        var solarGainSample = estimatedGain / solarFraction;
                        if (solarGainSample > 5.0f) { solarGainSample = 5.0f; } // max ~5 %/h at full sun
                        var currentGain = rates[:solarGain] as Float;
                        if (currentGain <= 0.0f) { rates[:solarGain] = solarGainSample; }
                        else { rates[:solarGain] = updateEMA(currentGain, solarGainSample); }
                    }
                }
            } else if (state == STATE_ACTIVITY) {
                // Update generic activity rate
                rates[:activityGeneric] = updateEMA(rates[:activityGeneric] as Float, rate);
                incrementCount(counts, :activityGeneric);
                _storage.incrementStat("totalActivitySegments");
                
                // Also update profile-specific rate if applicable
                updateProfileRate(rates, counts, segment[:profile] as Profile, rate);
            } else if (state == STATE_SLEEP) {
                // Could track separately, but for MVP treat as low idle
                var sleepRate = rate * 0.8f; // Sleep tends to be lower than idle
                rates[:idle] = updateEMA(rates[:idle] as Float, sleepRate);
            }
            // STATE_CHARGING and STATE_UNKNOWN are skipped

            // Track recent solar intensity as a slow EMA (α=0.1) across all segments
            var solarW = segment[:solarW] as Number;
            var currentRecentSolar = (rates[:recentSolar] as Number).toFloat();
            rates[:recentSolar] = (currentRecentSolar * 0.9f + solarW.toFloat() * 0.1f + 0.5f).toNumber();

            rates[:sampleCounts] = counts;
            _storage.setDrainRates(rates);
        }
        
        // Update EMA with new sample
        private function updateEMA(current as Float, sample as Float) as Float {
            // Clamp to valid range
            var clamped = clampRate(sample);
            return (1.0f - ALPHA) * current + ALPHA * clamped;
        }
        
        // Clamp rate to valid range
        private function clampRate(rate as Float) as Float {
            if (rate < MIN_RATE) {
                return MIN_RATE;
            }
            if (rate > MAX_RATE) {
                return MAX_RATE;
            }
            return rate;
        }
        
        // Update profile-specific rate
        private function updateProfileRate(rates as DrainRates, counts as Dictionary<Symbol, Number>,
                                           profile as Profile, rate as Float) as Void {
            var key = null as Symbol?;

            if (profile == PROFILE_RUN) {
                key = :run;
                if (rates[:run] == null) { rates[:run] = rate; }
                else { rates[:run] = updateEMA(rates[:run] as Float, rate); }
            } else if (profile == PROFILE_BIKE) {
                key = :bike;
                if (rates[:bike] == null) { rates[:bike] = rate; }
                else { rates[:bike] = updateEMA(rates[:bike] as Float, rate); }
            } else if (profile == PROFILE_HIKE) {
                key = :hike;
                if (rates[:hike] == null) { rates[:hike] = rate; }
                else { rates[:hike] = updateEMA(rates[:hike] as Float, rate); }
            } else if (profile == PROFILE_SWIM) {
                key = :swim;
                if (rates[:swim] == null) { rates[:swim] = rate; }
                else { rates[:swim] = updateEMA(rates[:swim] as Float, rate); }
            }
            // PROFILE_OTHER and PROFILE_GENERIC fall back to activityGeneric (already updated above)

            if (key != null) {
                incrementCount(counts, key);
            }
        }

        // Get the best available drain rate for a given activity profile.
        // Falls back to activityGeneric when fewer than MIN_PROFILE_SAMPLES exist.
        function getProfileRate(profile as Profile) as Float {
            var rates = _storage.getDrainRates();
            var counts = rates[:sampleCounts];

            var key = null as Symbol?;
            var rate = null as Float?;

            if (profile == PROFILE_RUN) {
                key = :run; rate = rates[:run] as Float?;
            } else if (profile == PROFILE_BIKE) {
                key = :bike; rate = rates[:bike] as Float?;
            } else if (profile == PROFILE_HIKE) {
                key = :hike; rate = rates[:hike] as Float?;
            } else if (profile == PROFILE_SWIM) {
                key = :swim; rate = rates[:swim] as Float?;
            }

            if (key != null && rate != null && counts != null) {
                var count = counts.hasKey(key) ? counts[key] as Number : 0;
                if (count >= MIN_PROFILE_SAMPLES) {
                    return rate as Float;
                }
            }

            // Fallback: not enough samples for this profile
            return rates[:activityGeneric] as Float;
        }
        
        // Increment sample count for a category
        private function incrementCount(counts as Dictionary<Symbol, Number>, key as Symbol) as Void {
            var current = counts.hasKey(key) ? counts[key] as Number : 0;
            counts[key] = current + 1;
        }
        
        // Returns true when the learned idle rate exceeds the default by more than 50%.
        // This indicates a rogue background process, active sensor, or unusual firmware behaviour.
        function isAbnormalDrain() as Boolean {
            var rates = _storage.getDrainRates();
            var counts = rates[:sampleCounts];
            // Only flag once we have enough idle samples to trust the EMA
            var idleCount = (counts != null && counts.hasKey(:idle)) ? counts[:idle] as Number : 0;
            if (idleCount < 5) {
                return false;
            }
            return (rates[:idle] as Float) > DEFAULT_RATE_IDLE * 1.5f;
        }

        // Return a snapshot of the sample-count dictionary (copy to avoid external mutation).
        // Keys present: :idle, :activityGeneric, :run, :bike, :hike, :swim (if any samples exist)
        function getProfileSampleCounts() as Dictionary {
            var rates = _storage.getDrainRates();
            var counts = rates[:sampleCounts];
            if (counts == null) {
                return {} as Dictionary;
            }
            var copy = {} as Dictionary;
            var keys = [:idle, :activityGeneric, :run, :bike, :hike, :swim];
            for (var i = 0; i < keys.size(); i++) {
                var k = keys[i];
                if ((counts as Dictionary<Symbol, Number>).hasKey(k)) {
                    copy[k] = (counts as Dictionary<Symbol, Number>)[k];
                }
            }
            return copy;
        }

        // Get idle rate
        function getIdleRate() as Float {
            var rates = _storage.getDrainRates();
            return rates[:idle] as Float;
        }
        
        // Get generic activity rate
        function getActivityRate() as Float {
            var rates = _storage.getDrainRates();
            return rates[:activityGeneric] as Float;
        }
        
        // Calculate confidence based on sample counts
        function getRatesConfidence() as Float {
            var rates = _storage.getDrainRates();
            var counts = rates[:sampleCounts];
            
            if (counts == null) {
                return 0.0f;
            }
            
            var idleCount = counts.hasKey(:idle) ? counts[:idle] as Number : 0;
            var actCount = counts.hasKey(:activityGeneric) ? counts[:activityGeneric] as Number : 0;
            
            // Need at least some idle and activity samples
            var idleConfidence = idleCount.toFloat() / 20.0f;
            if (idleConfidence > 1.0f) {
                idleConfidence = 1.0f;
            }
            
            var actConfidence = actCount.toFloat() / 10.0f;
            if (actConfidence > 1.0f) {
                actConfidence = 1.0f;
            }
            
            return (idleConfidence * 0.6f + actConfidence * 0.4f);
        }
    }
}
