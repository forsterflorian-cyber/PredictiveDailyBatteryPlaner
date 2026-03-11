import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.UserProfile;

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
            var dow = getWeekdayIndex(info);

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

        static function getMinutesSinceMidnight(info as Gregorian.Info) as Number {
            return info.hour * 60 + info.min;
        }

        static function getWeekdayIndex(info as Gregorian.Info) as Number {
            return normalizeDayOfWeek(info.day_of_week);
        }
        
        // Get slot index (0-23) from hour — one slot per hour.
        // The minute parameter is kept for call-site compatibility but is ignored.
        static function getSlotIndex(hour as Number, minute as Number) as Number {
            if (hour < 0) { return 0; }
            if (hour >= SLOTS_PER_DAY) { return SLOTS_PER_DAY - 1; }
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
            return getWeekdayIndex(info);
        }
        
        // Get weekday from epoch minutes
        static function getWeekdayFromEpochMin(epochMin as Number) as Number {
            var moment = new Time.Moment(epochMin * 60);
            var info = Gregorian.info(moment, Time.FORMAT_SHORT);
            return getWeekdayIndex(info);
        }
        
        // Get slot index from epoch minutes (local time)
        static function getSlotFromEpochMin(epochMin as Number) as Number {
            var moment = new Time.Moment(epochMin * 60);
            var info = Gregorian.info(moment, Time.FORMAT_SHORT);
            return getSlotIndex(info.hour, info.min);
        }
        
        // Parse HH:MM string to minutes since midnight
        static function tryParseTimeString(timeStr as String) as Number? {
            try {
                var parts = splitString(timeStr, ":");
                if (parts.size() != 2) {
                    return null;
                }

                var hourPart = parts[0];
                var minutePart = parts[1];
                if (hourPart.length() < 1 || hourPart.length() > 2 || minutePart.length() < 1 || minutePart.length() > 2) {
                    return null;
                }
                if (!isDigitString(hourPart) || !isDigitString(minutePart)) {
                    return null;
                }

                var hour = hourPart.toNumber();
                var minute = minutePart.toNumber();
                if (hour != null && minute != null && hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
                    return hour * 60 + minute;
                }
            } catch (ex) {
                // Fall through to null
            }
            return null;
        }

        static function parseTimeString(timeStr as String) as Number {
            // Default to 22:00 if parsing fails
            var parsed = tryParseTimeString(timeStr);
            if (parsed != null) {
                return parsed as Number;
            }
            return 22 * 60; // Default 22:00
        }

        static function formatCanonicalTime(minutesSinceMidnight as Number) as String {
            var clampedMinutes = minutesSinceMidnight;
            if (clampedMinutes < 0) { clampedMinutes = 0; }
            if (clampedMinutes > ((24 * 60) - 1)) { clampedMinutes = (24 * 60) - 1; }

            var hour = (clampedMinutes / 60).toNumber();
            var minute = (clampedMinutes % 60).toNumber();
            var hourStr = hour < 10 ? "0" + hour.toString() : hour.toString();
            var minuteStr = minute < 10 ? "0" + minute.toString() : minute.toString();
            return hourStr + ":" + minuteStr;
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

        private static function isDigitString(str as String) as Boolean {
            if (str.length() == 0) {
                return false;
            }

            var chars = str.toCharArray();
            for (var i = 0; i < chars.size(); i++) {
                var code = chars[i].toNumber();
                if (code < 48 || code > 57) {
                    return false;
                }
            }
            return true;
        }
        
        // Get minutes remaining until target time today
        static function getMinutesUntilTime(targetMinutesSinceMidnight as Number) as Number {
            var info = getLocalTimeInfo();
            var nowMinutes = getMinutesSinceMidnight(info);
            var remaining = targetMinutesSinceMidnight - nowMinutes;
            
            // If target time has passed, return 0
            return remaining > 0 ? remaining : 0;
        }
        
        static function getEndOfDaySlotRangeEnd(endOfDayMinutes as Number) as Number {
            if (endOfDayMinutes <= 0) {
                return 0;
            }

            var slotEnd = ((endOfDayMinutes.toFloat() + SLOT_DURATION_MIN.toFloat() - 1.0f)
                / SLOT_DURATION_MIN.toFloat()).toNumber();
            if (slotEnd < 0) { slotEnd = 0; }
            if (slotEnd > SLOTS_PER_DAY) { slotEnd = SLOTS_PER_DAY; }
            return slotEnd;
        }

        static function getSlotOverlapMinutes(slotIndex as Number,
                                              startMinutesSinceMidnight as Number,
                                              endMinutesSinceMidnight as Number) as Number {
            var slotStart = slotIndex * SLOT_DURATION_MIN;
            var slotEnd = slotStart + SLOT_DURATION_MIN;
            var overlapStart = startMinutesSinceMidnight > slotStart ? startMinutesSinceMidnight : slotStart;
            var overlapEnd = endMinutesSinceMidnight < slotEnd ? endMinutesSinceMidnight : slotEnd;

            if (overlapEnd <= overlapStart) {
                return 0;
            }
            return overlapEnd - overlapStart;
        }

        // Get slot index for end of day time (clamp to valid range 0..23)
        static function getEndOfDaySlot(endOfDayMinutes as Number) as Number {
            var hour = (endOfDayMinutes / 60).toNumber();
            var minute = (endOfDayMinutes % 60).toNumber();
            var slot = getSlotIndex(hour, minute);
            if (slot >= SLOTS_PER_DAY) { slot = SLOTS_PER_DAY - 1; }
            if (slot < 0) { slot = 0; }
            return slot;
        }

        static function resolveSleepStartHour(settings as Dictionary?) as Number {
            try {
                var profile = UserProfile.getProfile();
                if (profile has :sleepTime) {
                    var st = profile.sleepTime;
                    if (st instanceof Time.Duration) {
                        return clampHourOfDay(((st as Time.Duration).value() / 3600).toNumber());
                    }
                }
            } catch (ex) {}

            if (settings != null && (settings as Dictionary).hasKey(:sleepStartHour)) {
                var startHour = (settings as Dictionary)[:sleepStartHour];
                if (startHour instanceof Number) {
                    return clampHourOfDay(startHour as Number);
                }
            }
            return SLEEP_START_HOUR;
        }

        static function resolveSleepEndHour(settings as Dictionary?) as Number {
            try {
                var profile = UserProfile.getProfile();
                if (profile has :wakeTime) {
                    var wt = profile.wakeTime;
                    if (wt instanceof Time.Duration) {
                        return clampHourOfDay(((wt as Time.Duration).value() / 3600).toNumber());
                    }
                }
            } catch (ex) {}

            if (settings != null && (settings as Dictionary).hasKey(:sleepEndHour)) {
                var endHour = (settings as Dictionary)[:sleepEndHour];
                if (endHour instanceof Number) {
                    return clampHourOfDay(endHour as Number);
                }
            }
            return SLEEP_END_HOUR;
        }

        static function isWithinSleepWindow(hour as Number, settings as Dictionary?) as Boolean {
            var startHour = resolveSleepStartHour(settings);
            var endHour = resolveSleepEndHour(settings);

            if (startHour == endHour) {
                return false;
            }
            if (startHour < endHour) {
                return hour >= startHour && hour < endHour;
            }
            return hour >= startHour || hour < endHour;
        }

        static function isSleepTime(settings as Dictionary?) as Boolean {
            var info = getLocalTimeInfo();
            return isWithinSleepWindow(info.hour, settings);
        }

        private static function clampHourOfDay(hour as Number) as Number {
            if (hour < 0) { return 0; }
            if (hour > 23) { return 23; }
            return hour;
        }

        private static function normalizeDayOfWeek(dayOfWeek) as Number {
            var dow = 1;
            try {
                if (dayOfWeek instanceof Number) {
                    dow = dayOfWeek as Number;
                } else if (dayOfWeek != null) {
                    var converted = dayOfWeek.toNumber();
                    if (converted != null) {
                        dow = converted as Number;
                    }
                }
            } catch (ex) {
            }

            dow -= 1;
            if (dow < 0) { dow = 0; }
            if (dow > 6) { dow = 6; }
            return dow;
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
