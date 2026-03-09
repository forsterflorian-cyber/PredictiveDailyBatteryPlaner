import Toybox.Lang;
import Toybox.System;
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

        // Get the local Monday 00:00 start for the week containing the given epoch minute.
        static function getWeekStartEpochMinutes(epochMin as Number) as Number {
            var moment = new Time.Moment(epochMin * 60);
            var info = Gregorian.info(moment, Time.FORMAT_SHORT);
            var dayStart = epochMin - (info.hour * 60 + info.min);
            var dow = info.day_of_week - 1; // 0=Sunday
            if (dow < 0) { dow = 0; }
            if (dow > 6) { dow = 6; }

            // Monday-based week key: Monday=0 offset, Sunday=6 offset.
            var daysSinceMonday = (dow == 0) ? 6 : (dow - 1);
            return dayStart - (daysSinceMonday * 24 * 60);
        }

        static function getWeekKey(epochMin as Number) as Number {
            return getWeekStartEpochMinutes(epochMin);
        }

        static function getCurrentWeekKey() as Number {
            return getWeekStartEpochMinutes(nowEpochMinutes());
        }

        static function getOverlapMinutesWithinWeek(startTMin as Number, endTMin as Number, weekKey as Number) as Number {
            if (endTMin <= startTMin) {
                return 0;
            }

            var weekStart = weekKey;
            var weekEnd = weekStart + (7 * 24 * 60);
            var overlapStart = startTMin > weekStart ? startTMin : weekStart;
            var overlapEnd = endTMin < weekEnd ? endTMin : weekEnd;

            if (overlapEnd <= overlapStart) {
                return 0;
            }
            return overlapEnd - overlapStart;
        }
        
        // Get current local time info
        static function getLocalTimeInfo() as Gregorian.Info {
            return Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        }
        
        // Get slot index (0-23) from hour — one slot per hour.
        // The minute parameter is kept for call-site compatibility but is ignored.
        static function getSlotIndex(hour as Number, minute as Number) as Number {
            return hour;
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
        
        // Format hour:minute respecting the device's 12h/24h preference.
        // Returns "HH:MM" (24h) or "H:MMam/pm" (12h).
        static function formatTime(hour as Number, minute as Number) as String {
            var mStr = minute < 10 ? "0" + minute.toString() : minute.toString();
            try {
                var devSettings = System.getDeviceSettings();
                if ((devSettings has :is24Hour) && !devSettings.is24Hour) {
                    var h12 = hour % 12;
                    if (h12 == 0) { h12 = 12; }
                    var suffix = hour < 12 ? "am" : "pm";
                    return h12.toString() + ":" + mStr + suffix;
                }
            } catch (ex) {}
            // 24-hour default
            var hStr = hour < 10 ? "0" + hour.toString() : hour.toString();
            return hStr + ":" + mStr;
        }

        // Format time from slot index (e.g., slot 10 -> "10:00" or "10:00am")
        static function formatSlotTime(slotIndex as Number) as String {
            return formatTime(slotIndex, 0);
        }
    }
}
