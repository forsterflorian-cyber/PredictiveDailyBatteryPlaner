# BatteryBudget – Connect IQ Store Listing (v1.0.0)

---

## Kurzbeschreibung (Deutsch, max. 80 Zeichen)

Intelligente Akku-Prognose – lernt automatisch aus deinem Nutzungsverhalten.

---

## Beschreibung (Deutsch)

**BatteryBudget** beantwortet die eine Frage, die jeder Garmin-Traeger kennt:
"Wie viel Akku habe ich heute Abend noch?"

Das Widget lernt vollstaendig auf der Uhr – ohne Cloud, ohne manuellen Aufwand:

**Adaptives Lernen**
BatteryBudget beobachtet deinen echten Akku-Verbrauch in verschiedenen Zustaenden
(Standby, Laufen, Radfahren, Wandern, Schlaf) und passt seine Vorhersage
automatisch an deine Uhr und dein Trainingsverhalten an. Der EMA-Lernalgorithmus
aktualisiert sich bei jeder neuen Messung – je mehr Tage du die App nutzt, desto
praeziser wird die Prognose.

**Solar-Synergie (Fenix/Epix)**
Auf Solar-faehigen Uhren beruecksichtigt die App die aktuelle Sonnenintensitaet und
die gelernte Solar-Ladegeschwindigkeit direkt in der Prognose.

**Aktivitaets-Planer (What-If)**
Willst du heute noch eine Stunde laufen? Die App zeigt dir sofort, wie viel Akku
du danach voraussichtlich noch haben wirst – basierend auf deiner gelernten,
sportspezifischen Verbrauchsrate.

**3 Prognosen auf einen Blick**
- Typisch: dein wahrscheinlichster Akkustand heute Abend
- Konservativ: das pessimistische Szenario
- Optimistisch: bestes Fall-Szenario

**Risiko-Ampel**: NIEDRIG / MITTEL / HOCH – sofort erkennbar.

**Hintergrund-Logging**
Ein leichtgewichtiger Background-Prozess (<32 kB RAM) schreibt alle 15 Minuten
einen Snapshot, damit die Prognose auch dann praezise bleibt, wenn das Widget
nicht geoeffnet ist.

**Hinweis zur Lernphase:**
In den ersten 24–48 Stunden zeigt die App "LEARNING" und eine grobe Schaetzung.
Nach ca. 14 Tagen Nutzung liefert die Prognose ihre volle Genauigkeit.

**Alle Daten bleiben auf der Uhr.** Keine Cloud, keine Synchronisation, kein Account.

---

## Short Description (English, max. 80 chars)

Smart battery forecast that learns from your real usage — on-device, no cloud.

---

## Description (English)

**BatteryBudget** answers the question every Garmin wearer asks:
"How much battery will I have left tonight?"

The widget learns entirely on your watch — no cloud, no manual setup required.

**Adaptive Prediction**
BatteryBudget tracks your real battery drain across different states
(idle, running, cycling, hiking, sleep) and adapts its forecast to your specific
watch and activity style. The EMA learning algorithm updates with every new
measurement — the longer you use the app, the more accurate it becomes.

**Solar Synergy (Fenix / Epix)**
On solar-capable watches, the app factors in current sunlight intensity and your
learned solar charge rate directly into the end-of-day forecast.

**Activity Planner (What-If)**
Thinking about a 60-minute run this afternoon? The app immediately shows how much
battery you'd likely have afterward — based on your own learned, sport-specific
drain rate.

**3 Forecasts at a Glance**
- Typical: your most probable end-of-day battery level
- Conservative: the pessimistic scenario
- Optimistic: best-case scenario

**Risk Indicator**: LOW / MED / HIGH — spot the risk without squinting at numbers.

**Background Logging**
A lightweight background process (<32 kB RAM) writes a snapshot every 15 minutes
so the forecast stays accurate even when the widget is closed.

**Learning phase note:**
During the first 24–48 hours the app shows "LEARNING" and a rough idle-only
estimate. After ~14 days of use the forecast reaches its full accuracy.

**All data stays on your watch.** No cloud, no sync, no account needed.

---

## Keywords (for Store search optimisation)

1. battery life
2. battery forecast
3. battery planner
4. power management
5. energy monitor

---

## Permissions

| Permission | Why it is needed |
|---|---|
| **Background** | Periodic background snapshots for accurate learning even when the widget is closed. If denied, BatteryBudget falls back to logging only when the widget is opened. |
| **UserProfile** | Reads sleep/wake time from the Garmin profile to improve the sleep-window drain model. |

---

## Privacy

All computation and all stored data remain **on your watch**.
BatteryBudget transmits nothing to any server or third party.

---

## What's New – v1.0.0

- Initial release.
- Adaptive drain-rate learning with EMA per state (idle / activity / sleep).
- Sport-specific profiles: Run, Bike, Hike, Swim.
- Solar gain estimation and forecast integration (Fenix / Epix solar models).
- Activity Planner: What-If calculation for planned training sessions.
- Weekly activity pattern learning (7 x 24 hourly slots).
- Battery history chart (last 24 readings).
- Adaptive background sampling: shorter intervals during activity/charging,
  longer during idle/sleep to minimise battery impact.
- Abnormal-drain detection: flags when idle rate is >50% above baseline.
- Full localisation: German / English.

---

## Supported Devices (v1.0.0)

| Series | Models |
|---|---|
| Forerunner | 255 / 255S / 255M / 255SM, 265 / 265S, 955, 965 |
| Fenix 7 | fenix 7 / 7S / 7X / 7 Pro / 7S Pro / 7X Pro |
| Epix Gen 2 | epix 2 / 2 Pro 42 mm / 47 mm / 51 mm |
| Venu / Vivoactive | Venu 2 / 2 Plus / 2S / 3 / 3S, Venu Sq 2 / 2M, vivoactive 5 |
