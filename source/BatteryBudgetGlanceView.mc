import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Application.Storage;

(:glance)
class BatteryBudgetGlanceView extends WatchUi.GlanceView {

    private const DEFAULT_END_OF_DAY = "22:00";
    private const ALERT_COLOR_HIGH_DRAIN = 0xFF6600;
    private const ALERT_COLOR_LOW_BUDGET = 0xFFB000;
    private const BUDGET_COLOR_OK = 0x3399FF;
    private const RISK_CODE_LOW = "LOW";
    private const RISK_CODE_MEDIUM = "MED";
    private const RISK_CODE_HIGH = "HIGH";
    private const LABEL_NOW = "Now";
    private const LABEL_EOD = "EOD";
    private const LABEL_RISK = "Risk";
    private const LABEL_LEARNING = "Learning...";
    private const LABEL_WAIT_DATA = "Waiting for data";
    private const LABEL_DAYS_SHORT = "d";
    private const LABEL_HIGH_DRAIN = "! High background drain";
    private const LABEL_BUDGET = "Budget";
    private const LABEL_HOUR_SHORT = "h";
    private const LABEL_MINUTE_SHORT = "m";
    private const LABEL_NOW_DE = "Jetzt";
    private const LABEL_RISK_DE = "Risiko";
    private const LABEL_LEARNING_DE = "Lernt...";
    private const LABEL_WAIT_DATA_DE = "Warte auf Daten";
    private const LABEL_DAYS_SHORT_DE = "T";
    private const LABEL_HIGH_DRAIN_DE = "! Hoher Leerlauf";
    private const LABEL_RISK_LOW_DE = "NIED";
    private const LABEL_RISK_MEDIUM_DE = "MIT";
    private const LABEL_RISK_HIGH_DE = "HOCH";

    private var _nowBatt as Number = 50;
    private var _typicalBatt as Number? = null;

    private var _riskLabel as String? = null;
    private var _riskColor as Number = Graphics.COLOR_WHITE;

    private var _daysCollected as Number = 0;
    private var _endOfDayLabel as String = DEFAULT_END_OF_DAY;
    private var _budgetMin as Number = 0;
    private var _abnormalDrain as Boolean = false;
    private var _isGerman as Boolean = false;

    function initialize() {
        GlanceView.initialize();
        _isGerman = detectGermanLanguage();
    }

    function onShow() as Void {
        _isGerman = detectGermanLanguage();
        updateData();
    }

