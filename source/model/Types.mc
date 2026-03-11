import Toybox.Lang;

(:background)
module BatteryBudget {
    
    // State enum for battery tracking
    enum State {
        STATE_UNKNOWN = 0,
        STATE_IDLE = 1,
        STATE_ACTIVITY = 2,
        STATE_CHARGING = 3,
        STATE_SLEEP = 4,
        STATE_BROADCAST = 5
    }
    
    // Activity profile enum
    enum Profile {
        PROFILE_GENERIC = 0,
        PROFILE_RUN = 1,
        PROFILE_BIKE = 2,
        PROFILE_HIKE = 3,
        PROFILE_SWIM = 4,
        PROFILE_OTHER = 5
    }
    
    // Risk level enum
    enum RiskLevel {
        RISK_LOW = 0,
        RISK_MEDIUM = 1,
        RISK_HIGH = 2
    }
    
    // Snapshot structure (compact)
    typedef Snapshot as {
        :tMin as Number,        // epoch minutes
        :battPct as Number,     // 0-100
        :state as State,
        :profile as Profile,
        :solarW as Number,      // solar intensity 0-100
        :heartRate as Number,   // current bpm or 0 when unavailable
        :hrDensity as Number,   // recent HR samples per hour
        :broadcastCandidate as Boolean
    };

    // Segment structure
    typedef Segment as {
        :startTMin as Number,
        :endTMin as Number,
        :startBatt as Number,
        :endBatt as Number,
        :state as State,
        :profile as Profile,
        :solarW as Number,      // average solar intensity during segment (0-100)
        :hrDensity as Number,   // average HR samples per hour across the segment
        :broadcastCandidate as Boolean
    };

    // Forecast result
    typedef ForecastResult as {
        :typical as Number,
        :conservative as Number,
        :optimistic as Number,
        :risk as RiskLevel,
        :confidence as Float,
        :nextActivityTime as Number or Null,
        :nextActivityDuration as Number or Null,
        :nextActivityDrain as Number or Null,
        :remainingActivityMinutes as Number,
        :solarSuppressed as Boolean
    };

    // Drain rates structure
    typedef DrainRates as {
        :idle as Float,
        :activityGeneric as Float,
        :broadcast as Float,
        :run as Float or Null,
        :bike as Float or Null,
        :hike as Float or Null,
        :swim as Float or Null,
        :sampleCounts as Dictionary<Symbol, Number>,
        :solarGain as Float,              // %/h gained per unit solar intensity (0.0-1.0)
        :recentSolar as Number,           // recent average solar intensity (0-100)
        :hrDensityIdle as Float           // baseline HR history density during real idle periods
    };

    typedef WeeklyPlanState as {
        :weekKey as Number,
        :nativeUsedMin as Number,
        :broadcastUsedMin as Number
    };

    typedef PendingBroadcastEvent as {
        :startTMin as Number,
        :endTMin as Number,
        :durationMin as Number,
        :battDrop as Number,
        :drainRate as Float,
        :weekKey as Number,
        :hrDensity as Number
    };
    
    // Constants
    // 1-hour slots: 7×24 = 168 values (vs. old 7×48 = 336).
    // Halves RAM and persistent-storage footprint; ±30 min resolution loss
    // is negligible given EMA smoothing on the forecast side.
    const SLOTS_PER_DAY = 24;
    const SLOT_DURATION_MIN = 60;
    const MIN_SEGMENT_DURATION_MIN = 10;

    // Maximum gap between two snapshots before the interval is excluded from learning
    const MAX_LEARNING_GAP_MIN = 60;

    // Default drain rates (%/h) - conservative estimates for FR955
    const DEFAULT_RATE_IDLE = 0.8f;           // ~5 days standby
    const DEFAULT_RATE_ACTIVITY = 8.0f;       // ~12h GPS activity
    const DEFAULT_RATE_BROADCAST = 3.2f;      // HR broadcast with wireless links, no GPS
    const DEFAULT_RATE_SLEEP = 0.5f;
    const DEFAULT_HR_DENSITY_IDLE = 6.0f;     // sparse all-day HR sampling baseline

    // Rate bounds for sanity checking
    const MIN_RATE = 0.1f;
    const MAX_RATE = 25.0f;

    // Confidence threshold for full vs simple forecast
    const CONFIDENCE_THRESHOLD = 0.5f;

    // Minimum samples before a profile-specific rate is trusted over activityGeneric
    const MIN_PROFILE_SAMPLES = 3;

    // Activity budget target level: battery % the user wants to keep at end of day
    const TARGET_LEVEL = 15;

    // Sleep window for reduced drain rate (22:00 – 05:59 local time)
    const SLEEP_START_HOUR = 22;
    const SLEEP_END_HOUR = 6;
}
