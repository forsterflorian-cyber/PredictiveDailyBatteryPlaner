import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;

class BatteryBudgetDetailView extends WatchUi.View {
    
    private var _forecaster as BatteryBudget.Forecaster;
    private var _forecast as BatteryBudget.ForecastResult?;
    private var _lastForecastUpdateSec as Number = 0;
    private var _currentPage as Number = 0;
    private const MAX_PAGES = 3;
    private const FORECAST_REFRESH_INTERVAL_SEC = 60;

    private const PAGE_DOT_RADIUS = 4;
    private const PAGE_DOT_SPACING = 14;
    private const PAGE_DOT_Y_OFFSET = 15;
    private const PAGE_DOT_SAFE_GAP = 6;
    private const NEXT_ACTIVITY_TITLE_FALLBACK = "Next Activity";
    private const NEXT_ACTIVITY_TITLE_MIN = "Next";
    private const BASED_ON_PATTERN_FALLBACK = "Weekly pattern";
    
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
        if (_forecaster.hasMinimumConfidence()) {
            _forecast = _forecaster.forecast();
        } else {
            _forecast = _forecaster.getSimpleForecast();
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
        switch (_currentPage) {
            case 0:
                drawMainForecast(dc, width, height);
                break;
            case 1:
                drawLearnedRates(dc, width, height);
                break;
            case 2:
                drawActivityWindow(dc, width, height);
                break;
        }
        
        // Draw page indicator
        drawPageIndicator(dc, width, height);
    }
    
    // Page 1: Main forecast
    private function drawMainForecast(dc as Dc, width as Number, height as Number) as Void {
        var centerX = width / 2;
        var nowBatt = _forecaster.getCurrentBattery();

        var topPad = getTopPadding(height);
        var contentBottom = getContentBottom(height);

        var titleFont = Graphics.FONT_TINY;
        var nowFont = Graphics.FONT_SMALL;

        var titleH = dc.getFontHeight(titleFont);
        var nowH = dc.getFontHeight(nowFont);

        var y = topPad;

        // Title
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, titleFont, tr(Rez.Strings.AppName), Graphics.TEXT_JUSTIFY_CENTER);
        y += titleH + 4;

