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
        private const KEY_WEEKLY_PLAN_STATE = "wps";
        private const KEY_PENDING_BROADCAST_EVENTS = "pb";
        // Compact battery history: flat array [tMin1, batt1, tMin2, batt2, ...]
        // Max BATTERY_HISTORY_MAX_PAIRS pairs = 2*BATTERY_HISTORY_MAX_PAIRS numbers.
        private const KEY_BATTERY_HISTORY = "bh";
        private const BATTERY_HISTORY_MAX_PAIRS = 24;
        private const FUTURE_TIMESTAMP_TOLERANCE_MIN = 5;
        private const MAX_PENDING_BROADCAST_EVENTS = 3;

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
        private var _weeklyPlanState as WeeklyPlanState?;
        private var _pendingBroadcastEvents as Array<PendingBroadcastEvent>?;

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

        static function resetInstanceForTests() as Void {
            _instance = null;
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
            saveWeeklyPlanState();
            savePendingBroadcastEvents();
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
                            :solarW => arr.size() >= 7 ? arr[6] as Number : 0,
                            :hrDensity => arr.size() >= 8 ? arr[7] as Number : 0,
                            :broadcastCandidate => arr.size() >= 9 ? arr[8] as Boolean : false
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
                        segment[:solarW],
                        segment[:hrDensity],
                        segment[:broadcastCandidate]
                    ]);
                }
            } catch (ex) {
                // Ignore storage write failures
            }
        }
        //--------------------------------------------------
        // Drain Rates
        //--------------------------------------------------
        
        private function loadDrainRates() as DrainRates? {
            try {
                var data = Storage.getValue(KEY_DRAIN_RATES);
                if (data != null && data instanceof Dictionary) {
                    var dict = data as Dictionary;

                    var idle = DEFAULT_RATE_IDLE;
                    var activityGeneric = DEFAULT_RATE_ACTIVITY;
                    var broadcast = DEFAULT_RATE_BROADCAST;
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
                    if (dict.hasKey("br")) {
                        var v = dict["br"];
                        if (v instanceof Float) { broadcast = v as Float; }
                        else if (v instanceof Number) { broadcast = (v as Number).toFloat(); }
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

                            if (rawCounts.hasKey(:broadcast) && rawCounts[:broadcast] instanceof Number) { sampleCounts[:broadcast] = rawCounts[:broadcast] as Number; }
                            else if (rawCounts.hasKey("broadcast") && rawCounts["broadcast"] instanceof Number) { sampleCounts[:broadcast] = rawCounts["broadcast"] as Number; }

                            if (rawCounts.hasKey(:broadcastConfirmed) && rawCounts[:broadcastConfirmed] instanceof Number) { sampleCounts[:broadcastConfirmed] = rawCounts[:broadcastConfirmed] as Number; }
                            else if (rawCounts.hasKey("broadcastConfirmed") && rawCounts["broadcastConfirmed"] instanceof Number) { sampleCounts[:broadcastConfirmed] = rawCounts["broadcastConfirmed"] as Number; }

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

                    var solarGain = 0.0f;
                    var recentSolar = 0;
                    var hrDensityIdle = DEFAULT_HR_DENSITY_IDLE;
                    if (dict.hasKey("sg")) {
                        var v = dict["sg"];
                        if (v instanceof Float) { solarGain = v as Float; }
                        else if (v instanceof Number) { solarGain = (v as Number).toFloat(); }
                    }
                    if (dict.hasKey("rs")) {
                        var v = dict["rs"];
                        if (v instanceof Number) { recentSolar = v as Number; }
                    }
                    if (dict.hasKey("hd")) {
                        var v = dict["hd"];
                        if (v instanceof Float) { hrDensityIdle = v as Float; }
                        else if (v instanceof Number) { hrDensityIdle = (v as Number).toFloat(); }
                    }

                    return {
                        :idle => idle,
                        :activityGeneric => activityGeneric,
                        :broadcast => broadcast,
                        :run => run,
                        :bike => bike,
                        :hike => hike,
                        :swim => swim,
                        :sampleCounts => sampleCounts,
                        :solarGain => solarGain,
                        :recentSolar => recentSolar,
                        :hrDensityIdle => hrDensityIdle
                    } as DrainRates;
                }
            } catch (ex) {
                // Fall through to defaults
            }
            return null;
        }
        
        function getDefaultDrainRates() as DrainRates {
            return {
                :idle => DEFAULT_RATE_IDLE,
                :activityGeneric => DEFAULT_RATE_ACTIVITY,
                :broadcast => DEFAULT_RATE_BROADCAST,
                :run => null,
                :bike => null,
                :hike => null,
                :swim => null,
                :sampleCounts => {} as Dictionary<Symbol, Number>,
                :solarGain => 0.0f,
                :recentSolar => 0,
                :hrDensityIdle => DEFAULT_HR_DENSITY_IDLE
            } as DrainRates;
        }
        
        function getDrainRates() as DrainRates {
            if (_drainRates == null) {
                var loaded = loadDrainRates();
                _drainRates = (loaded != null) ? loaded as DrainRates : getDefaultDrainRates();
                // Persist once to initialize defaults and normalize legacy payloads.
                saveDrainRates();
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
                        "br" => _drainRates[:broadcast],
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
                    dict["sg"] = _drainRates[:solarGain];
                    if ((_drainRates[:recentSolar] as Number) > 0) {
                        dict["rs"] = _drainRates[:recentSolar];
                    }
                    dict["hd"] = _drainRates[:hrDensityIdle];
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
        private function loadPattern() as Array<Number>? {
            try {
                var data = Storage.getValue(KEY_PATTERN);
                if (data instanceof Array) {
                    var arr = data as Array;
                    // Accept new flat format: exactly 7*SLOTS_PER_DAY elements of Number
                    if (isValidFlatPattern(arr)) {
                        return arr as Array<Number>;
                    }
                    // Old nested format or wrong size -> discard persisted payload now
                    try { Storage.deleteValue(KEY_PATTERN); } catch (ex2) {}
                }
            } catch (ex) {
                // Fall through to default
            }
            return null;
        }

        private function isValidFlatPattern(arr as Array) as Boolean {
            var expectedSize = 7 * SLOTS_PER_DAY;
            if (arr.size() != expectedSize) {
                return false;
            }
            for (var i = 0; i < arr.size(); i++) {
                if (!(arr[i] instanceof Number)) {
                    return false;
                }
            }
            return true;
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
                var loaded = loadPattern();
                if (loaded == null) {
                    _pattern = createEmptyPattern();
                    savePattern();
                } else {
                    _pattern = loaded;
                }
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
                        var snapshot = {
                            :tMin => arr[0] as Number,
                            :battPct => arr[1] as Number,
                            :state => arr[2] as State,
                            :profile => arr[3] as Profile,
                            :solarW => arr.size() >= 5 ? arr[4] as Number : 0,
                            :heartRate => arr.size() >= 6 ? arr[5] as Number : 0,
                            :hrDensity => arr.size() >= 7 ? arr[6] as Number : 0,
                            :broadcastCandidate => arr.size() >= 8 ? arr[7] as Boolean : false
                        } as Snapshot;
                        if (isPersistedTimestampValid(snapshot[:tMin] as Number, TimeUtil.nowEpochMinutes())) {
                            return snapshot;
                        }
                        try { Storage.deleteValue(KEY_LAST_SNAPSHOT); } catch (ex2) {}
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
                    snapshot[:solarW],
                    snapshot[:heartRate],
                    snapshot[:hrDensity],
                    snapshot[:broadcastCandidate]
                ]);
            } catch (ex) {
                // Ignore storage write failures
            }
        }
        
        //--------------------------------------------------
        // Stats (for confidence calculation)
        //--------------------------------------------------
        
        private function createDefaultStats() as Dictionary {
            return {
                "firstDataDay" => 0,
                "totalActivitySegments" => 0,
                "totalBroadcastSegments" => 0,
                "totalConfirmedBroadcastSegments" => 0,
                "totalIdleSegments" => 0,
                "slotsCovered" => 0,
                "lastDecayTime" => 0
            };
        }

        private function normalizeStats(data as Dictionary) as Dictionary {
            var stats = createDefaultStats();
            var keys = ["firstDataDay", "totalActivitySegments", "totalBroadcastSegments",
                        "totalConfirmedBroadcastSegments", "totalIdleSegments", "slotsCovered", "lastDecayTime"];
            for (var i = 0; i < keys.size(); i++) {
                var key = keys[i];
                if (data.hasKey(key) && data[key] instanceof Number) {
                    stats[key] = data[key] as Number;
                }
            }
            return stats;
        }

        private function loadStats() as Dictionary? {
            try {
                var data = Storage.getValue(KEY_STATS);
                if (data != null && data instanceof Dictionary) {
                    return normalizeStats(data as Dictionary);
                }
            } catch (ex) {
                // Fall through
            }
            return null;
        }
        
        function getStats() as Dictionary {
            if (_stats == null) {
                var loaded = loadStats();
                _stats = (loaded != null) ? loaded as Dictionary : createDefaultStats();
                // Persist once to initialize missing keys / defaults.
                saveStats();
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
            var endOfDayMinutes = TimeUtil.parseTimeString(readStringProperty("endOfDayTime", "22:00"));
            var riskThresholdYellow = clampNumber(readNumberProperty("riskThresholdYellow", 30), 0, 100);
            var riskThresholdRed = clampNumber(readNumberProperty("riskThresholdRed", 15), 0, 100);

            // Keep thresholds ordered so risk bands remain reachable.
            if (riskThresholdRed > riskThresholdYellow) {
                var tmp = riskThresholdRed;
                riskThresholdRed = riskThresholdYellow;
                riskThresholdYellow = tmp;
            }

            return {
                :endOfDayTime => TimeUtil.formatCanonicalTime(endOfDayMinutes),
                :riskThresholdYellow => riskThresholdYellow,
                :riskThresholdRed => riskThresholdRed,
                :conservativeFactor => readFactorProperty("conservativeFactor", 1.2f, 1.0f, 2.0f),
                :optimisticFactor => readFactorProperty("optimisticFactor", 0.8f, 0.5f, 1.0f),
                :sampleIntervalMin => clampNumber(readNumberProperty("sampleIntervalMin", 15), 5, MAX_LEARNING_GAP_MIN),
                :learningWindowDays => clampNumber(readNumberProperty("learningWindowDays", 14), 1, 60),
                :targetLevel => clampNumber(readNumberProperty("targetLevel", TARGET_LEVEL), 5, 50),
                :weeklyNativeHours => clampNumber(readNumberProperty("weeklyNativeHours", 0), 0, 40),
                :weeklyBroadcastHours => clampNumber(readNumberProperty("weeklyBroadcastHours", 0), 0, 40),
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

        private function loadBatteryHistory() as Array<Number>? {
            try {
                var data = Storage.getValue(KEY_BATTERY_HISTORY);
                if (data instanceof Array) {
                    var arr = data as Array;
                    if (arr.size() % 2 != 0) {
                        return null;
                    }

                    for (var i = 0; i < arr.size(); i++) {
                        if (!(arr[i] instanceof Number)) {
                            return null;
                        }
                    }

                    var nowMin = TimeUtil.nowEpochMinutes();
                    var sanitized = [] as Array<Number>;
                    var lastTMin = 0;
                    for (var pairIndex = 0; pairIndex < arr.size(); pairIndex += 2) {
                        var tMin = arr[pairIndex] as Number;
                        var battPct = arr[pairIndex + 1] as Number;
                        if (!isPersistedTimestampValid(tMin, nowMin)) {
                            continue;
                        }
                        if (sanitized.size() > 0 && tMin <= lastTMin) {
                            continue;
                        }
                        sanitized.add(tMin);
                        sanitized.add(battPct);
                        lastTMin = tMin;
                    }

                    var maxSize = BATTERY_HISTORY_MAX_PAIRS * 2;
                    if (sanitized.size() > maxSize) {
                        var trimmed = [] as Array<Number>;
                        var start = sanitized.size() - maxSize;
                        for (var j = start; j < sanitized.size(); j++) {
                            trimmed.add(sanitized[j] as Number);
                        }
                        return trimmed;
                    }

                    return sanitized;
                }
            } catch (ex) {}
            return null;
        }

        private function isPersistedTimestampValid(tMin as Number, nowMin as Number) as Boolean {
            if (tMin <= 0) {
                return false;
            }
            return tMin <= (nowMin + FUTURE_TIMESTAMP_TOLERANCE_MIN);
        }

        private function saveBatteryHistory() as Void {
            if (_batteryHistory != null) {
                try {
                    Storage.setValue(KEY_BATTERY_HISTORY, _batteryHistory);
                } catch (ex) {}
            }
        }

        function getBatteryHistory() as Array<Number> {
            if (_batteryHistory == null) {
                var loaded = loadBatteryHistory();
                _batteryHistory = (loaded != null) ? loaded : ([] as Array<Number>);
                saveBatteryHistory();
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
            saveBatteryHistory();
        }

        //--------------------------------------------------
        // Weekly plan state
        //--------------------------------------------------

        private function createDefaultWeeklyPlanState() as WeeklyPlanState {
            return {
                :weekKey => TimeUtil.getCurrentWeekKey(),
                :nativeUsedMin => 0,
                :broadcastUsedMin => 0
            } as WeeklyPlanState;
        }

        private function normalizeWeeklyPlanState(state as WeeklyPlanState) as WeeklyPlanState {
            return StorageManager.normalizeWeeklyPlanStateForWeek(state, TimeUtil.getCurrentWeekKey());
        }

        static function normalizeWeeklyPlanStateForWeek(state as WeeklyPlanState, currentWeekKey as Number)
            as WeeklyPlanState {
            if ((state[:weekKey] as Number) != currentWeekKey) {
                return {
                    :weekKey => currentWeekKey,
                    :nativeUsedMin => 0,
                    :broadcastUsedMin => 0
                } as WeeklyPlanState;
            }
            return state;
        }

        private function loadWeeklyPlanState() as WeeklyPlanState? {
            try {
                var data = Storage.getValue(KEY_WEEKLY_PLAN_STATE);
                if (data instanceof Array) {
                    var arr = data as Array;
                    if (arr.size() >= 3) {
                        return normalizeWeeklyPlanState({
                            :weekKey => arr[0] as Number,
                            :nativeUsedMin => arr[1] as Number,
                            :broadcastUsedMin => arr[2] as Number
                        } as WeeklyPlanState);
                    }
                }
            } catch (ex) {}
            return null;
        }

        private function saveWeeklyPlanState() as Void {
            if (_weeklyPlanState != null) {
                try {
                    Storage.setValue(KEY_WEEKLY_PLAN_STATE, [
                        _weeklyPlanState[:weekKey],
                        _weeklyPlanState[:nativeUsedMin],
                        _weeklyPlanState[:broadcastUsedMin]
                    ]);
                } catch (ex) {}
            }
        }

        function getWeeklyPlanState() as WeeklyPlanState {
            if (_weeklyPlanState == null) {
                var loaded = loadWeeklyPlanState();
                _weeklyPlanState = (loaded != null) ? loaded : createDefaultWeeklyPlanState();
                saveWeeklyPlanState();
            } else {
                _weeklyPlanState = normalizeWeeklyPlanState(_weeklyPlanState as WeeklyPlanState);
            }
            return _weeklyPlanState as WeeklyPlanState;
        }

        function setWeeklyPlanState(state as WeeklyPlanState) as Void {
            _weeklyPlanState = normalizeWeeklyPlanState(state);
            saveWeeklyPlanState();
        }

        function recordUsageForSegment(state as State, startTMin as Number, endTMin as Number) as Void {
            if (endTMin <= startTMin) {
                return;
            }
            if (state != STATE_ACTIVITY && state != STATE_BROADCAST) {
                return;
            }

            var weekly = getWeeklyPlanState();
            var weekKey = weekly[:weekKey] as Number;
            var overlapMin = TimeUtil.getOverlapMinutesWithinWeek(startTMin, endTMin, weekKey);
            if (overlapMin <= 0) {
                return;
            }

            if (state == STATE_ACTIVITY) {
                weekly[:nativeUsedMin] = (weekly[:nativeUsedMin] as Number) + overlapMin;
            } else {
                weekly[:broadcastUsedMin] = (weekly[:broadcastUsedMin] as Number) + overlapMin;
            }
            setWeeklyPlanState(weekly);
        }

        function rollbackBroadcastUsageForEvent(event as PendingBroadcastEvent) as Void {
            var weekly = getWeeklyPlanState();
            if ((weekly[:weekKey] as Number) != (event[:weekKey] as Number)) {
                return;
            }

            var overlapMin = TimeUtil.getOverlapMinutesWithinWeek(
                event[:startTMin] as Number,
                event[:endTMin] as Number,
                event[:weekKey] as Number);
            if (overlapMin <= 0) {
                return;
            }

            var nextValue = (weekly[:broadcastUsedMin] as Number) - overlapMin;
            if (nextValue < 0) { nextValue = 0; }
            weekly[:broadcastUsedMin] = nextValue;
            setWeeklyPlanState(weekly);
        }

        function recordConfirmedBroadcastUsageForEvent(event as PendingBroadcastEvent) as Void {
            var weekly = getWeeklyPlanState();
            if ((weekly[:weekKey] as Number) != (event[:weekKey] as Number)) {
                return;
            }

            var overlapMin = TimeUtil.getOverlapMinutesWithinWeek(
                event[:startTMin] as Number,
                event[:endTMin] as Number,
                event[:weekKey] as Number);
            if (overlapMin <= 0) {
                return;
            }

            weekly[:broadcastUsedMin] = (weekly[:broadcastUsedMin] as Number) + overlapMin;
            setWeeklyPlanState(weekly);
        }

        //--------------------------------------------------
        // Pending broadcast validation queue
        //--------------------------------------------------

        private function loadPendingBroadcastEvents() as Array<PendingBroadcastEvent>? {
            try {
                var data = Storage.getValue(KEY_PENDING_BROADCAST_EVENTS);
                if (data instanceof Array) {
                    var raw = data as Array;
                    var events = [] as Array<PendingBroadcastEvent>;
                    for (var i = 0; i < raw.size(); i++) {
                        var item = raw[i];
                        if (item instanceof Array) {
                            var arr = item as Array;
                            if (arr.size() >= 7) {
                                events.add({
                                    :startTMin => arr[0] as Number,
                                    :endTMin => arr[1] as Number,
                                    :durationMin => arr[2] as Number,
                                    :battDrop => arr[3] as Number,
                                    :drainRate => (arr[4] as Number).toFloat(),
                                    :weekKey => arr[5] as Number,
                                    :hrDensity => arr[6] as Number
                                } as PendingBroadcastEvent);
                            }
                        }
                    }
                    return events;
                }
            } catch (ex) {}
            return null;
        }

        private function savePendingBroadcastEvents() as Void {
            if (_pendingBroadcastEvents != null) {
                try {
                    var payload = [] as Array;
                    for (var i = 0; i < _pendingBroadcastEvents.size(); i++) {
                        var event = _pendingBroadcastEvents[i] as PendingBroadcastEvent;
                        payload.add([
                            event[:startTMin],
                            event[:endTMin],
                            event[:durationMin],
                            event[:battDrop],
                            event[:drainRate],
                            event[:weekKey],
                            event[:hrDensity]
                        ]);
                    }
                    Storage.setValue(KEY_PENDING_BROADCAST_EVENTS, payload);
                } catch (ex) {}
            }
        }

        function getPendingBroadcastEvents() as Array<PendingBroadcastEvent> {
            if (_pendingBroadcastEvents == null) {
                var loaded = loadPendingBroadcastEvents();
                _pendingBroadcastEvents = (loaded != null) ? loaded : ([] as Array<PendingBroadcastEvent>);
            }
            _pendingBroadcastEvents = filterCurrentWeekEvents(_pendingBroadcastEvents as Array<PendingBroadcastEvent>);
            savePendingBroadcastEvents();
            return _pendingBroadcastEvents as Array<PendingBroadcastEvent>;
        }

        function getNextPendingBroadcastEvent() as PendingBroadcastEvent? {
            var events = getPendingBroadcastEvents();
            return events.size() > 0 ? events[0] as PendingBroadcastEvent : null;
        }

        function enqueuePendingBroadcastEvent(event as PendingBroadcastEvent) as Void {
            var events = getPendingBroadcastEvents();
            events.add(event);

            while (events.size() > MAX_PENDING_BROADCAST_EVENTS) {
                events = slicePendingEvents(events, 1);
            }

            _pendingBroadcastEvents = events;
            savePendingBroadcastEvents();
        }

        function popNextPendingBroadcastEvent() as PendingBroadcastEvent? {
            var events = getPendingBroadcastEvents();
            if (events.size() == 0) {
                return null;
            }

            var event = events[0] as PendingBroadcastEvent;
            _pendingBroadcastEvents = slicePendingEvents(events, 1);
            savePendingBroadcastEvents();
            return event;
        }

        private function slicePendingEvents(events as Array<PendingBroadcastEvent>, startIndex as Number)
            as Array<PendingBroadcastEvent> {
            var sliced = [] as Array<PendingBroadcastEvent>;
            for (var i = startIndex; i < events.size(); i++) {
                sliced.add(events[i] as PendingBroadcastEvent);
            }
            return sliced;
        }

        private function filterCurrentWeekEvents(events as Array<PendingBroadcastEvent>) as Array<PendingBroadcastEvent> {
            var weekKey = TimeUtil.getCurrentWeekKey();
            var filtered = [] as Array<PendingBroadcastEvent>;
            for (var i = 0; i < events.size(); i++) {
                var event = events[i] as PendingBroadcastEvent;
                if ((event[:weekKey] as Number) == weekKey) {
                    filtered.add(event);
                }
            }
            return filtered;
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
            _weeklyPlanState = null;
            _pendingBroadcastEvents = null;
        }

        // Reset learned model payloads completely for a clean re-learning cycle.
        // Required keys: drain rates, pattern, stats, and last snapshot.
        function resetLearning() as Void {
            try { Storage.deleteValue(KEY_DRAIN_RATES); } catch (ex) {}
            try { Storage.deleteValue(KEY_PATTERN); } catch (ex) {}
            try { Storage.deleteValue(KEY_STATS); } catch (ex) {}
            try { Storage.deleteValue(KEY_LAST_SNAPSHOT); } catch (ex) {}
            try { Storage.deleteValue(KEY_WEEKLY_PLAN_STATE); } catch (ex) {}
            try { Storage.deleteValue(KEY_PENDING_BROADCAST_EVENTS); } catch (ex) {}

            _drainRates = null;
            _pattern = null;
            _stats = null;
            _lastSnapshot = null;
            _lastSnapshotLoaded = true;
            _weeklyPlanState = null;
            _pendingBroadcastEvents = null;

            // Also reset in-memory segment/history state to avoid stale cross-reset learning.
            _currentSegment = null;
            _currentSegmentLoaded = true;
            try { Storage.deleteValue(KEY_CURRENT_SEGMENT); } catch (ex) {}
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
