import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Application.Storage;
import Toybox.Application.Properties;

(:glance)
class BatteryBudgetGlanceView extends WatchUi.GlanceView {

    private const SLOTS_PER_DAY = 24;
    private const SLOT_DURATION_MIN = 60;

    private const DEFAULT_END_OF_DAY = "22:00";
    private const DEFAULT_IDLE_RATE = 0.8f; // %/h
    private const DEFAULT_ACTIVITY_RATE = 8.0f; // %/h

    private const DEFAULT_CONSERVATIVE_FACTOR = 1.2f;

    private const DEFAULT_RISK_YELLOW = 30;
    private const DEFAULT_RISK_RED = 15;
    private const ALERT_COLOR_HIGH_DRAIN = 0xFF6600;
    private const ALERT_COLOR_LOW_BUDGET = 0xFFB000;
    private const BUDGET_COLOR_OK = 0x3399FF;

    private var _nowBatt as Number = 50;
    private var _typicalBatt as Number? = null;
    private var _consBatt as Number? = null;

    private var _riskLabel as String? = null;
    private var _riskColor as Number = Graphics.COLOR_WHITE;

    private var _daysCollected as Number = 0;
    private var _endOfDayLabel as String = DEFAULT_END_OF_DAY;
    private var _budgetMin as Number = 0;
    private var _abnormalDrain as Boolean = false;

    function initialize() {
        GlanceView.initialize();
    }

    function onShow() as Void {
        updateData();
    }

