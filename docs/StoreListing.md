# BatteryBudget - Connect IQ Store Listing

## Short Description (English, max. 80 chars)

Smart on-watch battery forecast with weekly training budgets and confidence.

## Description (English)

BatteryBudget helps you answer the question that matters before a workout:

**Will my watch battery still be ready when I need it?**

It combines a smart battery forecast with weekly planning and fully local,
on-watch learning.

**Smart Forecast**
BatteryBudget separates two real-world battery loads:

- **Native Garmin activities** such as runs, rides, and GPS workouts
- **External HR broadcast sessions** such as Zwift, trainer rides, or other
  cases where the watch powers the heart-rate sensor and radio stack without a
  native activity running

That dual model produces a more realistic forecast than a single generic drain
curve.

**Confidence-Based Learning**
The app learns from your real usage with exponential moving averages (EMA) and
a weekly activity pattern model. Confidence rises as more verified data becomes
available, so the forecast becomes more personal over time while staying stable
in edge cases.

**Weekly Battery Budget**
Plan your week, not just the next hour. Budget separate Native and Broadcast
hours and see how much is already consumed. BatteryBudget helps you understand
today whether your battery will still cover the training session you have
planned for Friday.

**Clear Visual Warnings**
Critical range warnings switch to red immediately. Weekly budget bars clamp at
100% and show overuse without breaking the layout.

**Responsive by Design**
The interface uses mathematically scaled, relative layout logic instead of fixed
pixel anchors, so it adapts cleanly across different Garmin display sizes.

**Private and Efficient**
Everything stays on your watch. No cloud, no account, no external analytics.
The rendering and storage model are optimized for minimal self-consumption.

**Engineered for Stability**
The alpha baseline is backed by **48 unit tests**, including extreme stress
scenarios for low battery, budget overrun, pending broadcast events, reboot
persistence, and zero-drain protection.

## Kurzbeschreibung (Deutsch, max. 80 Zeichen)

Smarte Akku-Prognose mit Wochenbudget und lokalem Lernen direkt auf der Uhr.

## Beschreibung (Deutsch)

BatteryBudget beantwortet die Frage, die vor dem Training wirklich zaehlt:

**Reicht mein Akku noch dann, wenn ich ihn brauche?**

Die App verbindet eine intelligente Akku-Prognose mit Wochenplanung und vollstaendig
lokalem Lernen auf der Uhr.

**Smart Forecast**
BatteryBudget trennt zwei reale Lastprofile:

- **Native Garmin-Aktivitaeten** wie Laufen, Radfahren oder GPS-Workouts
- **Externe HR-Broadcast-Sessions** wie Zwift oder Trainer-Einheiten, bei denen
  keine native Aktivitaet laeuft, die Uhr aber Herzfrequenzsensor und Funk
  trotzdem stark belastet

Durch dieses duale Modell ist die Prognose deutlich realistischer als bei einer
einzigen Standard-Verbrauchskurve.

**Confidence und EMA-Lernen**
Die App lernt aus deinem echten Nutzungsverhalten per Exponential Moving Average
(EMA) und ueber ein woechentliches Aktivitaetsmuster. Mit jeder bestaetigten
Session steigt die Confidence, und die Prognose wird persoenlicher und zugleich
robust gegen Ausreisser.

**Wochen-Budget statt nur Tageswert**
Plane Native- und Broadcast-Stunden getrennt und erkenne frueh, wie viel Budget
bereits verbraucht ist. So verstehst du schon heute, ob dein Akku noch fuer das
Training am Freitag reicht.

**Klare optische Warnsignale**
Bei kritischer Restlaufzeit wechselt die Warnfarbe sofort auf Rot. Wochenbudgets
werden sauber bei 100 % gedeckelt und zeigen Ueberziehung klar an.

**Responsives Design**
Die Oberflaeche nutzt relative, mathematisch skalierte Koordinaten statt fester
Pixel-Anker und passt sich dadurch sauber an unterschiedliche Garmin-Displays an.

**Datenschutz und Effizienz**
Alle Daten bleiben auf der Uhr. Keine Cloud, kein Konto, keine externe Analyse.
Rendering und Speicherung sind auf minimalen Eigenverbrauch optimiert.

**Technisch abgesichert**
Die verifizierte Alpha-Basis wird durch **48 Unit-Tests** abgesichert, darunter
Extremfaelle fuer niedrigen Akkustand, Budget-Ueberziehung, Pending-Events,
Reboot-Persistenz und Schutz vor Division durch Null.

## Suggested Keywords

- battery forecast
- battery planner
- zwift
- hr broadcast
- garmin battery
