import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;

class BatteryBudgetDetailView extends WatchUi.View {
    
    private var _forecaster as BatteryBudget.Forecaster;
    private var _forecast as BatteryBudget.ForecastResult?;
    private var _lastForecastUpdateSec as Number = 0;
    private var _currentPage as Number = 0;
    private const MAX_PAGES = 4;
    private const FORECAST_REFRESH_INTERVAL_SEC = 60;
    private const PAGE_DOT_RADIUS_FACTOR = 0.016f;
    private const PAGE_DOT_SPACING_FACTOR = 0.058f;
    private const PAGE_DOT_Y_OFFSET_FACTOR = 0.060f;
    private const PAGE_DOT_SAFE_GAP_FACTOR = 0.022f;
    
    function initialize() {
        View.initialize();
        _forecaster = new BatteryBudget.Forecaster();
    }
    
    function onShow() as Void {
        // Log snapshot when view shown
        var logger = new BatteryBudget.SnapshotLogger();
        if (logger.shouldTakeSnapshot()) {
            logger.logSnapshot();
        }

        refreshForecastIfNeeded(true);
    }
    
    function updateForecast() as Void {
        try {
            if (_forecaster.hasMinimumConfidence()) {
                _forecast = _forecaster.forecast();
            } else {
                _forecast = _forecaster.getSimpleForecast();
            }
        } catch (ex) {
            try {
                _forecast = _forecaster.getSimpleForecast();
            } catch (ex2) {
                _forecast = null;
            }
        }
        _lastForecastUpdateSec = nowEpochSeconds();
        WatchUi.requestUpdate();
    }

    private function refreshForecastIfNeeded(force as Boolean) as Void {
        if (force || isForecastStale()) {
            updateForecast();
        } else {
            WatchUi.requestUpdate();
        }
    }

    private function isForecastStale() as Boolean {
        if (_forecast == null || _lastForecastUpdateSec <= 0) {
            return true;
        }
        var nowSec = nowEpochSeconds();
        return (nowSec - _lastForecastUpdateSec) >= FORECAST_REFRESH_INTERVAL_SEC;
    }

    private function nowEpochSeconds() as Number {
        return Time.now().value().toNumber();
    }
    
    function onUpdate(dc as Dc) as Void {
        // Clear background
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        
        var width = dc.getWidth();
        var height = dc.getHeight();
        
        // Draw based on current page
        // 0=Forecast  1=History/Trend  2=Rates  3=Activity
        switch (_currentPage) {
            case 0:
                drawMainForecast(dc, width, height);
                break;
            case 1:
                drawHistoryTrend(dc, width, height);
                break;
            case 2:
                drawLearnedRates(dc, width, height);
                break;
            case 3:
                drawActivityWindow(dc, width, height);
                break;
        }
        
        // Draw page indicator
        drawPageIndicator(dc, width, height);
    }
    
    // Page 1: History / Battery trend
    // Draws a line chart of the last 24 battery readings and a solar-gain estimate.
    private function drawHistoryTrend(dc as Dc, width as Number, height as Number) as Void {
        var centerX = width / 2;
        var topPad = getTopPadding(height);
        var contentBottom = getContentBottom(height);

        var titleFont = Graphics.FONT_TINY;
        var noteFont  = Graphics.FONT_XTINY;
        var titleH = dc.getFontHeight(titleFont);
        var noteH  = dc.getFontHeight(noteFont);

        // Title
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, topPad, titleFont, tr(Rez.Strings.HistoryTitle), Graphics.TEXT_JUSTIFY_CENTER);

        // Solar-gain estimate (bottom anchor, above page dots)
        var solarStr = buildSolarGainStr();
        var noteY = contentBottom - noteH;
        if (noteY < topPad) { noteY = topPad; }
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, noteY, noteFont, solarStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Graph area between title and solar note
        var graphGap = scaleByHeight(height, 0.018f, 3, 10);
        var graphPadX = scaleByWidth(width, 0.04f, 6, 20);
        var graphTop    = topPad + titleH + graphGap;
        var graphBottom = noteY - graphGap;
        var graphLeft   = graphPadX;
        var graphRight  = width - graphPadX;
        var graphW      = graphRight - graphLeft;
        var graphH      = graphBottom - graphTop;
        if (graphH < scaleByHeight(height, 0.10f, 20, 64) || graphW < scaleByWidth(width, 0.16f, 20, 90)) { return; }