    function onUpdate(dc as Dc) as Void {
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

        var nowLabel = tr(Rez.Strings.NowShort);
        var line1 = Lang.format("$1$: $2$%", [nowLabel, _nowBatt]);

        var line2;
        if (_typicalBatt != null) {
            line2 = Lang.format("$1$ $2$: ~$3$%", [tr(Rez.Strings.EodShort), _endOfDayLabel, (_typicalBatt as Number)]);
        } else {
            line2 = Lang.format("$1$ $2$: $3$", [tr(Rez.Strings.EodShort), _endOfDayLabel, tr(Rez.Strings.Learning)]);
        }

        var line3;
        var daySuffix = tr(Rez.Strings.DaysShort);
        if (_typicalBatt != null && _riskLabel != null) {
            line3 = Lang.format("$1$ $2$ | $3$$4$", [tr(Rez.Strings.Risk), (_riskLabel as String), _daysCollected, daySuffix]);
        } else {
            line3 = Lang.format("$1$ | $2$$3$", [tr(Rez.Strings.MsgWaitForData), _daysCollected, daySuffix]);
        }
        var line3Color = Graphics.COLOR_WHITE;
        if (_riskLabel != null) { line3Color = _riskColor; }

        // Optional 4th line: abnormal drain warning takes priority, then budget info
        var line4 = null as String?;
        var line4Color = Graphics.COLOR_WHITE;
        if (_abnormalDrain) {
            line4 = tr(Rez.Strings.MsgHighDrain);
            line4Color = ALERT_COLOR_HIGH_DRAIN;
        } else if (_budgetMin > 0) {
            var budgetLabel = tr(Rez.Strings.LabelBudget);
            var unitHour = tr(Rez.Strings.UnitHourShort);
            var unitMinute = tr(Rez.Strings.UnitMinuteShort);
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
    }

    private function updateData() as Void {
        _nowBatt = getBatteryPercent();
        _typicalBatt = null;
        _consBatt = null;

        _riskLabel = null;
        _riskColor = Graphics.COLOR_WHITE;
        _budgetMin = 0;
        _abnormalDrain = false;

        _daysCollected = getDaysCollected();

        try {
            _endOfDayLabel = readStringProperty("endOfDayTime", DEFAULT_END_OF_DAY);
            var endOfDayMin = parseTimeString(_endOfDayLabel);

            var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            var weekday = (info.day_of_week - 1);
            if (weekday < 0) { weekday = 0; }
            if (weekday > 6) { weekday = 6; }

            var currentSlot = slotIndex(info.hour, info.min);
            var endOfDayHour = (endOfDayMin / 60).toNumber();
            var endOfDayMinute = (endOfDayMin % 60).toNumber();
            var endOfDaySlot = slotIndex(endOfDayHour, endOfDayMinute);

            if (endOfDaySlot < currentSlot) {
                endOfDaySlot = currentSlot;
            }
            if (endOfDaySlot >= SLOTS_PER_DAY) {
                endOfDaySlot = SLOTS_PER_DAY - 1;
            }

            var idleRate = readDrainRate("i", :idle, DEFAULT_IDLE_RATE);
            var activityRate = readDrainRate("a", :activityGeneric, DEFAULT_ACTIVITY_RATE);

            var conservativeFactor = readFactorProperty("conservativeFactor", DEFAULT_CONSERVATIVE_FACTOR, 1.0f, 2.0f);

            // The current slot may be partially elapsed - only count remaining minutes.
            // With 60-min slots, remaining = minutes left in the current hour.
            var remainingInCurrentSlot = SLOT_DURATION_MIN - info.min;

            var totalDrainTypical = 0.0f;
            var solarMinRemaining = 0;

            var patternFlat = tryLoadPatternFlat();
            for (var slot = currentSlot; slot < endOfDaySlot; slot++) {
                var slotDurationMin = (slot == currentSlot) ? remainingInCurrentSlot : SLOT_DURATION_MIN;
                solarMinRemaining += slotDurationMin;

                var expectedActivityMin = 0;
                if (patternFlat != null) {
                    expectedActivityMin = (patternFlat as Array<Number>)[weekday * SLOTS_PER_DAY + slot];
                }

                // Scale proportionally when the slot is only partially remaining
                if (slotDurationMin < SLOT_DURATION_MIN) {
                    expectedActivityMin = (expectedActivityMin * slotDurationMin / SLOT_DURATION_MIN);
                }
                var expectedIdleMin = slotDurationMin - expectedActivityMin;
                if (expectedIdleMin < 0) {
                    expectedIdleMin = 0;
                    expectedActivityMin = slotDurationMin;
                }

                var slotDrain =
                    (expectedActivityMin.toFloat() / 60.0f) * activityRate +
                    (expectedIdleMin.toFloat() / 60.0f) * idleRate;

                totalDrainTypical += slotDrain;
            }

            // Solar gain correction
            var solarBonusTypical = 0.0f;
            var drDict = Storage.getValue("dr");
            if (drDict != null && drDict instanceof Dictionary) {
                var d = drDict as Dictionary;
                var sgv = d.hasKey("sg") ? d["sg"] : null;
                var rsv = d.hasKey("rs") ? d["rs"] : null;
                if (sgv != null && rsv != null && rsv instanceof Number) {
                    var sgRate = (sgv instanceof Float) ? sgv as Float : (sgv as Number).toFloat();
                    var recentSol = rsv as Number;
                    if (recentSol > 10) {
                        var solarFraction = recentSol.toFloat() / 100.0f;
                        var totalGain = sgRate * solarFraction * solarMinRemaining.toFloat() / 60.0f;
                        solarBonusTypical = totalGain * 0.5f;
                    }
                }
            }

            var endTypical = clampBattery(_nowBatt.toFloat() - totalDrainTypical + solarBonusTypical);
            var endCons = clampBattery(_nowBatt.toFloat() - (totalDrainTypical * conservativeFactor));

            _typicalBatt = roundPct(endTypical);
            _consBatt = roundPct(endCons);

            var yellow = readNumberProperty("riskThresholdYellow", DEFAULT_RISK_YELLOW);
            var red = readNumberProperty("riskThresholdRed", DEFAULT_RISK_RED);

            var riskBatt = _consBatt as Number;
            if (riskBatt < red) {
                _riskLabel = tr(Rez.Strings.RiskHigh);
                _riskColor = 0xFF0000;
            } else if (riskBatt < yellow) {
                _riskLabel = tr(Rez.Strings.RiskMedium);
                _riskColor = 0xFFFF00;
            } else {
                _riskLabel = tr(Rez.Strings.RiskLow);
                _riskColor = 0x00FF00;
            }

            // Activity Budget (inline, mirrors Forecaster logic)
            var targetLevel = readNumberProperty("targetLevel", 15);
            var extraPerHour = activityRate - idleRate;
            if (extraPerHour > 0.0f) {
                var headroom = _nowBatt.toFloat() - totalDrainTypical - targetLevel.toFloat();
                if (headroom > 0.0f) {
                    var budgetCalc = (headroom / (extraPerHour / 60.0f)).toNumber();
                    var maxMin = (endOfDaySlot - currentSlot) * SLOT_DURATION_MIN;
                    if (budgetCalc > maxMin) { budgetCalc = maxMin; }
                    _budgetMin = budgetCalc;
                }
            }

            // Abnormal drain: idle rate more than 50% above default
            _abnormalDrain = (idleRate > DEFAULT_IDLE_RATE * 1.5f);

        } catch (ex) {
            // Keep fallback values
        }
    }

    // One slot per hour; minute parameter kept for call-site compatibility.
    private function slotIndex(hour as Number, minute as Number) as Number {
        return hour;
    }

    private function readStringProperty(key as String, defaultValue as String) as String {
        try {
            var v = Properties.getValue(key);
            if (v instanceof String) { return v as String; }
        } catch (ex) {
        }
        return defaultValue;
    }

    private function readNumberProperty(key as String, defaultValue as Number) as Number {
        try {
            var v = Properties.getValue(key);
            if (v instanceof Number) { return v as Number; }
        } catch (ex) {
        }
        return defaultValue;
    }

    private function readFactorProperty(key as String, defaultValue as Float, minVal as Float, maxVal as Float) as Float {
        var factor = defaultValue;
        try {
            var v = Properties.getValue(key);
            if (v instanceof Float) { factor = v as Float; }
            else if (v instanceof Number) { factor = (v as Number).toFloat(); }
        } catch (ex) {
        }

        // Backward compatibility: older versions stored factors as integer percentages (e.g., 120 -> 1.2)
        if (factor > 10.0f) { factor = factor / 100.0f; }

        if (factor < minVal) { factor = minVal; }
        if (factor > maxVal) { factor = maxVal; }
        return factor;
    }

    private function readDrainRate(shortKey as String, legacyKey as Symbol, defaultRate as Float) as Float {
        try {
            var data = Storage.getValue("dr");
            if (data != null && data instanceof Dictionary) {
                var dict = data as Dictionary;

                // Current format (v1.0.0+): short keys
                if (dict.hasKey(shortKey)) {
                    var v1 = dict[shortKey];
                    if (v1 instanceof Float) { return v1 as Float; }
                    if (v1 instanceof Number) { return (v1 as Number).toFloat(); }
                }

                // Legacy format: symbol keys
                if (dict.hasKey(legacyKey)) {
                    var v2 = dict[legacyKey];
                    if (v2 instanceof Float) { return v2 as Float; }
                    if (v2 instanceof Number) { return (v2 as Number).toFloat(); }
                }
            }
        } catch (ex) {
        }
        return defaultRate;
    }

    // Returns the full flat pattern array (7*SLOTS_PER_DAY elements), or null if unavailable/wrong format.
    private function tryLoadPatternFlat() as Array<Number>? {
        try {
            var data = Storage.getValue("pat");
            if (data instanceof Array) {
                var arr = data as Array;
                if (arr.size() == 7 * SLOTS_PER_DAY && arr[0] instanceof Number) {
                    return arr as Array<Number>;
                }
            }
        } catch (ex) {
        }
        return null;
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

    private function clampBattery(value as Float) as Float {
        if (value < 0.0f) { return 0.0f; }
        if (value > 100.0f) { return 100.0f; }
        return value;
    }

    private function roundPct(value as Float) as Number {
        return (value + 0.5f).toNumber();
    }

    // Parse HH:MM into minutes since midnight
    private function parseTimeString(timeStr as String) as Number {
        try {
            var parts = splitString(timeStr, ":");
            if (parts.size() >= 2) {
                var hour = parts[0].toNumber();
                var minute = parts[1].toNumber();

                if (hour != null && minute != null && hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
                    return hour * 60 + minute;
                }
            }
        } catch (ex) {
        }
        return 22 * 60;
    }

    private function splitString(str as String, delimiter as String) as Array<String> {
        var result = [] as Array<String>;
        if (delimiter.length() == 0) {
            result.add(str);
            return result;
        }
        var current = "";
        var chars = str.toCharArray();
        var delimChar = delimiter.toCharArray()[0];

        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] == delimChar) {
                result.add(current);
                current = "";
            } else {
                current = current + chars[i].toString();
            }
        }
        result.add(current);
        return result;
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

    private function tr(resourceId as Lang.ResourceId) as String {
        return WatchUi.loadResource(resourceId) as String;
    }
}
