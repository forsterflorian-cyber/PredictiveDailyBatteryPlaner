import Toybox.Lang;
import Toybox.Sensor;
import Toybox.SensorHistory;
import Toybox.Time;

(:background)
module BatteryBudget {

    class BroadcastDetector {

        private var _storage as StorageManager;

        private const HISTORY_WINDOW_MIN = 10;
        private const MAX_HISTORY_SAMPLES = 90;
        private const MIN_HEART_RATE_BPM = 40;

        function initialize() {
            _storage = StorageManager.getInstance();
        }

        function captureHeartRateContext() as Dictionary {
            var heartRate = getCurrentHeartRate();
            var density = 0.0f;
            var sampleCount = 0;

            try {
                if ((Toybox has :SensorHistory) && (Toybox.SensorHistory has :getHeartRateHistory)) {
                    var iter = SensorHistory.getHeartRateHistory({
                        :period => new Time.Duration(HISTORY_WINDOW_MIN * 60),
                        :order => SensorHistory.ORDER_NEWEST_FIRST
                    });

                    if (iter != null) {
                        var newest = iter.getNewestSampleTime();
                        var oldest = iter.getOldestSampleTime();
                        var sample = iter.next();

                        while (sample != null && sampleCount < MAX_HISTORY_SAMPLES) {
                            if (sample.data != null) {
                                var bpm = sample.data;
                                if (bpm instanceof Number && (bpm as Number) >= MIN_HEART_RATE_BPM) {
                                    sampleCount += 1;
                                }
                            }
                            sample = iter.next();
                        }

                        if (sampleCount > 0) {
                            var windowSec = HISTORY_WINDOW_MIN * 60;
                            if (newest != null && oldest != null) {
                                var spanSec = (newest.value() - oldest.value()).toNumber();
                                if (spanSec > 0) {
                                    windowSec = spanSec;
                                }
                            }
                            density = sampleCount.toFloat() * 3600.0f / windowSec.toFloat();
                        }
                    }
                }
            } catch (ex) {
                density = 0.0f;
                sampleCount = 0;
            }

            var hasHeartRate = heartRate >= MIN_HEART_RATE_BPM;
            var rates = _storage.getDrainRates();
            var idleDensity = rates[:hrDensityIdle] as Float;
            if (idleDensity <= 0.0f) {
                idleDensity = DEFAULT_HR_DENSITY_IDLE;
            }

            return {
                :heartRate => heartRate,
                :hrDensity => (density + 0.5f).toNumber(),
                :sampleCount => sampleCount,
                :broadcastCandidate => meetsSignalThreshold(density, idleDensity, hasHeartRate, sampleCount)
            };
        }

        static function meetsSignalThreshold(hrDensity as Float, idleDensityBaseline as Float,
                                             hasHeartRate as Boolean, sampleCount as Number) as Boolean {
            if (!hasHeartRate || sampleCount < 4) {
                return false;
            }

            var threshold = idleDensityBaseline * 3.0f;
            if (threshold < 18.0f) {
                threshold = 18.0f;
            }
            return hrDensity >= threshold;
        }

        static function meetsDrainSpike(drainRate as Float, idleRate as Float) as Boolean {
            var baseline = idleRate;
            if (baseline < DEFAULT_RATE_IDLE) {
                baseline = DEFAULT_RATE_IDLE;
            }

            var threshold = baseline * 1.5f;
            var minimumAbsolute = DEFAULT_RATE_IDLE * 1.5f;
            if (threshold < minimumAbsolute) {
                threshold = minimumAbsolute;
            }
            return drainRate >= threshold;
        }

        static function shouldTrigger(hrDensity as Float, idleDensityBaseline as Float,
                                      heartRate as Number, sampleCount as Number,
                                      drainRate as Float, idleRate as Float,
                                      hasNativeActivity as Boolean) as Boolean {
            if (hasNativeActivity) {
                return false;
            }

            var hasHeartRate = heartRate >= 40;
            return meetsSignalThreshold(hrDensity, idleDensityBaseline, hasHeartRate, sampleCount)
                && meetsDrainSpike(drainRate, idleRate);
        }

        private function getCurrentHeartRate() as Number {
            try {
                if ((Toybox has :Sensor) && (Toybox.Sensor has :getInfo)) {
                    var info = Sensor.getInfo();
                    if (info != null && info has :heartRate && info.heartRate != null) {
                        return info.heartRate.toNumber();
                    }
                }
            } catch (ex) {}
            return 0;
        }
    }
}
