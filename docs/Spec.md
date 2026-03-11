# Technical Specification

## Forecast

- End-of-day battery uses the learned idle/activity drain model across the
  remaining local-day slots.
- Confidence is a weighted combination of drain-rate confidence and pattern
  coverage confidence.
- Solar gain is applied conservatively and is suppressed after a charge cycle
  until fresh post-charge samples exist.

## Detection

- Native activities come from `Activity.getActivityInfo()`.
- HR broadcast candidates require dense heart-rate sampling on an otherwise
  idle/sleep segment.
- A segment is promoted to broadcast only when the HR signal threshold and the
  drain spike threshold are both met.

## Persistence

- Persisted state is limited to current segment, learned rates, activity
  pattern, last snapshot, battery history, weekly plan state, and pending
  broadcast confirmations.
- Legacy full-segment history is explicitly purged during startup migration to
  avoid low-memory failures on older targets.
