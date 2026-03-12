import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

(:glance)
class BatteryBudgetGlanceView extends WatchUi.GlanceView {

    private var _batteryText as WatchUi.Text?;
    private var _batteryLabel as String = "--%";

    function initialize() {
        GlanceView.initialize();
    }

    function onLayout(dc as Dc) as Void {
        var font = Graphics.FONT_TINY;
        _batteryText = new WatchUi.Text({
            :text => _batteryLabel,
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
        refreshBatteryLabel();
    }

    private function getBatteryLabel() as String {
        try {
            var stats = System.getSystemStats();
            if (stats has :battery && stats.battery != null) {
                return stats.battery.toNumber().toString() + "%";
            }
        } catch (ex) {
        }

        return "--%";
    }

    private function refreshBatteryLabel() as Void {
        try {
            var nextLabel = getBatteryLabel();
            if (nextLabel == _batteryLabel) {
                return;
            }

            _batteryLabel = nextLabel;

            if (_batteryText != null) {
                (_batteryText as WatchUi.Text).setText(_batteryLabel);
            }
        } catch (ex) {
        }
    }
}
