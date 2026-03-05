Baue ein Garmin Connect IQ Projekt für kompatible Garmin Uhren (CIQ 3.3+, verschiedene Auflösungen) mit dem Namen "BatteryBudget" als Widget (Glance + Detail) mit predictive „Akku heute Abend“-Prognose basierend auf on-device Historie.

Ziel / Nutzen:
- Das Widget beantwortet: „Wie viel Akku habe ich heute Abend voraussichtlich noch (typisch / konservativ / optimistisch)?“
- Ohne manuelle Eingaben des Nutzers (kein Plan eintippen). Stattdessen lernt das System aus:
  (a) realer Drain-Rate in unterschiedlichen Zuständen/Profilen (idle/activity/charging),
  (b) Wochenmuster (Wochentag + 30-min Slots), wann typischerweise Aktivität stattfindet.
- Ergebnis: End-of-day Prognose (Default 22:00) + Range + Risiko + „was kommt heute noch typischerweise“.

App-Typen:
- Primär: Widget (Glance + Detail Screens)
- Sekundär: Background Service zum Logging (wenn unterstützt); sonst degrade: Logging beim Widget-open.
- Optional: Data Field als „Turbo Logger“ während Aktivitäten, falls Profil-Erkennung im Widget/Service nicht stabil genug ist (nur wenn wirklich nötig).

Wichtige CIQ Realitäten:
- Wir dürfen NICHT davon ausgehen, dass wir eine vollständige Aktivitätsliste inkl. Battery start/end aus Garmin Connect auslesen können.
- Also: on-device Logging + Segmentbildung.
- Defensive coding: API availability und device variance.

Funktionaler Umfang (MVP v2.0):
1) Einstellungen:
   - end_of_day_time (Default 22:00, HH:MM)
   - risk_threshold_yellow (Default 30%)
   - risk_threshold_red (Default 15%)
   - conservative_factor (Default 1.20; optimistic_factor Default 0.80)
   - sample_interval_min (Default 15; nur nutzen, wenn Background möglich; sonst ignorieren)
   - learning_window_days (Default 14; max 28)

2) Snapshot Logging (battery efficient):
   - Sampling: alle 15 Minuten (Background) ODER bei Widget-open (Fallback).
   - Snapshot Felder:
     * t_min (epoch minutes oder minutes since anker)
     * batt_pct (0..100 int)
     * charging_flag (bool) oder detect via batt increase
     * state (enum): IDLE / ACTIVITY / CHARGING / SLEEP(optional) / UNKNOWN
     * profile (enum): RUN/BIKE/HIKE/OTHER/GENERIC (nur wenn state=ACTIVITY und ermittelbar)
   - Charging-Handling: steigende Battery% => CHARGING segment; diese Segmente dürfen NICHT in Drain-Lernen einfließen.

3) Segmenter:
   - Ziel: Rohsnapshots in wenige Segmente komprimieren.
   - Segment Struktur (rolling list):
     { start_t_min, end_t_min, start_batt, end_batt, state, profile }
   - Bildung:
     * gleicher state+profile wird zusammengefasst, solange keine große Lücke/Wechsel.
     * Bei state/profile Wechsel oder charging transition: Segment schließen, neues Segment starten.
   - Rate nur berechnen, wenn end_batt < start_batt:
     rate_pct_per_h = (start_batt - end_batt) / ((end_t - start_t)/60)
   - Segmente mit sehr kurzer Dauer (<10 min) ignorieren oder zusammenführen.

4) Learner (zwei Ebenen):
   A) Drain-Model (EMA) pro Kategorie:
     - rate_idle
     - rate_activity_generic
     - optional pro profile: rate_run, rate_bike, rate_hike (wenn genug Samples)
     - rate_sleep optional (wenn Sleep erkennbar; sonst nicht zwingend im MVP)
     Update:
       rate_new = (1-α)*rate_old + α*sample_rate
       α Default 0.2
     Rules:
       - nur aus nicht-charging Segmenten mit batt drop lernen
       - clamp rates in plausible range (z.B. 0.1..25 %/h) um Ausreißer zu schützen
   B) Pattern-Model (Wochentag + 30-min Slots):
     - Slots: 48 pro Tag
     - Key: weekday (0..6) + slotIndex (0..47)
     - Value: erwartete Minuten Aktivität in diesem Slot (und optional Anteil je profile)
     Minimal MVP:
       - speichere activity_minutes_expected[7][48] als float/int
       - update aus Aktivitätssegmenten: overlap minutes addieren
       - aging/rolling window: wende decay an (z.B. weekly decay 0.95 pro Tag) oder speichere per-day contributions und droppe >window
     Optional v2:
       - per-profile minutes_expected[profile][7][48]