        // Load history: flat array [tMin1, batt1, tMin2, batt2, ...]
        var history = BatteryBudget.StorageManager.getInstance().getBatteryHistory();
        var count = history.size() / 2; // number of data points

        if (count < 2) {
            // Not enough data yet
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, graphTop + graphH / 2, Graphics.FONT_SMALL,
                tr(Rez.Strings.NoData),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Find time and battery range
        var tFirst = history[0] as Number;
        var tLast  = history[(count - 1) * 2] as Number;
        var tSpan  = tLast - tFirst;
        if (tSpan <= 0) { tSpan = 1; }

        // Fixed battery display range (always 0-100 %; makes curves comparable)
        var battMin = 0;
        var battMax = 100;
        var battSpan = battMax - battMin;

        // Reference grid lines at 25 % / 50 % / 75 %
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var refLevels = [25, 50, 75];
        for (var i = 0; i < refLevels.size(); i++) {
            var gy = graphBottom - ((refLevels[i] - battMin) * graphH / battSpan);
            dc.drawLine(graphLeft, gy, graphRight, gy);
        }

        // Map a data-point index to screen coordinates
        // Returns [x, y] stored in a small 2-element array to avoid object allocation
        var prevX = -1;
        var prevY = -1;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        for (var i = 0; i < count; i++) {
            var tMin  = history[i * 2]     as Number;
            var batt  = history[i * 2 + 1] as Number;

            var px = graphLeft + ((tMin - tFirst) * graphW / tSpan);
            var py = graphBottom - ((batt - battMin) * graphH / battSpan);

            // Clamp to graph area
            if (px < graphLeft)   { px = graphLeft; }
            if (px > graphRight)  { px = graphRight; }
            if (py < graphTop)    { py = graphTop; }
            if (py > graphBottom) { py = graphBottom; }

            if (prevX >= 0) {
                dc.drawLine(prevX, prevY, px, py);
            } else {
                dc.drawPoint(px, py); // first point
            }
            prevX = px;
            prevY = py;
        }

        // Y-axis labels at 0 % and 100 %
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(graphLeft, graphBottom - noteH, noteFont, "0%", Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(graphLeft, graphTop, noteFont, "100%", Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Build the solar-gain estimate string for the last 24 h.
    private function buildSolarGainStr() as String {
        try {
            var rates = BatteryBudget.StorageManager.getInstance().getDrainRates();
            var sgv = rates[:solarGainRate];
            var rsv = rates[:recentSolar] as Number;
            if (sgv != null && rsv > 10) {
                var gainRate = sgv as Float;
                var fraction = rsv.toFloat() / 100.0f;
                // 24 h estimate, 50 % conservative
                var gain24h = gainRate * fraction * 24.0f * 0.5f;
                var intPart  = gain24h.toNumber();
                var decPart  = ((gain24h - intPart.toFloat()) * 10 + 0.5f).toNumber().abs();
                if (decPart > 9) { decPart = 9; }
                return tr(Rez.Strings.SolarGain24h) + ": +" + intPart.toString() + "." + decPart.toString() + "%";
            }
        } catch (ex) {}
        return tr(Rez.Strings.SolarGain24h) + ": --";
    }

    // Page 0: Main forecast
    private function drawMainForecast(dc as Dc, width as Number, height as Number) as Void {
        var centerX = width / 2;
        var nowBatt = _forecaster.getCurrentBattery();

        var topPad = getTopPadding(height);
        var contentBottom = getContentBottom(height);

        var titleFont = Graphics.FONT_TINY;
        var nowFont = Graphics.FONT_SMALL;

        var titleH = dc.getFontHeight(titleFont);
        var nowH = dc.getFontHeight(nowFont);
        var titleGap = scaleByHeight(height, 0.012f, 2, 6);
        var nowGap = scaleByHeight(height, 0.025f, 4, 12);

        var y = topPad;

        // Title
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, titleFont, tr(Rez.Strings.AppName), Graphics.TEXT_JUSTIFY_CENTER);
        y += titleH + titleGap;

        // Current battery
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, nowFont,
            Lang.format("$1$: $2$%", [tr(Rez.Strings.Now), nowBatt]), Graphics.TEXT_JUSTIFY_CENTER);
        y += nowH + nowGap;

        var bodyTop = y;
        var bodyBottom = contentBottom;

        if (_forecast == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, (bodyTop + bodyBottom) / 2, Graphics.FONT_SMALL,
                tr(Rez.Strings.Learning), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var forecast = _forecast as BatteryBudget.ForecastResult;
        var confidence = forecast[:confidence] as Float;

        if (confidence < BatteryBudget.CONFIDENCE_THRESHOLD) {
            // Learning mode
            drawLearningMode(dc, centerX, width, bodyTop, bodyBottom, forecast);
        } else {
            // Full forecast
            drawFullForecast(dc, centerX, width, bodyTop, bodyBottom, forecast);
        }
    }
    
    // Draw learning mode display
    private function drawLearningMode(dc as Dc, centerX as Number, width as Number, topY as Number, bottomY as Number,
                                      forecast as BatteryBudget.ForecastResult) as Void {
        var typical = forecast[:typical] as Number;
        var confidence = forecast[:confidence] as Float;
        var days = _forecaster.getDaysCollected();
        var confPct = (confidence * 100).toNumber();

        var titleFont = Graphics.FONT_MEDIUM;
        var estimateFont = Graphics.FONT_SMALL;
        var hintFont = Graphics.FONT_TINY;
        var infoFont = Graphics.FONT_TINY;

        var titleH = dc.getFontHeight(titleFont);
        var estimateH = dc.getFontHeight(estimateFont);
        var hintH = dc.getFontHeight(hintFont);
        var infoH = dc.getFontHeight(infoFont);

        var availableH = bottomY - topY;
        if (availableH < 0) { availableH = 0; }

        var barHeight = scaleByHeight(availableH, 0.040f, 5, 11);
        var gapLg = scaleByHeight(availableH, 0.032f, 2, 8);
        var gapMd = scaleByHeight(availableH, 0.022f, 1, 6);
        var gapSm = scaleByHeight(availableH, 0.012f, 1, 4);

        var showHint = true;
        var showDays = true;
        var showBar = true;

        var totalH = getLearningLayoutHeight(
            titleH,
            estimateH,
            infoH,
            getLearningOptionalBlocks(gapSm, hintH, gapLg, infoH, barHeight, showHint, showDays, showBar),
            gapLg,
            gapMd
        );
        if (totalH > availableH) {
            showBar = false;
            gapLg = scaleByHeight(availableH, 0.024f, 2, 6);
            gapMd = scaleByHeight(availableH, 0.018f, 1, 4);
            totalH = getLearningLayoutHeight(
                titleH,
                estimateH,
                infoH,
                getLearningOptionalBlocks(gapSm, hintH, gapLg, infoH, barHeight, showHint, showDays, showBar),
                gapLg,
                gapMd
            );
        }
        if (totalH > availableH) {
            showHint = false;
            gapLg = scaleByHeight(availableH, 0.018f, 1, 4);
            gapMd = scaleByHeight(availableH, 0.012f, 1, 3);
            totalH = getLearningLayoutHeight(
                titleH,
                estimateH,
                infoH,
                getLearningOptionalBlocks(gapSm, hintH, gapLg, infoH, barHeight, showHint, showDays, showBar),
                gapLg,
                gapMd
            );
        }
        if (totalH > availableH) {
            showDays = false;
            totalH = getLearningLayoutHeight(
                titleH,
                estimateH,
                infoH,
                getLearningOptionalBlocks(gapSm, hintH, gapLg, infoH, barHeight, showHint, showDays, showBar),
                gapLg,
                gapMd
            );
        }
        if (totalH > availableH) {
            titleFont = Graphics.FONT_SMALL;
            estimateFont = Graphics.FONT_TINY;
            titleH = dc.getFontHeight(titleFont);
            estimateH = dc.getFontHeight(estimateFont);
            totalH = getLearningLayoutHeight(
                titleH,
                estimateH,
                infoH,
                getLearningOptionalBlocks(gapSm, hintH, gapLg, infoH, barHeight, showHint, showDays, showBar),
                gapLg,
                gapMd
            );
        }

        var y = topY + ((availableH - totalH) / 2).toNumber();
        if (y < topY) { y = topY; }

        // Big "Learning" indicator
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, titleFont, tr(Rez.Strings.LearningTitle), Graphics.TEXT_JUSTIFY_CENTER);
        y += titleH + gapLg;

        // Estimated (idle-only)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, estimateFont,
            Lang.format("$1$: ~$2$%", [tr(Rez.Strings.Tonight), typical]), Graphics.TEXT_JUSTIFY_CENTER);
        y += estimateH;

        if (showHint) {
            y += gapSm;
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, hintFont, tr(Rez.Strings.IdleOnlyEstimate), Graphics.TEXT_JUSTIFY_CENTER);
            y += hintH;
        }

