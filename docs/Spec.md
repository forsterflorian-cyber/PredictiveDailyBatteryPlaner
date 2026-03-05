# BatteryBudget - Technical Specification

## 1. Overview

BatteryBudget is a Garmin Connect IQ widget that predicts end-of-day 
battery level based on learned usage patterns. It answers the question:
"How much battery will I have tonight?"

### 1.1 Goals
- Predict battery at configurable end-of-day time (default 22:00)
- Learn from actual device usage without manual input
- Provide typical/conservative/optimistic estimates
- Show risk level (low/medium/high)
- Work entirely on-device (no cloud dependency)

### 1.2 Target Devices
- Garmin watches that support widgets + glances + background logging
- Connect IQ 3.3+
- Designed for round and rectangular displays (roughly 218x218 up to 454x454)

## 2. Data Model

### 2.1 Snapshot
A point-in-time battery measurement:

  Snapshot:
    tMin: Number        - Epoch minutes (Unix timestamp / 60)
    battPct: Number     - Battery percentage 0-100
    state: State        - Current device state
    profile: Profile    - Activity profile (if in activity)

### 2.2 State Enum

  STATE_UNKNOWN   = 0
  STATE_IDLE      = 1
  STATE_ACTIVITY  = 2
  STATE_CHARGING  = 3
  STATE_SLEEP     = 4

### 2.3 Profile Enum

  PROFILE_GENERIC = 0
  PROFILE_RUN     = 1
  PROFILE_BIKE    = 2
  PROFILE_HIKE    = 3
  PROFILE_SWIM    = 4
  PROFILE_OTHER   = 5

### 2.4 Segment
A period of consistent state, derived from multiple snapshots:

  Segment:
    startTMin: Number   - Start epoch minutes
    endTMin: Number     - End epoch minutes
    startBatt: Number   - Battery at start
    endBatt: Number     - Battery at end
    state: State        - State during segment
    profile: Profile    - Profile (if activity)

Drain rate calculation (only if endBatt < startBatt):

  duration_hours = (endTMin - startTMin) / 60.0
  rate_pct_per_h = (startBatt - endBatt) / duration_hours

### 2.5 Drain Rates Structure
Learned drain rates using Exponential Moving Average (EMA):

  DrainRates:
    idle: Float              - percent/h idle drain (default 0.8)
    activityGeneric: Float   - percent/h generic activity (default 8.0)
    run: Float or null       - percent/h running (optional)
    bike: Float or null      - percent/h cycling (optional)
    hike: Float or null      - percent/h hiking (optional)
    sampleCounts:            - Samples per category
      idle: Number
      activityGeneric: Number
      run: Number
      bike: Number
      hike: Number

### 2.6 Activity Pattern
7-day x 48-slot array storing expected activity minutes:

  pattern[weekday][slot] = expected_activity_minutes

  weekday: 0 (Sunday) to 6 (Saturday)
  slot: 0-47 (each slot = 30 minutes)
    slot 0  = 00:00-00:30
    slot 1  = 00:30-01:00
    slot 36 = 18:00-18:30
    slot 44 = 22:00-22:30
    slot 47 = 23:30-00:00

### 2.7 Forecast Result
Output of the forecaster:

  ForecastResult:
    typical: Number           - Expected battery at end of day
    conservative: Number      - Worst case estimate
    optimistic: Number        - Best case estimate
    risk: RiskLevel           - LOW, MEDIUM, HIGH
    confidence: Float         - 0.0 to 1.0
    nextActivityTime: Number or null    - Slot index of next activity
    nextActivityDuration: Number or null - Expected minutes
    nextActivityDrain: Number or null    - Expected percent drain

## 3. State Detection

### 3.1 State Machine

  IDLE -----(battery increase)-----> CHARGING
    |                                    |
    | activity detected                  | battery stable/decrease
    v                                    |
  ACTIVITY <-----------------------------+
    |
    | activity ends
    v
  IDLE

Special: SLEEP state (optional)
  - Detected during 23:00-06:00
  - Low/no movement
  - Treated as low-power IDLE for learning

