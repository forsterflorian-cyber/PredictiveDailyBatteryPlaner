import Toybox.WatchUi;
import Toybox.Lang;

class BatteryBudgetDetailDelegate extends WatchUi.BehaviorDelegate {

    private var _view as BatteryBudgetDetailView;

    function initialize(view as BatteryBudgetDetailView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // Handle next page (swipe up or tap)
    function onNextPage() as Boolean {
        _view.nextPage();
        return true;
    }

    // Handle previous page (swipe down)
    function onPreviousPage() as Boolean {
        _view.previousPage();
        return true;
    }

    // Handle select button
    function onSelect() as Boolean {
        // Open next sub-page
        _view.nextPage();
        return true;
    }

    // Handle back button
    function onBack() as Boolean {
        // Exit widget
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    // Handle menu button (if applicable)
    function onMenu() as Boolean {
        // Could show settings or additional info
        // For now, just cycle pages
        _view.nextPage();
        return true;
    }

    // Handle key events
    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key = keyEvent.getKey();

        switch (key) {
            case WatchUi.KEY_UP:
                _view.previousPage();
                return true;
            case WatchUi.KEY_DOWN:
                _view.nextPage();
                return true;
            case WatchUi.KEY_ENTER:
                _view.nextPage();
                return true;
        }

        return false;
    }

    // Handle swipe events
    function onSwipe(swipeEvent as WatchUi.SwipeEvent) as Boolean {
        var direction = swipeEvent.getDirection();

        switch (direction) {
            case WatchUi.SWIPE_UP:
                _view.nextPage();
                return true;
            case WatchUi.SWIPE_DOWN:
                _view.previousPage();
                return true;
            case WatchUi.SWIPE_LEFT:
                // Could go to next widget
                return false;
            case WatchUi.SWIPE_RIGHT:
                // Exit
                WatchUi.popView(WatchUi.SLIDE_RIGHT);
                return true;
        }

        return false;
    }
}
