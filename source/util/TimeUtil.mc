import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:background)
module BatteryBudget {
    
    class TimeUtil {
        
        // Convert Time.Moment to epoch minutes
        static function momentToEpochMinutes(moment as Time.Moment) as Number {
            return (moment.value() / 60).toNumber();
        }
        
        // Get current epoch minutes
        static function nowEpochMinutes() as Number {
            return momentToEpochMinutes(Time.now());
        }
        
        // Get current local time info
        static function getLocalTimeInfo() as Gregorian.Info {
            return Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        }
        
        // Get slot index (0-47) from hour and minute
        static function getSlotIndex(hour as Number, minute as Number) as Number {
            return (hour * 2 + (minute >= 30 ? 1 : 0));
        }
        
        // Get current slot index
        static function getCurrentSlotIndex() as Number {
            var info = getLocalTimeInfo();
            return getSlotIndex(info.hour, info.min);
        }
        
        // Get weekday (0=Sunday, 6=Saturday) - Garmin uses 1=Sunday
        static function getWeekday() as Number {
            var info = getLocalTimeInfo();
            var dow = info.day_of_week - 1; // Convert to 0-based
            if (dow < 0) { dow = 0; }
            if (dow > 6) { dow = 6; }
            return dow;
        }
        
        // Get weekday from epoch minutes
        static function getWeekdayFromEpochMin(epochMin as Number) as Number {
            var moment = new Time.Moment(epochMin * 60);
            var info = Gregorian.info(moment, Time.FORMAT_SHORT);
            var dow = info.day_of_week - 1;
            if (dow < 0) { dow = 0; }
            if (dow > 6) { dow = 6; }
            return dow;
        }
        
        // Get slot index from epoch minutes (local time)
        static function getSlotFromEpochMin(epochMin as Number) as Number {
            var moment = new Time.Moment(epochMin * 60);
            var info = Gregorian.info(moment, Time.FORMAT_SHORT);
            return getSlotIndex(info.hour, info.min);
        }
        
        // Parse HH:MM string to minutes since midnight
        static function parseTimeString(timeStr as String) as Number {
            // Default to 22:00 if parsing fails
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
                // Fall through to default
            }
            return 22 * 60; // Default 22:00
        }
        // Simple string split (Connect IQ doesn't have built-in)
        static function splitString(str as String, delimiter as String) as Array<String> {
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
        
        // Get minutes remaining until target time today
        static function getMinutesUntilTime(targetMinutesSinceMidnight as Number) as Number {
            var info = getLocalTimeInfo();
            var nowMinutes = info.hour * 60 + info.min;
            var remaining = targetMinutesSinceMidnight - nowMinutes;
            
            // If target time has passed, return 0
            return remaining > 0 ? remaining : 0;
        }
        
        // Get slot index for end of day time (clamp to valid range 0..47)
        static function getEndOfDaySlot(endOfDayMinutes as Number) as Number {
            var hour = (endOfDayMinutes / 60).toNumber();
            var minute = (endOfDayMinutes % 60).toNumber();
            var slot = getSlotIndex(hour, minute);
            if (slot >= SLOTS_PER_DAY) { slot = SLOTS_PER_DAY - 1; }
            if (slot < 0) { slot = 0; }
            return slot;
        }
        
        // Format time from slot index (e.g., slot 10 -> "05:00")
        static function formatSlotTime(slotIndex as Number) as String {
            var hour = slotIndex / 2;
            var minute = (slotIndex % 2) * 30;
            var hourStr = hour < 10 ? "0" + hour.toString() : hour.toString();
            var minStr = minute < 10 ? "0" + minute.toString() : minute.toString();
            return hourStr + ":" + minStr;
        }
    }
}
