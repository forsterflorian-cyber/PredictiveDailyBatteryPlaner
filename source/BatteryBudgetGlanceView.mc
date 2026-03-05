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

    private const SLOTS_PER_DAY = 48;
    private const SLOT_DURATION_MIN = 30;

    private const DEFAULT_END_OF_DAY = "22:00";
    private const DEFAULT_IDLE_RATE = 0.8f; // %/h
    private const DEFAULT_ACTIVITY_RATE = 8.0f; // %/h

    private const DEFAULT_CONSERVATIVE_FACTOR = 1.2f;
    private const DEFAULT_OPTIMISTIC_FACTOR = 0.8f;

    private const DEFAULT_RISK_YELLOW = 30;
    private const DEFAULT_RISK_RED = 15;
    private const RISK_LABEL_LOW = "LOW";
    private const RISK_LABEL_MEDIUM = "MED";
    private const RISK_LABEL_HIGH = "HIGH";

    private var _nowBatt as Number = 50;
    private var _typicalBatt as Number? = null;
    private var _consBatt as Number? = null;
    private var _optBatt as Number? = null;

    private var _riskLabel as String? = null;
    private var _riskColor as Number = Graphics.COLOR_WHITE;

    private var _daysCollected as Number = 0;
    private var _endOfDayLabel as String = DEFAULT_END_OF_DAY;

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

        var fontMain = Graphics.FONT_GLANCE;
        var fontSub = Graphics.FONT_XTINY;

        var line1 = "Now: " + _nowBatt.toString() + "%";

        var line2;
        if (_typicalBatt != null) {
            line2 = "EOD " + _endOfDayLabel + ": ~" + (_typicalBatt as Number).toString() + "%";
        } else {
            line2 = "EOD " + _endOfDayLabel + ": learning";
        }

        var line3;
        if (_typicalBatt != null && _riskLabel != null) {
            line3 = "Risk " + (_riskLabel as String) + " | " + _daysCollected.toString() + "d";
        } else {
            line3 = "Learning | " + _daysCollected.toString() + "d";
        }
        var line3Color = Graphics.COLOR_WHITE;
        if (_riskLabel != null) { line3Color = _riskColor; }

        var gap = 2;
        var h1 = dc.getFontHeight(fontMain);
        var h2 = dc.getFontHeight(fontMain);
        var h3 = dc.getFontHeight(fontSub);
        var totalH = h1 + gap + h2 + gap + h3;

        var y = ((height - totalH) / 2).toNumber();
        if (y < 0) { y = 0; }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, fontMain, line1, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + h1 + gap, fontMain, line2, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(line3Color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + h1 + gap + h2 + gap, fontSub, line3, Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function updateData() as Void {
        _nowBatt = getBatteryPercent();
        _typicalBatt = null;
        _consBatt = null;
        _optBatt = null;

        _riskLabel = null;
        _riskColor = Graphics.COLOR_WHITE;

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
            var optimisticFactor = readFactorProperty("optimisticFactor", DEFAULT_OPTIMISTIC_FACTOR, 0.5f, 1.0f);

            var totalDrainTypical = 0.0f;

            var patternDay = tryLoadPatternDay(weekday);
            for (var slot = currentSlot; slot < endOfDaySlot; slot++) {
                var expectedActivityMin = 0;
                if (patternDay != null) {
                    var v = (patternDay as Array)[slot];
                    if (v instanceof Number) {
                        expectedActivityMin = v as Number;
                    }
                }

                var expectedIdleMin = SLOT_DURATION_MIN - expectedActivityMin;
                if (expectedIdleMin < 0) {
                    expectedIdleMin = 0;
                    expectedActivityMin = SLOT_DURATION_MIN;
                }

                var slotDrain =
                    (expectedActivityMin.toFloat() / 60.0f) * activityRate +
                    (expectedIdleMin.toFloat() / 60.0f) * idleRate;

                totalDrainTypical += slotDrain;
            }

            var endTypical = clampBattery(_nowBatt.toFloat() - totalDrainTypical);
            var endCons = clampBattery(_nowBatt.toFloat() - (totalDrainTypical * conservativeFactor));
            var endOpt = clampBattery(_nowBatt.toFloat() - (totalDrainTypical * optimisticFactor));

            _typicalBatt = roundPct(endTypical);
            _consBatt = roundPct(endCons);
            _optBatt = roundPct(endOpt);

            var yellow = readNumberProperty("riskThresholdYellow", DEFAULT_RISK_YELLOW);
            var red = readNumberProperty("riskThresholdRed", DEFAULT_RISK_RED);

            var riskBatt = _consBatt as Number;
            if (riskBatt < red) {
                _riskLabel = RISK_LABEL_HIGH;
                _riskColor = 0xFF0000;
            } else if (riskBatt < yellow) {
                _riskLabel = RISK_LABEL_MEDIUM;
                _riskColor = 0xFFFF00;
            } else {
                _riskLabel = RISK_LABEL_LOW;
                _riskColor = 0x00FF00;
            }
        } catch (ex) {
            // Keep fallback values
        }
    }

    private function slotIndex(hour as Number, minute as Number) as Number {
        return (hour * 2 + (minute >= 30 ? 1 : 0));
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

    private function tryLoadPatternDay(weekday as Number) as Array? {
        try {
            var data = Storage.getValue("pat");
            if (data != null && data instanceof Array) {
                var week = data as Array;
                if (week.size() == 7 && weekday >= 0 && weekday < 7) {
                    var day = week[weekday];
                    if (day != null && day instanceof Array && (day as Array).size() == SLOTS_PER_DAY) {
                        return day as Array;
                    }
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
        if (stats != null && stats has :battery && stats.battery != null) {
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
        var inset = (width * 0.18).toNumber();
        if (inset < 32) { inset = 32; }
        if (inset > 80) { inset = 80; }
        return inset;
    }

    private function getContentX(width as Number) as Number {
        return getLeftInset(width) + 2;
    }
}
