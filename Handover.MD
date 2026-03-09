==============================================================================
PROJECT CONTEXT & HANDOVER
==============================================================================
Target Platform: Garmin Connect IQ (Monkey C)
Current Status: Alpha-Completion (v1.0.0-alpha)

### STATUS QUO
- 48 Unit Tests: PASS (100%)
- Build: FR955 and Vivoactive4 SUCCESSFUL
- UI: Fully transitioned to Relative Design (H/W factors).

### KEY ARCHITECTURE
- Relative Design: UI scaling via H/W factors (centerY anchor).
- Dictionary-Params: Bypassing the 9-argument limit on legacy devices.
- Safety: Zero-division protection and state persistence verified.
- Detection: Hybrid (HR signal + Drain spike validation).

### BACKLOG
- [ ] Field testing (EMA validation at wrist)
- [ ] Confidence Metric visualization (Data maturity)
- [ ] Haptic alerts for range < 2.0 days
==============================================================================