### 3.2 State Detection Logic

  function detectCurrentState():
    // Priority 1: Charging
    if System.getSystemStats().charging == true:
      return STATE_CHARGING
    
    // Priority 2: Battery increase (backup charging detection)
    if current_batt > previous_batt:
      return STATE_CHARGING
    
    // Priority 3: Active activity
    if Activity.getActivityInfo() has active timer:
      return STATE_ACTIVITY
    
    // Priority 4: Sleep heuristic
    if hour >= 23 OR hour < 6:
      return STATE_SLEEP  // or STATE_IDLE if not tracking sleep
    
    // Default
    return STATE_IDLE

### 3.3 Profile Detection

  function detectProfile(state):
    if state != STATE_ACTIVITY:
      return PROFILE_GENERIC
    
    info = Activity.getActivityInfo()
    if info.sport == null:
      return PROFILE_GENERIC
    
    switch info.sport:
      case 1, 10:  return PROFILE_RUN    // Running, Trail Running
      case 2:      return PROFILE_BIKE   // Cycling
      case 16, 11: return PROFILE_HIKE   // Hiking, Walking
      case 5:      return PROFILE_SWIM   // Swimming
      default:     return PROFILE_OTHER

## 4. Segmentation Algorithm

### 4.1 Segment Formation Rules

1. New segment on state change: When prev.state != curr.state
2. New segment on profile change: When prev.profile != curr.profile
3. New segment on charging transition: Battery starts/stops increasing
4. New segment on large gap: Time difference > 120 minutes
5. New segment on max duration: Segment would exceed 240 minutes

### 4.2 Segment Processing

  function processSnapshotPair(prev, curr):
    segments = storage.getSegments()
    lastSegment = segments.last() or null
    
    shouldCreateNew = false
    
    if lastSegment == null:
      shouldCreateNew = true
    else if prev.state != curr.state:
      shouldCreateNew = true
    else if prev.profile != curr.profile:
      shouldCreateNew = true
    else if (prev.state != CHARGING) and (curr.state == CHARGING):
      shouldCreateNew = true
    else if (curr.tMin - prev.tMin) > 120:
      shouldCreateNew = true
    else if (curr.tMin - lastSegment.startTMin) > 240:
      shouldCreateNew = true
    
    if shouldCreateNew:
      if lastSegment != null:
        finalizeSegment(lastSegment, prev)
      
      newSegment = create segment from prev to curr
      segments.add(newSegment)
    else:
      lastSegment.endTMin = curr.tMin
      lastSegment.endBatt = curr.battPct
    
    storage.setSegments(segments)

### 4.3 Segment Validation

A segment is valid for learning if:
- endBatt < startBatt (battery decreased)
- state != STATE_CHARGING
- duration >= 10 minutes
- calculated_rate is within 0.1-25 percent/h

## 5. Learning Algorithms

### 5.1 Drain Rate Learning (EMA)

Exponential Moving Average balances recent data with history:

  alpha = 0.2  // Smoothing factor (higher = more responsive)

  function updateRate(currentRate, newSample):
    // Clamp sample to valid range
    clampedSample = clamp(newSample, 0.1, 25.0)
    
    // EMA update
    newRate = (1 - alpha) * currentRate + alpha * clampedSample
    
    return newRate

Learning rules by state:

  State       Action
  -----       ------
  IDLE        Update rate_idle
  ACTIVITY    Update rate_activityGeneric AND profile-specific rate
  CHARGING    Skip (no drain learning)
  SLEEP       Update rate_idle with 0.8x multiplier

Profile-specific rates:
- Require minimum 5 samples before using
- Fall back to rate_activityGeneric if insufficient samples

### 5.2 Pattern Learning

Activity pattern tracks when user typically exercises:

  function learnFromActivitySegment(segment):
    if segment.state != STATE_ACTIVITY:
      return
    
    // Distribute minutes across affected slots
    currentMin = segment.startTMin
    
    while currentMin < segment.endTMin:
      weekday = getWeekday(currentMin)
      slot = getSlot(currentMin)
      
      slotEndMin = getSlotEndTime(currentMin)
      effectiveEnd = min(slotEndMin, segment.endTMin)
      minutesInSlot = effectiveEnd - currentMin
      
      // EMA update for slot
      alpha = 0.3  // Faster learning for patterns
      currentValue = pattern[weekday][slot]
      newValue = (1 - alpha) * currentValue + alpha * minutesInSlot
      pattern[weekday][slot] = min(newValue, 30)  // Cap at slot duration
      
      currentMin = slotEndMin

Weekly decay:

  function applyWeeklyDecay():
    decay = 0.9  // 10 percent decay per week
    
    for day in 0..6:
      for slot in 0..47:
        pattern[day][slot] *= decay

