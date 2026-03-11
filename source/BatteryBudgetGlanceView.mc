import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

(:glance)
class BatteryBudgetGlanceView extends WatchUi.GlanceView {

    private var _batteryText as WatchUi.Text?;

    function initialize() {
        GlanceView.initialize();
    }

    function onLayout(dc as Dc) as Void {
        var font = Graphics.FONT_TINY;
        _batteryText = new WatchUi.Text({
            :text => getGlanceLabel(),
            :color => Graphics.COLOR_WHITE,
            :font => font,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_CENTER,
            :justification => Graphics.TEXT_JUSTIFY_CENTER,
            :width => dc.getWidth(),
            :height => dc.getFontHeight(font) + 4
        });

        setLayout([_batteryText as WatchUi.Drawable]);
    }

    function onShow() as Void {
        refreshGlanceLabel();
    }

    function onUpdate(dc as Dc) as Void {
        refreshGlanceLabel();
        View.onUpdate(dc);
    }

    private function getGlanceLabel() as String {
        var forecastLabel = getForecastLabel();
        if (forecastLabel != null) {
            return forecastLabel as String;
        }
        return getBatteryLabel();
    }

    private function getForecastLabel() as String? {
        try {
            var forecast = BatteryBudget.Forecaster.getSharedInstance().getDisplayForecast();
            if (forecast != null && forecast[:typical] instanceof Number) {
                return "EOD " + formatPercentLabel(forecast[:typical] as Number);
            }
        } catch (ex) {
        }
        return null;
    }

    private function getBatteryLabel() as String {
        try {
            var stats = System.getSystemStats();
            if (stats has :battery && stats.battery != null) {
                return formatPercentLabel(stats.battery.toNumber());
            }
        } catch (ex) {
        }

        return "--%";
    }

    private function refreshGlanceLabel() as Void {
        try {
            if (_batteryText != null) {
                (_batteryText as WatchUi.Text).setText(getGlanceLabel());
            }
        } catch (ex) {
        }
    }

    private function formatPercentLabel(value as Number) as String {
        var percent = value;
        if (percent < 0) { percent = 0; }
        if (percent > 100) { percent = 100; }
        return percent.toNumber().toString() + "%";
    }
}
