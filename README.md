# OSCcourier

OSCcourier is a multi-track OSC message sequencer.
Create different types of tracks — interpolated curve, step, message, bang — plus a dedicated markers track providing snap-to guides.

## Features:
- Curve editing with linear, S-curve and bulge interpolation
- Bidirectional OSC: sends messages live, and can be remotely controlled (play/pause/goto/loop) from Max/MSP or any OSC-capable app
- Loop zone and quantization grid, with an adjustable time step
- Multi-window, multi-port: run several independent sequences at once, each with its own OSC address and auto-incrementing receive port
- Autofill: populate tracks with periodic patterns automatically
- Points List window: review every point at a glance, filter by track, and attach comments
- Sequences saved as JSON

OSCcourier was initially designed to give Max/MSP the timeline it lacks — a kind of score. But since it emits standard OSC messages, it should work with any application able to receive them.

Tested with macOS 26 Tahoe and Apple Silicon.
<br> <br>

> **Note:** unsigned app (no paid Apple Developer account) — Gatekeeper will initially block it. If you get "can't be opened," go to **System Settings → Privacy & Security → Open Anyway**.

<img width="2124" height="844" alt="Capture d’écran 2026-07-23 à 16 26 54" src="https://github.com/user-attachments/assets/718cf548-2753-49e7-8ec8-5fb81ee66aea" />