## 6. Forecasting Algorithm

### 6.1 Core Forecast

  function forecast():
    // Get current state
    nowBatt = getBatteryPercent()
    weekday = getWeekday()
    currentSlot = getCurrentSlot()
    endSlot = getEndOfDaySlot()  // e.g., 44 for 22:00
    
    // Get learned rates
    rateIdle = drainRates.idle
    rateActivity = drainRates.activityGeneric
    
    // Calculate drain for each remaining slot
    totalDrain = 0.0
    
    for slot in currentSlot to endSlot:
      expectedActivityMin = pattern[weekday][slot]
      expectedIdleMin = 30 - expectedActivityMin
      
      // Ensure non-negative
      if expectedIdleMin < 0:
        expectedIdleMin = 0
        expectedActivityMin = 30
      
      slotDrain = (expectedActivityMin / 60.0) * rateActivity +
                  (expectedIdleMin / 60.0) * rateIdle
      
      totalDrain += slotDrain
    
    // Calculate predictions
    typical = nowBatt - totalDrain
    conservative = nowBatt - (totalDrain * conservativeFactor)
    optimistic = nowBatt - (totalDrain * optimisticFactor)
    
    // Clamp to 0-100
    typical = clamp(typical, 0, 100)
    conservative = clamp(conservative, 0, 100)
    optimistic = clamp(optimistic, 0, 100)
    
    // Determine risk
    risk = calculateRisk(conservative)
    
    return ForecastResult(...)

### 6.2 Risk Calculation

  function calculateRisk(conservativeBatt):
    if conservativeBatt < redThreshold:    // default 15
      return RISK_HIGH
    else if conservativeBatt < yellowThreshold:  // default 30
      return RISK_MEDIUM
    else:
      return RISK_LOW

### 6.3 Simple Forecast (Low Confidence)

When confidence < 0.5, use idle-only estimate:

  function getSimpleForecast():
    nowBatt = getBatteryPercent()
    hoursRemaining = getMinutesUntilEndOfDay() / 60.0
    
    drain = rateIdle * hoursRemaining
    endBatt = clamp(nowBatt - drain, 0, 100)
    
    return ForecastResult with typical/conservative/optimistic all = endBatt## 7. Confidence Calculation

### 7.1 Rates Confidence

Based on sample counts:

  function getRatesConfidence():
    idleCount = sampleCounts.idle or 0
    actCount = sampleCounts.activityGeneric or 0
    
    // Need ~20 idle samples, ~10 activity samples for full confidence
    idleConf = min(idleCount / 20.0, 1.0)
    actConf = min(actCount / 10.0, 1.0)
    
    // Idle is more important (60 percent)
    return idleConf * 0.6 + actConf * 0.4

### 7.2 Pattern Confidence

Based on slot coverage and activity segments:

  function getPatternConfidence():
    totalSlots = 7 * 48  // 336
    slotsWithData = countSlotsWithData()
    activitySegments = stats.totalActivitySegments
    
    coverageRatio = slotsWithData / totalSlots
    segmentConf = min(activitySegments / 20.0, 1.0)
    
    return coverageRatio * 0.5 + segmentConf * 0.5

### 7.3 Total Confidence

  function calculateConfidence():
    ratesConf = getRatesConfidence()
    patternConf = getPatternConfidence()
    
    // Rates slightly more important
    return ratesConf * 0.6 + patternConf * 0.4

Confidence thresholds:
- Less than 0.5: Show "Learning" mode, simple forecast only
- 0.5 or higher: Show full forecast with range

## 8. Storage

### 8.1 Storage Keys

  Key   Type          Description
  ---   ----          -----------
  seg   Array         Serialized segments
  dr    Dictionary    Drain rates
  pat   Array[7][48]  Activity pattern
  ls    Array         Last snapshot
  st    Dictionary    Statistics

### 8.2 Segment Serialization

Compact array format to save space:

  segment becomes [startTMin, endTMin, startBatt, endBatt, state, profile]

### 8.3 Storage Limits

  Data       Limit      Size Estimate
  ----       -----      -------------
  Segments   300 max    ~7KB
  Pattern    7x48 ints  ~1.3KB
  Rates      ~10 floats ~100B
  Stats      ~10 values ~200B
  Total                 ~10KB

