import Toybox.Lang;
import Toybox.WatchUi;

class BatteryBudgetBroadcastConfirmationDelegate extends WatchUi.ConfirmationDelegate {

    private var _view as BatteryBudgetDetailView;

    function initialize(view as BatteryBudgetDetailView) {
        ConfirmationDelegate.initialize();
        _view = view;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        return _view.handleBroadcastValidationResponse(response);
    }
}
