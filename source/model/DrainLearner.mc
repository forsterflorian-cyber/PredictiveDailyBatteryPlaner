import Toybox.Lang;

(:background)
module BatteryBudget {
    
    class DrainLearner {
        
        private var _storage as StorageManager;
        
        // EMA smoothing factor
        private const ALPHA = 0.2f;
        
        // Minimum samples before using learned rate
        private const MIN_SAMPLES_FOR_PROFILE = 5;
        
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
                if (rates[:run] == null) {
                    rates[:run] = rate;
                } else {
                    rates[:run] = updateEMA(rates[:run] as Float, rate);
                }
            } else if (profile == PROFILE_BIKE) {
                key = :bike;
                if (rates[:bike] == null) {
                    rates[:bike] = rate;
                } else {
                    rates[:bike] = updateEMA(rates[:bike] as Float, rate);
                }
            } else if (profile == PROFILE_HIKE) {
                key = :hike;
                if (rates[:hike] == null) {
                    rates[:hike] = rate;
                } else {
                    rates[:hike] = updateEMA(rates[:hike] as Float, rate);
                }
            }
            // Other profiles use generic
            
            if (key != null) {
                incrementCount(counts, key);
            }
        }
        
        // Increment sample count for a category
        private function incrementCount(counts as Dictionary<Symbol, Number>, key as Symbol) as Void {
            var current = counts.hasKey(key) ? counts[key] as Number : 0;
            counts[key] = current + 1;
        }
        
        // Get the best rate for an activity profile
        function getRateForProfile(profile as Profile) as Float {
            var rates = _storage.getDrainRates();
            var counts = rates[:sampleCounts];
            
            // Check if we have enough samples for profile-specific rate
            var profileKey = profileToKey(profile);
            if (profileKey != null && counts != null) {
                var count = counts.hasKey(profileKey) ? counts[profileKey] as Number : 0;
                if (count >= MIN_SAMPLES_FOR_PROFILE) {
                    var profileRate = getProfileRate(rates, profile);
                    if (profileRate != null) {
                        return profileRate;
                    }
                }
            }
            
            // Fall back to generic activity rate
            return rates[:activityGeneric] as Float;
        }
        
        // Map profile to dictionary key
        private function profileToKey(profile as Profile) as Symbol? {
            if (profile == PROFILE_RUN) {
                return :run;
            } else if (profile == PROFILE_BIKE) {
                return :bike;
            } else if (profile == PROFILE_HIKE) {
                return :hike;
            }
            return null;
        }
        
        // Get profile-specific rate from rates dictionary
        private function getProfileRate(rates as DrainRates, profile as Profile) as Float? {
            if (profile == PROFILE_RUN) {
                return rates[:run] as Float?;
            } else if (profile == PROFILE_BIKE) {
                return rates[:bike] as Float?;
            } else if (profile == PROFILE_HIKE) {
                return rates[:hike] as Float?;
            }
            return null;
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
