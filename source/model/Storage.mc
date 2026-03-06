import Toybox.Lang;
import Toybox.Application.Storage;
import Toybox.Application.Properties;

(:background)
module BatteryBudget {
    
    class StorageManager {
        
        // Storage keys
        // Legacy key (pre-v1.0.0): stored segment history caused OOM on low-memory devices
        private const KEY_SEGMENTS = "seg";
        private const KEY_DRAIN_RATES = "dr";
        private const KEY_PATTERN = "pat";
        private const KEY_CURRENT_SEGMENT = "cs";
        private const KEY_LAST_SNAPSHOT = "ls";
        private const KEY_STATS = "st";
        // Compact battery history: flat array [tMin1, batt1, tMin2, batt2, ...]
        // Max BATTERY_HISTORY_MAX_PAIRS pairs = 2*BATTERY_HISTORY_MAX_PAIRS numbers.
        private const KEY_BATTERY_HISTORY = "bh";
        private const BATTERY_HISTORY_MAX_PAIRS = 24;

        // Singleton instance
        private static var _instance as StorageManager?;

        // Cached data
        private var _currentSegment as Segment?;
        private var _currentSegmentLoaded as Boolean;
        private var _drainRates as DrainRates?;
        // Flat array: index = weekday * SLOTS_PER_DAY + slotIndex (7×24 = 168 elements)
        private var _pattern as Array<Number>?;
        private var _lastSnapshot as Snapshot?;
        private var _lastSnapshotLoaded as Boolean;
        private var _stats as Dictionary?;
        private var _batteryHistory as Array<Number>?;

        // Settings cache
        private var _settings as Dictionary?;
        
        //--------------------------------------------------
        // Singleton
        //--------------------------------------------------
        
        static function getInstance() as StorageManager {
            if (_instance == null) {
                _instance = new StorageManager();
            }
            return _instance;
        }
        
        private function initialize() {
            _currentSegmentLoaded = false;
            _lastSnapshotLoaded = false;
            migrateLegacySegmentHistory();
        }
        
        //--------------------------------------------------
        // Load/Save All
        //--------------------------------------------------
        
        function saveAll() as Void {
            saveDrainRates();
            savePattern();
            saveStats();
            // Note: Last snapshot is saved immediately in setLastSnapshot()
        }
        

        //--------------------------------------------------
        // Segment state (only keep the current in-progress segment)
        //--------------------------------------------------
        
        private function loadCurrentSegment() as Segment? {
            try {
                var data = Storage.getValue(KEY_CURRENT_SEGMENT);
                if (data != null && data instanceof Array) {
                    var arr = data as Array;
                    if (arr.size() >= 6) {
                        return {
                            :startTMin => arr[0] as Number,
                            :endTMin => arr[1] as Number,
                            :startBatt => arr[2] as Number,
                            :endBatt => arr[3] as Number,
                            :state => arr[4] as State,
                            :profile => arr[5] as Profile,
                            :solarW => arr.size() >= 7 ? arr[6] as Number : 0
                        } as Segment;
                    }
                }
            } catch (ex) {
                // Fall through
            }
            return null;
        }
        
        function getCurrentSegment() as Segment? {
            if (!_currentSegmentLoaded) {
                _currentSegment = loadCurrentSegment();
                _currentSegmentLoaded = true;
            }
            return _currentSegment;
        }
        
        function setCurrentSegment(segment as Segment?) as Void {
            _currentSegment = segment;
            _currentSegmentLoaded = true;
            
            try {
                if (segment == null) {
                    Storage.deleteValue(KEY_CURRENT_SEGMENT);
                } else {
                    Storage.setValue(KEY_CURRENT_SEGMENT, [
                        segment[:startTMin],
                        segment[:endTMin],
                        segment[:startBatt],
                        segment[:endBatt],
                        segment[:state],
                        segment[:profile],
                        segment[:solarW]
                    ]);
                }
            } catch (ex) {
                // Ignore storage write failures
            }
        }
        //--------------------------------------------------
        // Drain Rates
        //--------------------------------------------------
        