    function onUpdate(dc as Dc) as Void {
        try {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var x = getContentX(width);
        var rightPad = scaleByWidth(width, 0.03f, 2, 14);
        var maxLineW = width - x - rightPad;
        if (maxLineW < scaleByWidth(width, 0.26f, 42, width)) {
            x = scaleByWidth(width, 0.04f, 2, 12);
            maxLineW = width - x - rightPad;
        }

        var fontMain = Graphics.FONT_GLANCE;
        var fontSub = Graphics.FONT_XTINY;
        var gap = scaleByHeight(height, 0.016f, 1, 5);
        var outerPad = scaleByHeight(height, 0.018f, 1, 6);

        var labelNow = localizeLabel(LABEL_NOW, LABEL_NOW_DE);
        var labelRisk = localizeLabel(LABEL_RISK, LABEL_RISK_DE);
        var labelLearning = localizeLabel(LABEL_LEARNING, LABEL_LEARNING_DE);
        var labelWaitData = localizeLabel(LABEL_WAIT_DATA, LABEL_WAIT_DATA_DE);
        var labelDaysShort = localizeLabel(LABEL_DAYS_SHORT, LABEL_DAYS_SHORT_DE);
        var labelHighDrain = localizeLabel(LABEL_HIGH_DRAIN, LABEL_HIGH_DRAIN_DE);
        var line1 = Lang.format("$1$: $2$%", [labelNow, _nowBatt]);

        var line2;
        if (_typicalBatt != null) {
            line2 = Lang.format("$1$ $2$: ~$3$%", [LABEL_EOD, _endOfDayLabel, (_typicalBatt as Number)]);
        } else {
            line2 = Lang.format("$1$ $2$: $3$", [LABEL_EOD, _endOfDayLabel, labelLearning]);
        }

        var line3;
        var daySuffix = labelDaysShort;
        if (_typicalBatt != null && _riskLabel != null) {
            line3 = Lang.format("$1$ $2$ | $3$$4$", [labelRisk, displayRiskLabel(_riskLabel as String), _daysCollected, daySuffix]);
        } else {
            line3 = Lang.format("$1$ | $2$$3$", [labelWaitData, _daysCollected, daySuffix]);
        }
        var line3Color = Graphics.COLOR_WHITE;
        if (_riskLabel != null) { line3Color = _riskColor; }

        // Optional 4th line: abnormal drain warning takes priority, then budget info
        var line4 = null as String?;
        var line4Color = Graphics.COLOR_WHITE;
        if (_abnormalDrain) {
            line4 = labelHighDrain;
            line4Color = ALERT_COLOR_HIGH_DRAIN;
        } else if (_budgetMin > 0) {
            var budgetLabel = LABEL_BUDGET;
            var unitHour = LABEL_HOUR_SHORT;
            var unitMinute = LABEL_MINUTE_SHORT;
            if (_budgetMin >= 60) {
                var bh = _budgetMin / 60;
                var bm = _budgetMin - bh * 60;
                line4 = Lang.format("$1$: $2$$3$ $4$$5$", [budgetLabel, bh, unitHour, bm, unitMinute]);
                line4Color = BUDGET_COLOR_OK;
            } else {
                line4 = Lang.format("$1$: !$2$$3$", [budgetLabel, _budgetMin, unitMinute]);
                line4Color = ALERT_COLOR_LOW_BUDGET;
            }
        }

        var h1 = dc.getFontHeight(fontMain);
        var h2 = dc.getFontHeight(fontMain);
        var h3 = dc.getFontHeight(fontSub);
        var h4 = dc.getFontHeight(fontSub);
        var totalH3 = h1 + gap + h2 + gap + h3;
        var totalH4 = totalH3 + gap + h4;

        // Show 4th line only when it actually fits (avoids clipping on small screens)
        var showLine4 = (line4 != null) && (totalH4 <= (height - (outerPad * 2)));
        var totalH = showLine4 ? totalH4 : totalH3;
        if (!showLine4 && line4 != null) {
            // When there is no vertical space for a 4th line, promote the alert/budget info.
            line3 = line4 as String;
            line3Color = line4Color;
        }

        line1 = fitTextToWidth(dc, line1, fontMain, maxLineW);
        line2 = fitTextToWidth(dc, line2, fontMain, maxLineW);
        line3 = fitTextToWidth(dc, line3, fontSub, maxLineW);
        if (showLine4 && line4 != null) {
            line4 = fitTextToWidth(dc, line4 as String, fontSub, maxLineW);
        }

        var y = ((height - totalH) / 2).toNumber();
        if (y < outerPad) { y = outerPad; }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, fontMain, line1, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + h1 + gap, fontMain, line2, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(line3Color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + h1 + gap + h2 + gap, fontSub, line3, Graphics.TEXT_JUSTIFY_LEFT);

        if (showLine4) {
            dc.setColor(line4Color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y + h1 + gap + h2 + gap + h3 + gap, fontSub,
                line4 as String, Graphics.TEXT_JUSTIFY_LEFT);
        }
        } catch (ex) {
            drawSafeFallback(dc);
        }
    }

    private function updateData() as Void {
        _nowBatt = getBatteryPercent();
        _typicalBatt = null;

        _riskLabel = null;
        _riskColor = Graphics.COLOR_WHITE;
        _budgetMin = 0;
        _abnormalDrain = false;

        _daysCollected = getDaysCollected();

        try {
            var forecaster = BatteryBudget.Forecaster.getSharedInstance();
            var forecast = forecaster.getDisplayForecast();
            _daysCollected = forecaster.getDaysCollected();

            var endOfDayMin = BatteryBudget.StorageManager.getInstance().getEndOfDayMinutes();
            _endOfDayLabel = BatteryBudget.TimeUtil.formatTime(
                (endOfDayMin / 60).toNumber(),
                (endOfDayMin % 60).toNumber());

            _typicalBatt = forecast[:typical] as Number;
            _budgetMin = forecast[:remainingActivityMinutes] as Number;
            _abnormalDrain = (forecast[:abnormalDrain] == true);

            var risk = forecast[:risk] as BatteryBudget.RiskLevel;
            _riskLabel = riskLevelToCode(risk);
            _riskColor = BatteryBudget.Forecaster.riskToColor(risk);

        } catch (ex) {
            // Keep fallback values
        }
    }

