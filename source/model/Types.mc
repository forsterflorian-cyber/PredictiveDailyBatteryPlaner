import Toybox.Lang;

(:background)
module BatteryBudget {
    
    // State enum for battery tracking
    enum State {
        STATE_UNKNOWN = 0,
        STATE_IDLE = 1,
        STATE_ACTIVITY = 2,
        STATE_CHARGING = 3,
        STATE_SLEEP = 4
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
        :solarW as Number       // solar intensity 0-100
    };

    // Segment structure
    typedef Segment as {
        :startTMin as Number,
        :endTMin as Number,
        :startBatt as Number,
        :endBatt as Number,
        :state as State,
        :profile as Profile,
        :solarW as Number       // average solar intensity during segment (0-100)
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
        :remainingActivityMinutes as Number,  // minutes of activity budget until target level
        :abnormalDrain as Boolean,            // true when idle rate is >50% above default
        :dataPointsPerProfile as Dictionary   // sample counts keyed by :idle/:activityGeneric/:run etc.
    };

    // Drain rates structure
    typedef DrainRates as {
        :idle as Float,
        :activityGeneric as Float,
        :run as Float or Null,
        :bike as Float or Null,
        :hike as Float or Null,
        :swim as Float or Null,
        :sampleCounts as Dictionary<Symbol, Number>,
        :solarGain as Float,              // %/h gained per unit solar intensity (0.0-1.0)
        :recentSolar as Number            // recent average solar intensity (0-100)
    };
    
    // Constants
    // 1-hour slots: 7×24 = 168 values (vs. old 7×48 = 336).
    // Halves RAM and persistent-storage footprint; ±30 min resolution loss
    // is negligible given EMA smoothing on the forecast side.
    const SLOTS_PER_DAY = 24;
    const SLOT_DURATION_MIN = 60;
    const MAX_SEGMENTS = 300;
    const MIN_SEGMENT_DURATION_MIN = 10;

    // Maximum gap between two snapshots before the interval is excluded from learning
    const MAX_LEARNING_GAP_MIN = 60;

    // Default drain rates (%/h) - conservative estimates for FR955
    const DEFAULT_RATE_IDLE = 0.8f;           // ~5 days standby
    const DEFAULT_RATE_ACTIVITY = 8.0f;       // ~12h GPS activity
    const DEFAULT_RATE_SLEEP = 0.5f;

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
