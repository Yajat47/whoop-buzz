# WHOOP Buzz: phone alerts and the time, on a WHOOP 5.0 band

Research notes and an iPhone app that make a WHOOP 5.0 vibrate when chosen
iPhone apps send a notification, and buzz out the time when the band is tapped.
It needs only the phone at run time and a free Apple account to build.

This is an unofficial personal research project. It is not affiliated with,
endorsed by or supported by WHOOP or Apple. WHOOP and Apple Watch are
trademarks of their owners. Use it on your own band at your own risk.

## How it works

1. An iOS 27 Shortcuts **Notification** automation fires when a chosen app
   posts a notification.
2. It runs a background App Intent, **Buzz WHOOP**, in a small app.
3. The app sends the band a haptic command over Bluetooth LE.

The band also reports double taps and the tap that lights its battery
indicator. The app listens for those and plays the time as a short pattern of
buzzes, following the Apple Watch "Terse" scheme.

## Where things are

| Path | What it is |
|---|---|
| `CLAUDE-HANDOVER.md` | The original brief: protocol, constraints and what was known at the start |
| `TECHNICAL-ARCHITECTURE.md`, `research-plan.md`, `reconnect-findings.md`, `live-hr-findings.md` | Notes on the band's Bluetooth behaviour |
| `WhoopBuzz/` | The first app: manual buzz, then the Shortcuts action |
| `Claude-Experiments/README.md` | Lab notebook: what was tried, what the logs showed, what is still unproven |
| `Claude-Experiments/WhoopTime/` | The most complete app: burst handling, tap for the time, reconnection, battery logging |
| `Claude-Experiments/sidestore/` | Keeping a free-signed app alive with SideStore |
| `decode_capture.py` | Offline decoder for Apple PacketLogger captures |
| `references/` | Links and hashes for the third-party sources used |

Each app folder has a `Verification/main.swift` that checks framing, the alert
burst rule and the time code on a Mac:

```sh
cd Claude-Experiments/WhoopTime
swiftc Sources/WhoopFrame.swift Verification/main.swift -o /tmp/check && /tmp/check
```

## What is left out of this public copy

- Raw Bluetooth captures and everything decoded from them. They contain a
  link key, device addresses and health data. The notes still describe what
  they showed.
- Copies of the app's data from the phone, build and install logs, and signed
  app files.
- Third-party source snapshots. `references/` lists where to fetch them.
- Personal identifiers. Device IDs, account IDs and local paths are replaced
  with placeholders such as `<DEVICE-UDID>` and `<TEAM-ID>`, the band's serial
  number is zeroed in the test data, and heart-rate values are removed.

The Xcode projects have no signing team set. Choose your own in Xcode. The
helper scripts read `PHONE_UDID`, `WHOOP_BUZZ_BUNDLE` and `SIDESTORE_BUNDLE`
from the environment.

## State

Shown working on one band (firmware 50.42.1.0) and one iPhone 15 on iOS 27.0:
alerts buzzing the band with the phone locked, tap for the time, and on-phone
re-signing with SideStore. Several later changes have not been run on a phone;
the notebook says which. Nothing here has been tried on another band,
firmware or iOS version.