5) Forecaster (predictive):
   Input:
     - now_time (local)
     - now_batt_pct
     - weekday
   Steps:
     - Compute remaining slots from now to end_of_day_time.
     - For each slot:
         expected_activity_min = pattern[weekday][slot]
         expected_idle_min = slot_len - expected_activity_min
         drain_slot_typical =
             (expected_activity_min/60)*rate_activity_selected +
             (expected_idle_min/60)*rate_idle
       Where rate_activity_selected = per-profile if known else activity_generic.
     - Sum drains across remaining slots:
         drain_total_typical
     - end_batt_typical = now_batt - drain_total_typical
     - end_batt_conservative = now_batt - (drain_total_typical * conservative_factor)
     - end_batt_optimistic = now_batt - (drain_total_typical * optimistic_factor)
     - Clamp outputs to 0..100
     - Risk:
         if end_batt_conservative < red_threshold -> HIGH
         else if < yellow_threshold -> MED
         else LOW
   Extras:
     - “Top expected drains remaining today”:
       finde die nächsten 1–2 Slots/Blöcke mit höchstem expected_activity_min (z.B. zusammenhängende Slots >30 min) und zeige:
         next_window_start_time, duration_est, expected_drain_pct

6) Confidence / Onboarding:
   - Confidence Score 0..1:
     * basiert auf: Anzahl Tage mit Daten im window, Anzahl Aktivitätssegmente, Abdeckung der Slots (z.B. wie viele Slots mind. 1 sample contribution haben)
   - Verhalten:
     * Confidence < 0.5 => UI zeigt “Learning” und nur grobe Schätzung (idle-only) + „n days collected“
     * Confidence >= 0.5 => volle Tonight Forecast + Range

7) UI/Views (260x260, große Lesbarkeit):
   A) Glance:
     - "Now 58% | Tonight 31% (24–36) | Risk MED"
   B) Detail Screen 1:
     - Big: Tonight 31%
     - Range: 24–36
     - Risk label
     - Confidence + last update time
   C) Detail Screen 2:
     - Learned rates:
       Idle: 1.2%/h
       Act: 5.4%/h (oder Run/Bike wenn verfügbar)
     - Next typical activity window:
       "Next: 18:00 ~60m → -5%"
   D) Detail Screen 3 (optional):
     - Mini history (letzte 24h drain vs charging) nur textuell; keine schweren Graphen im MVP

Robustheit / Fallbacks:
- Profil-Erkennung:
  - Wenn profile nicht verfügbar oder instabil: nutze ACTIVITY_GENERIC.
- Background Service:
  - Wenn nicht verfügbar/disabled: Logging nur beim Widget-open; Confidence wird langsamer steigen; UI muss das klar sagen (“Background not supported; open widget daily to learn”).
- Charging Detection:
  - batt increase => charging; ignore for drain learning; segments trennen.
- Storage Limits:
  - Speichere Segmente (rolling, capped, z.B. max 300 Segmente).
  - Pattern Arrays sind klein (7*48 ints).
  - Keine großen JSON dumps; nutze kompakte Datenstrukturen.

Projektstruktur:
- manifest.xml (CIQ 3.3+, mehrere unterstützte Geräte)
- source/
  - BatteryBudgetWidget.mc (Glance + Detail Views + Settings UI)
  - BatteryBudgetService.mc (Background logging scheduler; fallback behavior)
  - model/
    - SnapshotLogger.mc
    - Segmenter.mc
    - DrainLearner.mc
    - PatternLearner.mc
    - Forecaster.mc
    - Storage.mc (persist segments, rates, pattern, settings)
- resources/
  - strings.xml
  - layouts für 260x260 (glance + detail)
- docs/SPEC.md:
  - Datenmodell
  - State machine (idle/activity/charging)
  - Confidence definition
  - Testplan
- README.md:
  - Build/Install (Connect IQ SDK)
  - How to test on FR955
  - How learning works (kurz, ohne Marketing)

Akzeptanzkriterien (Testplan):
- Nach 3 Tagen Daten: UI zeigt “Learning”, confidence < 0.5.
- Nach 14 Tagen: Tonight Forecast + Range erscheint; Werte plausibel (nicht negativ, clamped).
- Charging wird erkannt: steigende Battery% erzeugt CHARGING segment und beeinflusst rates nicht.
- Rates werden nur aus batt drop Segmenten gelernt.
- Pattern wird genutzt: wenn der Nutzer typischerweise abends trainiert, sinkt Tonight Forecast entsprechend.
- Storage bleibt unter Limits: Segmente capped + Pattern arrays klein; App bleibt performant und battery-efficient.