        private function loadDrainRates() as DrainRates {
            try {
                var data = Storage.getValue(KEY_DRAIN_RATES);
                if (data != null && data instanceof Dictionary) {
                    var dict = data as Dictionary;

                    var idle = DEFAULT_RATE_IDLE;
                    var activityGeneric = DEFAULT_RATE_ACTIVITY;
                    var run = null as Float?;
                    var bike = null as Float?;
                    var hike = null as Float?;
                    var swim = null as Float?;
                    var sampleCounts = {} as Dictionary<Symbol, Number>;

                    if (dict.hasKey("i")) {
                        var v = dict["i"];
                        if (v instanceof Float) { idle = v as Float; }
                        else if (v instanceof Number) { idle = (v as Number).toFloat(); }
                    }
                    if (dict.hasKey("a")) {
                        var v = dict["a"];
                        if (v instanceof Float) { activityGeneric = v as Float; }
                        else if (v instanceof Number) { activityGeneric = (v as Number).toFloat(); }
                    }
                    if (dict.hasKey("r")) {
                        var v = dict["r"];
                        if (v instanceof Float) { run = v as Float; }
                        else if (v instanceof Number) { run = (v as Number).toFloat(); }
                    }
                    if (dict.hasKey("b")) {
                        var v = dict["b"];
                        if (v instanceof Float) { bike = v as Float; }
                        else if (v instanceof Number) { bike = (v as Number).toFloat(); }
                    }
                    if (dict.hasKey("h")) {
                        var v = dict["h"];
                        if (v instanceof Float) { hike = v as Float; }
                        else if (v instanceof Number) { hike = (v as Number).toFloat(); }
                    }
                    if (dict.hasKey("sw")) {
                        var v = dict["sw"];
                        if (v instanceof Float) { swim = v as Float; }
                        else if (v instanceof Number) { swim = (v as Number).toFloat(); }
                    }

                    if (dict.hasKey("c")) {
                        var c = dict["c"];
                        if (c != null && c instanceof Dictionary) {
                            var rawCounts = c as Dictionary;
                            if (rawCounts.hasKey(:idle) && rawCounts[:idle] instanceof Number) { sampleCounts[:idle] = rawCounts[:idle] as Number; }
                            else if (rawCounts.hasKey("idle") && rawCounts["idle"] instanceof Number) { sampleCounts[:idle] = rawCounts["idle"] as Number; }

                            if (rawCounts.hasKey(:activityGeneric) && rawCounts[:activityGeneric] instanceof Number) { sampleCounts[:activityGeneric] = rawCounts[:activityGeneric] as Number; }
                            else if (rawCounts.hasKey("activityGeneric") && rawCounts["activityGeneric"] instanceof Number) { sampleCounts[:activityGeneric] = rawCounts["activityGeneric"] as Number; }

                            if (rawCounts.hasKey(:run) && rawCounts[:run] instanceof Number) { sampleCounts[:run] = rawCounts[:run] as Number; }
                            else if (rawCounts.hasKey("run") && rawCounts["run"] instanceof Number) { sampleCounts[:run] = rawCounts["run"] as Number; }

                            if (rawCounts.hasKey(:bike) && rawCounts[:bike] instanceof Number) { sampleCounts[:bike] = rawCounts[:bike] as Number; }
                            else if (rawCounts.hasKey("bike") && rawCounts["bike"] instanceof Number) { sampleCounts[:bike] = rawCounts["bike"] as Number; }

                            if (rawCounts.hasKey(:hike) && rawCounts[:hike] instanceof Number) { sampleCounts[:hike] = rawCounts[:hike] as Number; }
                            else if (rawCounts.hasKey("hike") && rawCounts["hike"] instanceof Number) { sampleCounts[:hike] = rawCounts["hike"] as Number; }

                            if (rawCounts.hasKey(:swim) && rawCounts[:swim] instanceof Number) { sampleCounts[:swim] = rawCounts[:swim] as Number; }
                            else if (rawCounts.hasKey("swim") && rawCounts["swim"] instanceof Number) { sampleCounts[:swim] = rawCounts["swim"] as Number; }
                        }
                    }

                    var solarGainRate = null as Float?;
                    var recentSolar = 0;
                    if (dict.hasKey("sg")) {
                        var v = dict["sg"];
                        if (v instanceof Float) { solarGainRate = v as Float; }
                        else if (v instanceof Number) { solarGainRate = (v as Number).toFloat(); }
                    }
                    if (dict.hasKey("rs")) {
                        var v = dict["rs"];
                        if (v instanceof Number) { recentSolar = v as Number; }
                    }

                    return {
                        :idle => idle,
                        :activityGeneric => activityGeneric,
                        :run => run,
                        :bike => bike,
                        :hike => hike,
                        :swim => swim,
                        :sampleCounts => sampleCounts,
                        :solarGainRate => solarGainRate,
                        :recentSolar => recentSolar
                    } as DrainRates;
                }
            } catch (ex) {
                // Fall through to defaults
            }
            return getDefaultDrainRates();
        }
        