    private function riskLevelToCode(risk as BatteryBudget.RiskLevel) as String {
        switch (risk) {
            case BatteryBudget.RISK_HIGH:
                return RISK_CODE_HIGH;
            case BatteryBudget.RISK_MEDIUM:
                return RISK_CODE_MEDIUM;
            case BatteryBudget.RISK_LOW:
                return RISK_CODE_LOW;
            default:
                return RISK_CODE_LOW;
        }
    }

    private function getDaysCollected() as Number {
        try {
            var stats = Storage.getValue("st");
            if (stats != null && stats instanceof Dictionary) {
                var s = stats as Dictionary;
                if (s.hasKey("firstDataDay")) {
                    var first = s["firstDataDay"];
                    if (first instanceof Number) {
                        var firstMin = first as Number;
                        if (firstMin > 0) {
                            var nowMin = (Time.now().value() / 60).toNumber();
                            var days = (nowMin - firstMin) / (24 * 60);
                            if (days < 0) { return 0; }
                            return days.toNumber();
                        }
                    }
                }
            }
        } catch (ex) {
        }
        return 0;
    }

    private function getBatteryPercent() as Number {
        var stats = System.getSystemStats();
        if (stats has :battery && stats.battery != null) {
            return stats.battery.toNumber();
        }
        return 50;
    }

    private function getLeftInset(width as Number) as Number {
        // Leave room for the system-drawn glance icon on the left.
        var inset = (width.toFloat() * 0.18f + 0.5f).toNumber();
        var minInset = scaleByWidth(width, 0.11f, 18, 40);
        var maxInset = scaleByWidth(width, 0.28f, minInset + 6, width / 2);
        return clampNumber(inset, minInset, maxInset);
    }

    private function getContentX(width as Number) as Number {
        return getLeftInset(width) + scaleByWidth(width, 0.01f, 1, 4);
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

    private function fitTextToWidth(dc as Dc, text as String, font, maxWidth as Number) as String {
        if (maxWidth <= 0) {
            return "";
        }
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) {
            return text;
        }

        var ellipsis = "...";
        var ellipsisWidth = dc.getTextWidthInPixels(ellipsis, font);
        if (ellipsisWidth >= maxWidth) {
            return "";
        }

        var chars = text.toCharArray();
        var result = "";
        for (var i = 0; i < chars.size(); i++) {
            var candidate = result + chars[i].toString();
            if (dc.getTextWidthInPixels(candidate, font) + ellipsisWidth > maxWidth) {
                return result + ellipsis;
            }
            result = candidate;
        }
        return result;
    }

    private function displayRiskLabel(riskCode as String) as String {
        if (_isGerman) {
            if (riskCode == RISK_CODE_HIGH) { return LABEL_RISK_HIGH_DE; }
            if (riskCode == RISK_CODE_MEDIUM) { return LABEL_RISK_MEDIUM_DE; }
            if (riskCode == RISK_CODE_LOW) { return LABEL_RISK_LOW_DE; }
        }
        return riskCode;
    }

    private function localizeLabel(english as String, german as String) as String {
        return _isGerman ? german : english;
    }

    private function detectGermanLanguage() as Boolean {
        try {
            var settings = System.getDeviceSettings();
            if (settings has :systemLanguage) {
                return settings.systemLanguage == System.LANGUAGE_DEU;
            }
        } catch (ex) {
        }
        return false;
    }

    private function drawSafeFallback(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - dc.getFontHeight(Graphics.FONT_XTINY), Graphics.FONT_XTINY,
            "BatteryBudget", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy, Graphics.FONT_XTINY,
            localizeLabel("Waiting for data", "Warte auf Daten"), Graphics.TEXT_JUSTIFY_CENTER);
    }
}