### 8.4 Cleanup

  function cleanupOldSegments(windowDays):
    cutoffMin = now - (windowDays * 24 * 60)
    
    segments = segments.filter(s where s.endTMin >= cutoffMin)
    
    // Ensure max 300 segments
    while segments.size > 300:
      segments.removeFirst()

## 9. Background Service

### 9.1 Temporal Events

Register for periodic background execution:

  function registerBackgroundEvents():
    interval = settings.sampleIntervalMin  // default 15
    interval = max(interval, 5)  // Garmin minimum
    
    nextTime = now + Duration(interval * 60)
    Background.registerForTemporalEvent(nextTime)

### 9.2 Background Task

  function onTemporalEvent():
    // 1. Take snapshot
    logger.logSnapshot()
    
    // 2. Save data
    storage.saveAll()
    
    // 3. Cleanup old data
    storage.cleanupOldSegments(settings.learningWindowDays)
    
    // 4. Apply weekly decay if needed
    if timeSinceLastDecay >= 7 days:
      patternLearner.applyDecay()
      updateLastDecayTime()
    
    // 5. Return status
    Background.exit with status ok

### 9.3 Fallback (No Background)

If background not available:
- Log snapshot only when widget is opened
- Show message: "Open widget daily to learn"
- Confidence increases more slowly## 10. User Interface

### 10.1 Glance View (Widget List)

Compact single-line display:

  Normal:   Now 58% | Tonight 31% (24-36) MED
  Learning: Learning... Now 58% | Est ~45%
            3 days data

### 10.2 Detail View - Page 1 (Main Forecast)

  +---------------------------+
  |     BATTERY BUDGET        |
  |       Now: 58%            |
  |                           |
  |          31               |
  |           %               |
  |    TONIGHT @ 22:00        |
  |                           |
  |    Range: 24 - 36%        |
  |                           |
  |       Risk: MED           |
  |                           |
  |    Confidence: 72%        |
  |         o O o             |
  +---------------------------+

### 10.3 Detail View - Page 2 (Learned Rates)

  +---------------------------+
  |     LEARNED RATES         |
  |                           |
  |     Idle: 0.8%/h          |
  |   Activity: 7.2%/h        |
  |                           |
  |     Run: 8.5%/h           |
  |     Bike: 6.1%/h          |
  |                           |
  |   Rates update auto-      |
  |   matically as you        |
  |   use your watch          |
  |         o o O             |
  +---------------------------+

### 10.4 Detail View - Page 3 (Next Activity)

  +---------------------------+
  |  NEXT TYPICAL ACTIVITY    |
  |                           |
  |         18:00             |
  |                           |
  |     ~45 min typical       |
  |                           |
  |        -> -6%             |
  |                           |
  |   Based on your typical   |
  |   Tuesday pattern         |
  |         o o o             |
  +---------------------------+

## 11. Test Plan

### 11.1 Unit Tests

1. TimeUtil functions (slot calculation, weekday)
2. Segmenter (state change detection, rate calculation)
3. DrainLearner (EMA update, clamping)
4. PatternLearner (slot distribution, decay)
5. Forecaster (prediction math, risk levels)

### 11.2 Integration Tests

1. Day 1: First snapshot recorded
2. Day 3: Multiple segments, "Learning" mode, confidence < 0.5
3. Day 7: Pattern emerging, rates stabilizing
4. Day 14: Full forecast shown, confidence >= 0.5
5. Day 15+: Predictions correlate with actual end-of-day battery

### 11.3 Edge Cases

1. Charging detected: New segment started, no drain learning
2. Long gap (>2h): New segment started
3. Very short segment (<10min): Ignored or merged
4. Battery API unavailable: Fallback to 50%
5. No activity ever: Idle-only forecast
6. Activity profile unknown: Use generic rate

### 11.4 Performance Tests

1. Storage stays under limit after 30 days
2. Widget opens in <500ms
3. Background service completes in <2s
4. Battery impact <1%/day from logging

## 12. Acceptance Criteria

- Widget shows current battery and tonight forecast
- Range (conservative-optimistic) displayed
- Risk level color-coded (green/yellow/red)
- "Learning" mode shown when confidence < 0.5
- Learned rates viewable on second page
- Next typical activity shown on third page
- Settings configurable via Garmin Connect Mobile
- Data persists across app restarts
- Background logging works (where supported)
- Charging periods excluded from drain learning
- Predictions improve over 14-day learning window