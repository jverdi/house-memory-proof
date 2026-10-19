# Requested TestFlight 228.1

Source: `f7123ca2ee6c556620b3f01cc3d6d88bc20d0597`. Delivery run: `39191585115`.

Status: native validation passed; interface validation, Apple upload and owner readiness pending.

## Changes since 216.1

- A five-step introduction with Skip, Back, three starting goals and replay settings.
- Fourteen searchable offline homeowner guides with links to the relevant app tasks.
- Clearer first-capture location and Start instructions after exploring the sample.
- Remembered movement speed, acceleration, turning, sensitivity, view width, eye height and handedness.
- Room/floor map, heading, saved viewpoints, photo positions and a remembered mini-map; unaligned visits stay separate.
- Recovery from unusable saved viewpoints, preservation of usable map markers and more stable streamed detail during small distance reversals.

This is the requested development snapshot. Precision remains disabled. Full-house software, actual-device/provider and independent field acceptance remain open. The later checked-wall map summaries and distant-room collision handoff are being validated separately in 230.1 and are absent from this snapshot.

## Suggested first check on the phone

Open Help & getting started, replay the introduction, then try Explore → Layers → Movement & view and Room map. In Tools, run synthetic self-tests and export diagnostics. The full [owner-device protocol](DEVICE_ACCEPTANCE.md) records the remaining sustained-use, accessibility, Files and measured-field checks; only record the cases actually performed.

Evidence: [native checkpoint](evidence/native-f712-summary.json). Apple upload and readiness evidence will be recorded before this document calls the build available.