        function getDefaultDrainRates() as DrainRates {
            return {
                :idle => DEFAULT_RATE_IDLE,
                :activityGeneric => DEFAULT_RATE_ACTIVITY,
                :run => null,
                :bike => null,
                :hike => null,
                :swim => null,
                :sampleCounts => {} as Dictionary<Symbol, Number>,
                :solarGainRate => null,
                :recentSolar => 0
            } as DrainRates;
        }
        
        function getDrainRates() as DrainRates {
            if (_drainRates == null) {
                _drainRates = loadDrainRates();
            }
            return _drainRates;
        }
        
        function setDrainRates(rates as DrainRates) as Void {
            _drainRates = rates;
            saveDrainRates();
        }
        
        private function saveDrainRates() as Void {
            if (_drainRates != null) {
                try {
                    var dict = {
                        "i" => _drainRates[:idle],
                        "a" => _drainRates[:activityGeneric],
                        "c" => _drainRates[:sampleCounts]
                    } as Dictionary;
                    if (_drainRates[:run] != null) {
                        dict["r"] = _drainRates[:run];
                    }
                    if (_drainRates[:bike] != null) {
                        dict["b"] = _drainRates[:bike];
                    }
                    if (_drainRates[:hike] != null) {
                        dict["h"] = _drainRates[:hike];
                    }
                    if (_drainRates[:swim] != null) {
                        dict["sw"] = _drainRates[:swim];
                    }
                    if (_drainRates[:solarGainRate] != null) {
                        dict["sg"] = _drainRates[:solarGainRate];
                    }
                    if ((_drainRates[:recentSolar] as Number) > 0) {
                        dict["rs"] = _drainRates[:recentSolar];
                    }
                    Storage.setValue(KEY_DRAIN_RATES, dict);
                } catch (ex) {
                    // Ignore storage write failures
                }
            }
        }
        
        //--------------------------------------------------
        // Pattern (Activity Minutes Expected)
        //--------------------------------------------------
        
        // Pattern is stored as a flat array of 7*SLOTS_PER_DAY=168 Numbers.
        // Index: weekday * SLOTS_PER_DAY + slotIndex.
        // Old format (7×48 nested Array<Array<Number>>) is discarded on first load;
        // patterns re-learn within days via the background service.
        private function loadPattern() as Array<Number> {
            try {
                var data = Storage.getValue(KEY_PATTERN);
                if (data instanceof Array) {
                    var arr = data as Array;
                    // Accept new flat format: exactly 7*SLOTS_PER_DAY elements of Number
                    if (arr.size() == 7 * SLOTS_PER_DAY && arr[0] instanceof Number) {
                        return arr as Array<Number>;
                    }
                    // Old nested format or wrong size → discard, start fresh
                }
            } catch (ex) {
                // Fall through to default
            }
            return createEmptyPattern();
        }

        private function createEmptyPattern() as Array<Number> {
            var pattern = [] as Array<Number>;
            var total = 7 * SLOTS_PER_DAY;
            for (var i = 0; i < total; i++) {
                pattern.add(0);
            }
            return pattern;
        }

        function getPattern() as Array<Number> {
            if (_pattern == null) {
                _pattern = loadPattern();
            }
            return _pattern;
        }

        function setPattern(pattern as Array<Number>) as Void {
            _pattern = pattern;
            savePattern();
        }
        
        private function savePattern() as Void {
            if (_pattern != null) {
                try {
                    Storage.setValue(KEY_PATTERN, _pattern);
                } catch (ex) {
                    // Ignore storage write failures
                }
            }
        }
        
        //--------------------------------------------------
        // Last Snapshot
        //--------------------------------------------------
        
        private function loadLastSnapshot() as Snapshot? {
            try {
                var data = Storage.getValue(KEY_LAST_SNAPSHOT);
                if (data != null && data instanceof Array) {
                    var arr = data as Array;
                    if (arr.size() >= 4) {
                        return {
                            :tMin => arr[0] as Number,
                            :battPct => arr[1] as Number,
                            :state => arr[2] as State,
                            :profile => arr[3] as Profile,
                            :solarW => arr.size() >= 5 ? arr[4] as Number : 0
                        } as Snapshot;
                    }
                }
            } catch (ex) {
                // No previous snapshot
            }
            return null;
        }
        
        function getLastSnapshot() as Snapshot? {
            if (!_lastSnapshotLoaded) {
                _lastSnapshot = loadLastSnapshot();
                _lastSnapshotLoaded = true;
            }
            return _lastSnapshot;
        }
        