        // Current battery
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, nowFont,
            Lang.format("$1$: $2$%", [tr(Rez.Strings.Now), nowBatt]), Graphics.TEXT_JUSTIFY_CENTER);
        y += nowH + 8;

        var bodyTop = y;
        var bodyBottom = contentBottom;

        if (_forecast == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, (bodyTop + bodyBottom) / 2, Graphics.FONT_SMALL,
                tr(Rez.Strings.NoData), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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

        var barHeight = 8;

        var gapLg = 6;
        var gapMd = 4;
        var gapSm = 2;

        var showHint = true;
        var showDays = true;
        var showBar = true;

        var availableH = bottomY - topY;
        if (availableH < 0) { availableH = 0; }

        var totalH = getLearningLayoutHeight(titleH, estimateH, hintH, infoH, barHeight, gapLg, gapMd, gapSm, showHint, showDays, showBar);
        if (totalH > availableH) {
            showBar = false;
            gapLg = 4;
            gapMd = 3;
            totalH = getLearningLayoutHeight(titleH, estimateH, hintH, infoH, barHeight, gapLg, gapMd, gapSm, showHint, showDays, showBar);
        }
        if (totalH > availableH) {
            showHint = false;
            gapLg = 3;
            gapMd = 2;
            totalH = getLearningLayoutHeight(titleH, estimateH, hintH, infoH, barHeight, gapLg, gapMd, gapSm, showHint, showDays, showBar);
        }
        if (totalH > availableH) {
            showDays = false;
            totalH = getLearningLayoutHeight(titleH, estimateH, hintH, infoH, barHeight, gapLg, gapMd, gapSm, showHint, showDays, showBar);
        }
        if (totalH > availableH) {
            titleFont = Graphics.FONT_SMALL;
            estimateFont = Graphics.FONT_TINY;
            titleH = dc.getFontHeight(titleFont);
            estimateH = dc.getFontHeight(estimateFont);
            totalH = getLearningLayoutHeight(titleH, estimateH, hintH, infoH, barHeight, gapLg, gapMd, gapSm, showHint, showDays, showBar);
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
            var barWidth = (width * 0.6).toNumber();
            if (barWidth > 180) { barWidth = 180; }
            if (barWidth < 90) { barWidth = width - 40; }
            if (barWidth < 60) { barWidth = width - 20; }
            if (barWidth < 50) { barWidth = 50; }

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
        var confFont = Graphics.FONT_XTINY;

        var numH = dc.getFontHeight(numFont);
        var percentH = dc.getFontHeight(percentFont);
        var labelH = dc.getFontHeight(labelFont);
        var rangeH = dc.getFontHeight(rangeFont);
        var riskH = dc.getFontHeight(riskFont);
        var confH = dc.getFontHeight(confFont);

        // Confidence anchored just above the page dots
        var confPct = (confidence * 100).toNumber();
        var confStr = Lang.format("$1$: $2$%", [tr(Rez.Strings.Confidence), confPct]);
        var confY = bottomY - confH;
        if (confY < topY) { confY = topY; }

        var stackTop = topY;
        var stackBottom = confY - 8;
        if (stackBottom < stackTop) { stackBottom = stackTop; }

        var gapSm = 2;
        var gapMd = 6;

        var stackH = numH + gapSm + labelH + gapMd + rangeH + gapMd + riskH;
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
        var percentX = centerX + (numW / 2) + 2;
        if ((percentX + percentW) > width) { percentX = width - percentW - 2; }
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
        var contentTop = topPad + titleH + 10;
        var gapAfterIdle = 6;
        var gapBetweenProfile = 4;
        var gapBeforeNote = 10;
        var noteGap = 2;

        var profileCount = 0;
        if (run != null) { profileCount += 1; }
        if (bike != null) { profileCount += 1; }
        if (hike != null) { profileCount += 1; }

        var gapAfterActivity = profileCount > 0 ? 10 : 6;

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
        var titleY = topPad + 2;
        var titleCandidate = tr(Rez.Strings.NextActivity);
        var titleMaxW = getSafeTextWidthAtY(width, height, titleY + (dc.getFontHeight(titleFont) / 2));
        var titleText = fitTextOrFallback(dc, titleCandidate, titleFont, titleMaxW, NEXT_ACTIVITY_TITLE_FALLBACK);
        if (titleText == null) {
            titleFont = Graphics.FONT_XTINY;
            titleMaxW = getSafeTextWidthAtY(width, height, titleY + (dc.getFontHeight(titleFont) / 2));
            titleText = fitTextOrFallback(dc, titleCandidate, titleFont, titleMaxW, NEXT_ACTIVITY_TITLE_FALLBACK);
        }
        if (titleText == null && dc.getTextWidthInPixels(NEXT_ACTIVITY_TITLE_MIN, titleFont) <= titleMaxW) {
            titleText = NEXT_ACTIVITY_TITLE_MIN;
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
        var noteY = contentBottom - noteH;
        var noteMaxW = getSafeTextWidthAtY(width, height, noteY + (noteH / 2));
        var noteText = fitTextOrFallback(dc, noteCandidate, noteFont, noteMaxW, BASED_ON_PATTERN_FALLBACK);
        if (noteText == null) {
            noteY = contentBottom;
        }

        // Content area between title and footer
        var contentTop = titleY + titleH + (titleText != null ? 10 : 4);
        var contentBottomInner = noteY - (noteText != null ? 10 : 0);
        if (contentBottomInner < contentTop) { contentBottomInner = contentTop; }

        if (_forecast == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, (contentTop + contentBottomInner) / 2, Graphics.FONT_SMALL,
                tr(Rez.Strings.NoData), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

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

            var blockH = noneH + 6 + msgH;
            var y = contentTop + ((contentBottomInner - contentTop - blockH) / 2).toNumber();
            if (y < contentTop) { y = contentTop; }

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, noneFont, tr(Rez.Strings.None), Graphics.TEXT_JUSTIFY_CENTER);

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y + noneH + 6, msgFont,
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

            var blockH = timeH + 8 + durH;
            if (drain > 0) { blockH += 10 + drainH; }

            var y = contentTop + ((contentBottomInner - contentTop - blockH) / 2).toNumber();
            if (y < contentTop) { y = contentTop; }

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, timeFont, timeStr, Graphics.TEXT_JUSTIFY_CENTER);
            y += timeH + 8;

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, durFont,
                Lang.format("~$1$ $2$", [duration, tr(Rez.Strings.MinTypical)]), Graphics.TEXT_JUSTIFY_CENTER);
            y += durH;

            // Expected drain
            if (drain > 0) {
                y += 10;
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

    private function getLearningLayoutHeight(titleH as Number, estimateH as Number, hintH as Number, infoH as Number,
                                             barHeight as Number, gapLg as Number, gapMd as Number, gapSm as Number,
                                             showHint as Boolean, showDays as Boolean, showBar as Boolean) as Number {
        var totalH = titleH + gapLg + estimateH;
        if (showHint) { totalH += gapSm + hintH; }
        if (showDays) { totalH += gapLg + infoH; }
        totalH += gapMd + infoH; // confidence line
        if (showBar) { totalH += gapSm + barHeight; }
        return totalH;
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
        if (width != height) { return 10; }
        var edgeBand = (height * 0.2f).toNumber();
        if (y <= edgeBand || y >= (height - edgeBand)) {
            return (width * 0.22f).toNumber();
        }
        return (width * 0.10f).toNumber();
    }

    private function getTopPadding(height as Number) as Number {
        var pad = (height * 0.08).toNumber();
        if (pad < 8) { pad = 8; }
        if (pad > 24) { pad = 24; }
        return pad;
    }

    private function getContentBottom(height as Number) as Number {
        return height - (PAGE_DOT_Y_OFFSET + PAGE_DOT_RADIUS + PAGE_DOT_SAFE_GAP);
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
        var totalWidth = (MAX_PAGES - 1) * PAGE_DOT_SPACING;
        var startX = (width - totalWidth) / 2;
        var y = height - PAGE_DOT_Y_OFFSET;
        
        for (var i = 0; i < MAX_PAGES; i++) {
            var x = startX + i * PAGE_DOT_SPACING;
            if (i == _currentPage) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, PAGE_DOT_RADIUS);
            } else {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, PAGE_DOT_RADIUS - 1);
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