        if (showDays) {
            y += gapLg;
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, infoFont,
                Lang.format("$1$ $2$", [days, tr(Rez.Strings.DaysCollected)]), Graphics.TEXT_JUSTIFY_CENTER);
            y += infoH;
        }

        // Confidence label
        y += gapMd;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, infoFont,
            Lang.format("$1$: $2$%", [tr(Rez.Strings.Confidence), confPct]), Graphics.TEXT_JUSTIFY_CENTER);
        y += infoH;

        if (showBar) {
            y += gapSm;

            // Progress bar
            var maxBarWidth = scaleByWidth(width, 0.78f, 60, width);
            var minBarWidth = scaleByWidth(width, 0.36f, 42, maxBarWidth);
            var barWidth = scaleByWidth(width, 0.60f, minBarWidth, maxBarWidth);

            var barX = centerX - barWidth / 2;
            var barY = y;

            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(barX, barY, barWidth, barHeight);

            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barX + 1, barY + 1, ((barWidth - 2) * confidence).toNumber(), barHeight - 2);
        }
    }
    
    // Draw full forecast display
    private function drawFullForecast(dc as Dc, centerX as Number, width as Number, topY as Number, bottomY as Number,
                                      forecast as BatteryBudget.ForecastResult) as Void {
        var typical = forecast[:typical] as Number;
        var conservative = forecast[:conservative] as Number;
        var optimistic = forecast[:optimistic] as Number;
        var risk = forecast[:risk] as BatteryBudget.RiskLevel;
        var confidence = forecast[:confidence] as Float;
        var budgetMin = forecast[:remainingActivityMinutes] as Number;

        // "Tonight" label
        var endTimeLabel = "22:00";
        var endTimeStr = BatteryBudget.StorageManager.getInstance().getSetting(:endOfDayTime);
        if (endTimeStr instanceof String) {
            endTimeLabel = endTimeStr as String;
        }

        var numFont = Graphics.FONT_NUMBER_HOT;
        var percentFont = Graphics.FONT_SMALL;
        var labelFont = Graphics.FONT_TINY;
        var rangeFont = Graphics.FONT_SMALL;
        var riskFont = Graphics.FONT_MEDIUM;
        var budgetFont = Graphics.FONT_TINY;
        var confFont = Graphics.FONT_XTINY;

        var numH = dc.getFontHeight(numFont);
        var percentH = dc.getFontHeight(percentFont);
        var labelH = dc.getFontHeight(labelFont);
        var rangeH = dc.getFontHeight(rangeFont);
        var riskH = dc.getFontHeight(riskFont);
        var budgetH = dc.getFontHeight(budgetFont);
        var confH = dc.getFontHeight(confFont);
        var contentH = bottomY - topY;
        if (contentH < 0) { contentH = 0; }

        // Confidence anchored just above the page dots
        var confPct = (confidence * 100).toNumber();
        var confStr = Lang.format("$1$: $2$%", [tr(Rez.Strings.Confidence), confPct]);
        var confY = bottomY - confH;
        if (confY < topY) { confY = topY; }

        var stackTop = topY;
        var stackBottom = confY - scaleByHeight(contentH, 0.018f, 3, 10);
        if (stackBottom < stackTop) { stackBottom = stackTop; }

        var gapSm = scaleByHeight(contentH, 0.012f, 1, 4);
        var gapMd = scaleByHeight(contentH, 0.026f, 2, 10);

        // Include budget line when there is meaningful budget (>0 min)
        var showBudget = budgetMin > 0;
        var stackH = numH + gapSm + labelH + gapMd + rangeH + gapMd + riskH;
        if (showBudget) { stackH += gapMd + budgetH; }

        var availableStackH = stackBottom - stackTop;
        if (availableStackH < 0) { availableStackH = 0; }
        if (showBudget && stackH > availableStackH) {
            showBudget = false;
            stackH = numH + gapSm + labelH + gapMd + rangeH + gapMd + riskH;
        }
        if (stackH > availableStackH) {
            gapMd = scaleByHeight(contentH, 0.014f, 1, 4);
            gapSm = scaleByHeight(contentH, 0.008f, 1, 3);
            stackH = numH + gapSm + labelH + gapMd + rangeH + gapMd + riskH;
            if (showBudget && stackH + gapMd + budgetH > availableStackH) {
                showBudget = false;
            }
            if (showBudget) { stackH += gapMd + budgetH; }
        }

        var y = stackTop + ((stackBottom - stackTop - stackH) / 2).toNumber();
        if (y < stackTop) { y = stackTop; }

        // Big tonight value
        var numStr = typical.toString();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, numFont, numStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Percent sign positioned relative to the number width
        var numW = dc.getTextWidthInPixels(numStr, numFont);
        var percentStr = "%";
        var percentW = dc.getTextWidthInPixels(percentStr, percentFont);
        var percentGap = scaleByWidth(width, 0.008f, 1, 4);
        var rightPad = scaleByWidth(width, 0.012f, 1, 6);
        var percentX = centerX + (numW / 2) + percentGap;
        if ((percentX + percentW) > (width - rightPad)) {
            percentX = width - percentW - rightPad;
        }
        var percentY = y + ((numH - percentH) / 2).toNumber();
        dc.drawText(percentX, percentY, percentFont, percentStr, Graphics.TEXT_JUSTIFY_LEFT);

        y += numH + gapSm;

        // Tonight label
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, labelFont,
            Lang.format("$1$ @ $2$", [tr(Rez.Strings.Tonight), endTimeLabel]), Graphics.TEXT_JUSTIFY_CENTER);
        y += labelH + gapMd;

        // Range
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, rangeFont,
            Lang.format("$1$: $2$ - $3$%", [tr(Rez.Strings.Range), conservative, optimistic]), Graphics.TEXT_JUSTIFY_CENTER);
        y += rangeH + gapMd;

        // Risk
        var riskColor = BatteryBudget.Forecaster.riskToColor(risk);
        var riskStr = BatteryBudget.Forecaster.riskToString(risk);

        dc.setColor(riskColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, riskFont,
            Lang.format("$1$: $2$", [tr(Rez.Strings.Risk), riskStr]), Graphics.TEXT_JUSTIFY_CENTER);
        y += riskH + gapMd;

        // Activity budget line: "Budget: Xh Ym" or "Budget: Ym"
        if (showBudget) {
            var budgetLabel = tr(Rez.Strings.LabelBudget);
            var unitHour = tr(Rez.Strings.UnitHourShort);
            var unitMinute = tr(Rez.Strings.UnitMinuteShort);
            var budgetStr;
            if (budgetMin >= 60) {
                var bh = budgetMin / 60;
                var bm = budgetMin - bh * 60;
                budgetStr = Lang.format("$1$: $2$$3$ $4$$5$", [budgetLabel, bh, unitHour, bm, unitMinute]);
            } else {
                budgetStr = Lang.format("$1$: $2$$3$", [budgetLabel, budgetMin, unitMinute]);
            }
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, budgetFont, budgetStr, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Confidence (bottom)
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, confY, confFont, confStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Page 2: Learned rates
    private function drawLearnedRates(dc as Dc, width as Number, height as Number) as Void {
        var centerX = width / 2;
        var topPad = getTopPadding(height);
        var contentBottom = getContentBottom(height);

        var titleFont = Graphics.FONT_TINY;
        var titleH = dc.getFontHeight(titleFont);

        // Title
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, topPad, titleFont, tr(Rez.Strings.LearnedRates), Graphics.TEXT_JUSTIFY_CENTER);

        // Get rates
        var rates = _forecaster.getLearnedRatesDisplay();
        var idle = rates[:idle] as Float;
        var activity = rates[:activity] as Float;
        var run = rates[:run];
        var bike = rates[:bike];
        var hike = rates[:hike];

        var smallFont = Graphics.FONT_SMALL;
        var tinyFont = Graphics.FONT_TINY;
        var noteFont = Graphics.FONT_XTINY;

        var smallH = dc.getFontHeight(smallFont);
        var tinyH = dc.getFontHeight(tinyFont);
        var noteH = dc.getFontHeight(noteFont);

        // Layout: center all lines between title and page dots
        var contentTop = topPad + titleH + scaleByHeight(height, 0.028f, 5, 14);
        var gapAfterIdle = scaleByHeight(height, 0.018f, 3, 8);
        var gapBetweenProfile = scaleByHeight(height, 0.014f, 2, 6);
        var gapBeforeNote = scaleByHeight(height, 0.032f, 6, 16);
        var noteGap = scaleByHeight(height, 0.008f, 1, 4);

        var profileCount = 0;
        if (run != null) { profileCount += 1; }
        if (bike != null) { profileCount += 1; }
        if (hike != null) { profileCount += 1; }

        var gapAfterActivity = profileCount > 0
            ? scaleByHeight(height, 0.032f, 6, 14)
            : gapAfterIdle;

        var profilesH = 0;
        if (profileCount > 0) {
            profilesH = profileCount * tinyH + (profileCount - 1) * gapBetweenProfile;
        }

        var totalH = smallH + gapAfterIdle + smallH + gapAfterActivity + profilesH + gapBeforeNote + (noteH * 2) + noteGap;
        var y = contentTop + ((contentBottom - contentTop - totalH) / 2).toNumber();
        if (y < contentTop) { y = contentTop; }

        // Idle rate
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, smallFont,
            Lang.format("$1$: $2$%$3$", [tr(Rez.Strings.IdleRate), formatRate(idle), tr(Rez.Strings.PerHour)]), Graphics.TEXT_JUSTIFY_CENTER);
        y += smallH + gapAfterIdle;

        // Activity rate
        dc.drawText(centerX, y, smallFont,
            Lang.format("$1$: $2$%$3$", [tr(Rez.Strings.ActivityRate), formatRate(activity), tr(Rez.Strings.PerHour)]), Graphics.TEXT_JUSTIFY_CENTER);
        y += smallH + gapAfterActivity;

        // Profile-specific rates if available
        if (profileCount > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            var drawnProfiles = 0;

            if (run != null) {
                dc.drawText(centerX, y, tinyFont,
                    Lang.format("$1$: $2$%$3$", [tr(Rez.Strings.RunRate), formatRate(run as Float), tr(Rez.Strings.PerHour)]), Graphics.TEXT_JUSTIFY_CENTER);
                drawnProfiles += 1;
                y += tinyH + (drawnProfiles < profileCount ? gapBetweenProfile : 0);
            }

            if (bike != null) {
                dc.drawText(centerX, y, tinyFont,
                    Lang.format("$1$: $2$%$3$", [tr(Rez.Strings.BikeRate), formatRate(bike as Float), tr(Rez.Strings.PerHour)]), Graphics.TEXT_JUSTIFY_CENTER);
                drawnProfiles += 1;
                y += tinyH + (drawnProfiles < profileCount ? gapBetweenProfile : 0);
            }

            if (hike != null) {
                dc.drawText(centerX, y, tinyFont,
                    Lang.format("$1$: $2$%$3$", [tr(Rez.Strings.HikeRate), formatRate(hike as Float), tr(Rez.Strings.PerHour)]), Graphics.TEXT_JUSTIFY_CENTER);
                drawnProfiles += 1;
                y += tinyH;
            }
        }

        y += gapBeforeNote;

        // Note about learning
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, noteFont,
            tr(Rez.Strings.RatesAutoLine1), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(centerX, y + noteH + noteGap, noteFont,
            tr(Rez.Strings.RatesAutoLine2), Graphics.TEXT_JUSTIFY_CENTER);
    }
    // Page 3: Next activity window
    private function drawActivityWindow(dc as Dc, width as Number, height as Number) as Void {
        var centerX = width / 2;
        var topPad = getTopPadding(height);
        var contentBottom = getContentBottom(height);

        var titleFont = Graphics.FONT_TINY;
        var titleY = topPad + scaleByHeight(height, 0.010f, 1, 4);
        var titleCandidate = tr(Rez.Strings.NextActivity);
        var titleFallback = tr(Rez.Strings.NextActivityShort);
        var titleMin = tr(Rez.Strings.NextActivityMin);
        var titleMaxW = getSafeTextWidthAtY(width, height, titleY + (dc.getFontHeight(titleFont) / 2));
        var titleText = fitTextOrFallback(dc, titleCandidate, titleFont, titleMaxW, titleFallback);
        if (titleText == null) {
            titleFont = Graphics.FONT_XTINY;
            titleMaxW = getSafeTextWidthAtY(width, height, titleY + (dc.getFontHeight(titleFont) / 2));
            titleText = fitTextOrFallback(dc, titleCandidate, titleFont, titleMaxW, titleFallback);
        }
        if (titleText == null && dc.getTextWidthInPixels(titleMin, titleFont) <= titleMaxW) {
            titleText = titleMin;
        }
        var titleH = titleText != null ? dc.getFontHeight(titleFont) : 0;

        // Title
        if (titleText != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, titleY, titleFont, titleText as String, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Footer note
        var noteFont = Graphics.FONT_XTINY;
        var noteH = dc.getFontHeight(noteFont);
        var noteCandidate = tr(Rez.Strings.BasedOnPattern);
        var noteFallback = tr(Rez.Strings.BasedOnPatternShort);
        var noteY = contentBottom - noteH;
        var noteMaxW = getSafeTextWidthAtY(width, height, noteY + (noteH / 2));
        var noteText = fitTextOrFallback(dc, noteCandidate, noteFont, noteMaxW, noteFallback);
        if (noteText == null) {
            noteY = contentBottom;
        }

        // Content area between title and footer
        var topGap = titleText != null
            ? scaleByHeight(height, 0.034f, 4, 12)
            : scaleByHeight(height, 0.016f, 2, 6);
        var bottomGap = noteText != null ? scaleByHeight(height, 0.028f, 4, 12) : 0;
        var contentTop = titleY + titleH + topGap;
        var contentBottomInner = noteY - bottomGap;
        if (contentBottomInner < contentTop) { contentBottomInner = contentTop; }

        if (_forecast == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, (contentTop + contentBottomInner) / 2, Graphics.FONT_SMALL,
                tr(Rez.Strings.Learning), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            if (noteText != null) {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, noteY, noteFont, noteText as String, Graphics.TEXT_JUSTIFY_CENTER);
            }
            return;
        }

        var forecast = _forecast as Dictionary;
        var nextTime = forecast[:nextActivityTime];
        var nextDuration = forecast[:nextActivityDuration];
        var nextDrain = forecast[:nextActivityDrain];

        if (nextTime == null || nextDuration == null) {
            // No predicted activity
            var noneFont = Graphics.FONT_MEDIUM;
            var msgFont = Graphics.FONT_SMALL;
            var noneH = dc.getFontHeight(noneFont);
            var msgH = dc.getFontHeight(msgFont);
            var noneGap = scaleByHeight(height, 0.020f, 2, 8);

            var blockH = noneH + noneGap + msgH;
            var y = contentTop + ((contentBottomInner - contentTop - blockH) / 2).toNumber();
            if (y < contentTop) { y = contentTop; }

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, noneFont, tr(Rez.Strings.None), Graphics.TEXT_JUSTIFY_CENTER);

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y + noneH + noneGap, msgFont,
                tr(Rez.Strings.NoActivityPredicted), Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            // Show next activity window
            var slotIndex = nextTime as Number;
            var duration = nextDuration as Number;
            var drain = nextDrain != null ? nextDrain as Number : 0;

            var timeStr = BatteryBudget.TimeUtil.formatSlotTime(slotIndex);

            var timeFont = Graphics.FONT_LARGE;
            var durFont = Graphics.FONT_SMALL;
            var drainFont = Graphics.FONT_MEDIUM;

            var timeH = dc.getFontHeight(timeFont);
            var durH = dc.getFontHeight(durFont);
            var drainH = dc.getFontHeight(drainFont);
            var gapAfterTime = scaleByHeight(height, 0.026f, 3, 10);
            var gapBeforeDrain = scaleByHeight(height, 0.028f, 4, 12);

            var blockH = timeH + gapAfterTime + durH;
            if (drain > 0) { blockH += gapBeforeDrain + drainH; }

            var y = contentTop + ((contentBottomInner - contentTop - blockH) / 2).toNumber();
            if (y < contentTop) { y = contentTop; }

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, timeFont, timeStr, Graphics.TEXT_JUSTIFY_CENTER);
            y += timeH + gapAfterTime;

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, durFont,
                Lang.format("~$1$ $2$", [duration, tr(Rez.Strings.MinTypical)]), Graphics.TEXT_JUSTIFY_CENTER);
            y += durH;

            // Expected drain
            if (drain > 0) {
                y += gapBeforeDrain;
                dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, y, drainFont,
                    "-> -" + drain + "%", Graphics.TEXT_JUSTIFY_CENTER);
            }
        }

        // Today's pattern summary
        if (noteText != null) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, noteY, noteFont, noteText as String, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function getLearningLayoutHeight(titleH as Number, estimateH as Number, infoH as Number,
                                             optionalBlocks as Array<Number>, gapLg as Number, gapMd as Number) as Number {
        return titleH + gapLg + estimateH + optionalBlocks[0] + optionalBlocks[1] + gapMd + infoH + optionalBlocks[2];
    }

    private function getLearningOptionalBlocks(gapSm as Number, hintH as Number, gapLg as Number, infoH as Number,
                                               barHeight as Number, showHint as Boolean, showDays as Boolean,
                                               showBar as Boolean) as Array<Number> {
        return [
            showHint ? (gapSm + hintH) : 0,
            showDays ? (gapLg + infoH) : 0,
            showBar ? (gapSm + barHeight) : 0
        ];
    }

    private function clampNumber(value as Number, minVal as Number, maxVal as Number) as Number {
        if (value < minVal) { return minVal; }
        if (value > maxVal) { return maxVal; }
        return value;
    }

    private function scaleByHeight(height as Number, factor as Float, minVal as Number, maxVal as Number) as Number {
        var scaled = (height.toFloat() * factor + 0.5f).toNumber();
        return clampNumber(scaled, minVal, maxVal);
    }

    private function scaleByWidth(width as Number, factor as Float, minVal as Number, maxVal as Number) as Number {
        var scaled = (width.toFloat() * factor + 0.5f).toNumber();
        return clampNumber(scaled, minVal, maxVal);
    }

    private function getPageDotRadius(height as Number) as Number {
        return scaleByHeight(height, PAGE_DOT_RADIUS_FACTOR, 2, 6);
    }

    private function getPageDotSpacing(width as Number, height as Number, radius as Number) as Number {
        var baseSpacing = scaleByWidth(width, PAGE_DOT_SPACING_FACTOR, radius * 3, radius * 5);
        var minSpacing = radius * 3;
        if (baseSpacing < minSpacing) { return minSpacing; }
        return baseSpacing;
    }

    private function getPageIndicatorY(height as Number) as Number {
        var offset = scaleByHeight(height, PAGE_DOT_Y_OFFSET_FACTOR, 10, 28);
        return height - offset;
    }

    private function fitTextOrFallback(dc as Dc, text as String, font, maxWidth as Number, fallback as String) as String? {
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) {
            return text;
        }
        if (dc.getTextWidthInPixels(fallback, font) <= maxWidth) {
            return fallback;
        }
        return null;
    }

    private function getSafeTextWidthAtY(width as Number, height as Number, y as Number) as Number {
        var inset = getRoundInsetAtY(width, height, y);
        var safeWidth = width - (inset * 2);
        if (safeWidth < 48) { safeWidth = 48; }
        return safeWidth;
    }

    private function getRoundInsetAtY(width as Number, height as Number, y as Number) as Number {
        // Conservative inset curve for round screens; safe on square screens too.
        if (width != height) { return scaleByWidth(width, 0.035f, 6, 14); }
        var edgeBand = scaleByHeight(height, 0.20f, 14, 96);
        if (y <= edgeBand || y >= (height - edgeBand)) {
            return (width * 0.22f).toNumber();
        }
        return (width * 0.10f).toNumber();
    }

    private function getTopPadding(height as Number) as Number {
        return scaleByHeight(height, 0.08f, 8, 24);
    }

    private function getContentBottom(height as Number) as Number {
        var radius = getPageDotRadius(height);
        var safeGap = scaleByHeight(height, PAGE_DOT_SAFE_GAP_FACTOR, 3, 10);
        return getPageIndicatorY(height) - radius - safeGap;
    }

    // Format rate with one decimal (proper rounding)
    private function formatRate(rate as Float) as String {
        var intPart = rate.toNumber();
        var decPart = ((rate - intPart) * 10 + 0.5f).toNumber().abs();
        if (decPart > 9) { decPart = 9; }
        return intPart.toString() + "." + decPart.toString();
    }
    
    // Draw page indicator dots
    private function drawPageIndicator(dc as Dc, width as Number, height as Number) as Void {
        var radius = getPageDotRadius(height);
        var spacing = getPageDotSpacing(width, height, radius);
        var totalWidth = (MAX_PAGES - 1) * spacing;
        var startX = (width - totalWidth) / 2;
        var y = getPageIndicatorY(height);
        
        for (var i = 0; i < MAX_PAGES; i++) {
            var x = startX + i * spacing;
            if (i == _currentPage) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, radius);
            } else {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                var inactiveRadius = radius - 1;
                if (inactiveRadius < 1) { inactiveRadius = 1; }
                dc.fillCircle(x, y, inactiveRadius);
            }
        }
    }
    
    // Navigate to next page
    function nextPage() as Void {
        _currentPage = (_currentPage + 1) % MAX_PAGES;
        refreshForecastIfNeeded(false);
    }
    
    // Navigate to previous page
    function previousPage() as Void {
        _currentPage = (_currentPage - 1 + MAX_PAGES) % MAX_PAGES;
        refreshForecastIfNeeded(false);
    }
    
    // Get current page
    function getCurrentPage() as Number {
        return _currentPage;
    }

    private function tr(resourceId as Lang.ResourceId) as String {
        return WatchUi.loadResource(resourceId) as String;
    }
}