        function setLastSnapshot(snapshot as Snapshot) as Void {
            _lastSnapshot = snapshot;
            _lastSnapshotLoaded = true;
            try {
                Storage.setValue(KEY_LAST_SNAPSHOT, [
                    snapshot[:tMin],
                    snapshot[:battPct],
                    snapshot[:state],
                    snapshot[:profile],
                    snapshot[:solarW]
                ]);
            } catch (ex) {
                // Ignore storage write failures
            }
        }
        
        //--------------------------------------------------
        // Stats (for confidence calculation)
        //--------------------------------------------------
        
        private function loadStats() as Dictionary {
            try {
                var data = Storage.getValue(KEY_STATS);
                if (data != null && data instanceof Dictionary) {
                    return data as Dictionary;
                }
            } catch (ex) {
                // Fall through
            }
            return {
                "firstDataDay" => 0,
                "totalActivitySegments" => 0,
                "totalIdleSegments" => 0,
                "slotsCovered" => 0,
                "lastDecayTime" => 0
            };
        }
        
        function getStats() as Dictionary {
            if (_stats == null) {
                _stats = loadStats();
            }
            return _stats;
        }
        
        function updateStats(key as String, value) as Void {
            var stats = getStats();
            stats[key] = value;
            _stats = stats;
            saveStats();
        }
        
        function incrementStat(key as String) as Void {
            var stats = getStats();
            var current = stats.hasKey(key) ? stats[key] as Number : 0;
            stats[key] = current + 1;
            _stats = stats;
            // Don't save immediately for performance - saveAll() will handle it
        }
        
        private function saveStats() as Void {
            if (_stats != null) {
                try {
                    Storage.setValue(KEY_STATS, _stats);
                } catch (ex) {
                    // Ignore storage write failures
                }
            }
        }
        
        //--------------------------------------------------
        // Settings (from Properties)
        //--------------------------------------------------
        
        private function loadSettings() as Dictionary {
            return {
                :endOfDayTime => readStringProperty("endOfDayTime", "22:00"),
                :riskThresholdYellow => clampNumber(readNumberProperty("riskThresholdYellow", 30), 0, 100),
                :riskThresholdRed => clampNumber(readNumberProperty("riskThresholdRed", 15), 0, 100),
                :conservativeFactor => readFactorProperty("conservativeFactor", 1.2f, 1.0f, 2.0f),
                :optimisticFactor => readFactorProperty("optimisticFactor", 0.8f, 0.5f, 1.0f),
                :sampleIntervalMin => clampNumber(readNumberProperty("sampleIntervalMin", 15), 5, 120),
                :learningWindowDays => clampNumber(readNumberProperty("learningWindowDays", 14), 1, 60),
                :targetLevel => clampNumber(readNumberProperty("targetLevel", TARGET_LEVEL), 5, 50),
                :sleepStartHour => clampNumber(readNumberProperty("sleepStartHour", SLEEP_START_HOUR), 18, 23),
                :sleepEndHour => clampNumber(readNumberProperty("sleepEndHour", SLEEP_END_HOUR), 0, 10)
            };
        }

        private function readStringProperty(key as String, defaultValue as String) as String {
            var value = getPropertySafe(key, defaultValue);
            return (value instanceof String) ? value as String : defaultValue;
        }

        private function readNumberProperty(key as String, defaultValue as Number) as Number {
            var value = getPropertySafe(key, defaultValue);
            return (value instanceof Number) ? value as Number : defaultValue;
        }

        private function readFactorProperty(key as String, defaultValue as Float, minVal as Float, maxVal as Float) as Float {
            var value = getPropertySafe(key, defaultValue);
            var factor = defaultValue;

            if (value instanceof Float) {
                factor = value as Float;
            } else if (value instanceof Number) {
                factor = (value as Number).toFloat();
            }

            // Backward compatibility: older versions stored factors as integer percentages (e.g., 120 -> 1.2)
            if (factor > 10.0f) { factor = factor / 100.0f; }

            if (factor < minVal) { factor = minVal; }
            if (factor > maxVal) { factor = maxVal; }
            return factor;
        }

        private function clampNumber(value as Number, minVal as Number, maxVal as Number) as Number {
            if (value < minVal) { return minVal; }
            if (value > maxVal) { return maxVal; }
            return value;
        }
        private function getPropertySafe(key as String, defaultValue) {
            try {
                var value = Properties.getValue(key);
                if (value != null) {
                    return value;
                }
            } catch (ex) {
                // Property not found
            }
            return defaultValue;
        }
        
        function getSettings() as Dictionary {
            if (_settings == null) {
                _settings = loadSettings();
            }
            return _settings;
        }
        
        function reloadSettings() as Void {
            _settings = loadSettings();
        }
        
        function getSetting(key as Symbol) {
            var settings = getSettings();
            return settings.hasKey(key) ? settings[key] : null;
        }
        
        function getEndOfDayMinutes() as Number {
            var timeStr = getSetting(:endOfDayTime);
            if (timeStr instanceof String) {
                return TimeUtil.parseTimeString(timeStr as String);
            }
            return 22 * 60; // Default 22:00
        }
        
        //--------------------------------------------------
        // Battery History (compact ring buffer)
        //--------------------------------------------------

        function getBatteryHistory() as Array<Number> {
            if (_batteryHistory == null) {
                try {
                    var data = Storage.getValue(KEY_BATTERY_HISTORY);
                    if (data instanceof Array) {
                        var arr = data as Array;
                        if (arr.size() > 0 && arr[0] instanceof Number) {
                            _batteryHistory = arr as Array<Number>;
                            return _batteryHistory;
                        }
                    }
                } catch (ex) {}
                _batteryHistory = [] as Array<Number>;
            }
            return _batteryHistory;
        }

        // Append a new [tMin, battPct] reading; evicts oldest when buffer is full.
        function appendBatteryHistory(tMin as Number, battPct as Number) as Void {
            var history = getBatteryHistory();
            history.add(tMin);
            history.add(battPct);
            // Trim to max capacity (2 values per pair)
            var maxSize = BATTERY_HISTORY_MAX_PAIRS * 2;
            while (history.size() > maxSize) {
                history.remove(history[0]);
                if (history.size() > 0) { history.remove(history[0]); }
            }
            _batteryHistory = history;
            try {
                Storage.setValue(KEY_BATTERY_HISTORY, history);
            } catch (ex) {}
        }

        //--------------------------------------------------
        // Cleanup old data
        //--------------------------------------------------

        function cleanupOldSegments(windowDays as Number) as Void {
            // v1.0.0+ no longer stores segment history (prevents OOM on low-memory devices).
            // Still honor the call site by clearing any legacy data and pruning stale current segment.
            
            var nowMin = TimeUtil.nowEpochMinutes();
            var cutoffMin = nowMin - (windowDays * 24 * 60);
            var current = getCurrentSegment();
            if (current != null && (current[:endTMin] as Number) < cutoffMin) {
                setCurrentSegment(null);
            }
        }
        
        //--------------------------------------------------
        // First data tracking
        //--------------------------------------------------
        
        function recordFirstDataIfNeeded() as Void {
            var stats = getStats();
            if (!stats.hasKey("firstDataDay") || stats["firstDataDay"] == 0) {
                updateStats("firstDataDay", TimeUtil.nowEpochMinutes());
            }
        }
        
        //--------------------------------------------------
        // Debug / Reset
        //--------------------------------------------------
        
        function resetAllData() as Void {
            Storage.clearValues();
            _currentSegment = null;
            _currentSegmentLoaded = false;
            _drainRates = null;
            _pattern = null;
            _lastSnapshot = null;
            _lastSnapshotLoaded = false;
            _stats = null;
            _settings = null;
            _batteryHistory = null;
        }

        // Reset only learned EMA values (drain rates + activity pattern) while keeping
        // statistics such as firstDataDay intact. Use this when the watch hardware changes
        // or a firmware update significantly alters power consumption.
        function resetLearning() as Void {
            _drainRates = getDefaultDrainRates();
            saveDrainRates();

            _pattern = createEmptyPattern();
            savePattern();

            // Reset segment counters but keep firstDataDay so "days collected" stays accurate
            var stats = getStats();
            stats["totalActivitySegments"] = 0;
            stats["totalIdleSegments"] = 0;
            stats["slotsCovered"] = 0;
            _stats = stats;
            saveStats();

            _currentSegment = null;
            _currentSegmentLoaded = true;
            setCurrentSegment(null);

            // Clear last snapshot so the next background trigger starts fresh instead
            // of creating a cross-reset segment that would corrupt the new EMA values.
            _lastSnapshot = null;
            _lastSnapshotLoaded = true;
            try { Storage.deleteValue(KEY_LAST_SNAPSHOT); } catch (ex) {}

            _batteryHistory = [] as Array<Number>;
            try { Storage.deleteValue(KEY_BATTERY_HISTORY); } catch (ex) {}
        }

        private function migrateLegacySegmentHistory() as Void {
            // Old versions stored a full segment history; that can OOM on low-memory devices.
            try {
                Storage.deleteValue(KEY_SEGMENTS);
            } catch (ex) {
                // Ignore if key does not exist / API not available
            }
        }
    }
}
