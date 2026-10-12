# WHOOP 5.0 research — handover for Claude

Updated: 9 October 2026. Local project: `<project>`.

**Latest development:** Apple’s live iOS 27 Shortcuts guide documents a **Notification** automation trigger with an app selector, and the owner confirmed **“Yes, Notification is available”** on the phone. The **Buzz WHOOP** App Intent has signed with the free account and reached the real band, producing a brief physical buzz. Cleanup and Bluetooth-state handling fixes are now installed, as described below. The updated action, real WhatsApp triggering, and locked-phone behavior still need tests. This is a separate route from the blocked Accessory Notifications extensions. See `WhoopBuzz/Sources/BuzzWhoopIntent.swift`, `WhoopBuzz/stop-fix-build.log`, and `WhoopBuzz/stop-fix-install-result.json`. The manual-only source baseline is saved under `WhoopBuzz/ManualBuzzBaseline/`. Prioritize this Shortcuts route over the earlier signing block.

**Follow-up fix installed:** The owner's Shortcuts run did reach WHOOP, receive command-19 success (`result 1, detail 5`), and physically buzz briefly. The old app then sent an unnecessary stop two seconds later, received stop failure, and left its busy flag set. App-local preference logs in `WhoopBuzz/Diagnostics/stop-failure-preferences.plist` establish that order. A fresh old-build test lost Bluetooth as the action started and produced no vibration; its log is `fresh-test-preferences.plist`. The owner says the shortcut contains only Buzz WHOOP, with no Bluetooth toggle. The new build now skips the extra stop after a confirmed bounded one-shot, retains a two-second cooldown, clears busy on terminal failures, and avoids retrying a rejected stop automatically. It logs precise Bluetooth state and distinguishes connection loss from a missing vendor reply. Signed build, protocol/semantic checks, installation, and relaunch passed (`stop-fix-build.log`, `stop-fix-install-result.json`, `stop-fix-launch-result.json`). Startup log shows Bluetooth initially powered off and then ready again. Retest the updated action twice, then a real locked-phone notification; neither has yet been validated on this updated build.

## Your task

Investigate and, where feasible, implement an **iPhone-only notification trigger that makes the owner's WHOOP 5.0 vibrate for WhatsApp, WhatsApp Business, and other selected iPhone apps**. A manual iPhone-to-WHOOP buzz already works on the real band. Receiving other apps' notification events is the remaining problem.

The Mac may build, install, and capture experiments. The finished bridge must work without the Mac running nearby. The owner has **only a free Apple signing account / Personal Team**. A paid membership is not available and should not be treated as an already solved requirement. The owner wants a research/hack approach, with short, simple updates.

Start by reading this file, `WhoopBuzz/prototype-status.json`, and the four Swift source files. Independently assess possible notification triggers. Produce a concrete result: a working experiment, or an evidence-backed explanation of which requirement prevents it and the smallest useful next test. Do not call manual buzzing a finished notification bridge.

## Parallel work

Codex and Claude may work on this project at the same time. Put your code changes and new outputs under `Claude-Experiments/`; copy the small app project there if you need to change it. Treat original captures and existing source files as shared evidence. Agree on use of the physical iPhone, band, PacketLogger, and app installation before both sessions try to control them at once. Keep the working installed buzz app available as a baseline.

No Git repository or branch workflow has been set up for this research folder.

## Confirmed state

- Band: **WHOOP 5.0**. WHOOP One is the owner's membership name.
- iPhone: iPhone 15, device name `<phone-name>`, iOS **27.0**, build `24A437`.
- Mac: macOS 26.6.2; Xcode 27.0; iPhoneOS SDK 27.0.
- iPhone Developer Mode is enabled; pairing/trust and USB deployment worked.
- Apple Bluetooth logging profile is installed. PacketLogger successfully records the iPhone's Bluetooth traffic.
- `WhoopBuzz` was signed, installed, and launched on the owner's phone.
- Owner explicitly reported: **“tested one buzz , it works”**.
- This confirms physical vibration from the app's foreground **Test one buzz** button. Locked-phone operation, background execution, automatic notification triggering, reconnection reliability, and physical completion of the stop command have not been validated.
- Candidate firmware version from the captured hello reply: **50.42.1.0**. Parsed from hello response-body offsets 91–97; the app uses the same interpretation. This matches the public haptics reference, but remains an interpreted version field.

`WhoopBuzz/prototype-status.json` is the latest status. Some earlier reports and reference-manifest descriptions still say haptics are untested; that wording predates the owner's successful test.

## The specific signing block already reproduced

An isolated, non-installed ExtensionKit probe lives in `WhoopBuzz/NotificationProbe/`.

- It implements `AccessoryTransportAppExtension`, declares the `com.apple.accessory-transport-extension` extension point, and requests `com.apple.developer.accessory-transport-extension = true`.
- Unsigned SDK 27 compilation **passed**: `unsigned-build.log`.
- Automatic development signing **failed**: `signing-build.log`, line 35.
- Xcode's relevant error: **“Personal development teams … do not support the Accessory Transport Extension capability.”**
- Its source rejects incoming sessions and never contacts the band. It was not installed.

This is an actual provisioning restriction, not a guessed Bluetooth problem. Do not repeat certificate repair or assume a plist entry can bypass it. A paid team might clear the signing gate, but that would not prove WHOOP supports the required secure accessory protocol.

## Notification routes: facts and open questions

### Normal app notification APIs

`UNUserNotificationCenter` handles an app's own notifications. It does not provide a general listener for WhatsApp or WhatsApp Business notifications. A notification service extension belongs to the app receiving that push; adding one to our app does not let us inspect WhatsApp pushes. Bluetooth background mode and an App Intent can help execute a buzz, but neither provides the missing notification event by itself.

### New Apple Accessory Notifications framework

Do not give an outdated blanket answer that iOS has no third-party notification forwarding API. Apple now has **AccessoryNotifications**, available from iOS 26.5, with companion extensions through **AccessoryTransportExtension**. Both frameworks exist in the local SDK 27.

Apple's documented route:

1. Register/select the accessory with `AccessorySetupKit`, obtaining an `ASAccessory`.
2. Call `AccessoryNotificationCenter.requestForwarding(for:)`. The person can allow all apps, selected apps, or no apps.
3. An `AccessoryDataProvider` extension receives notification details. Its entitlement is `com.apple.developer.accessory-data-provider`; extension point is `com.apple.accessory-data-provider`; `EXCapabilities` includes `AccessoryNotifications.NotificationsForwarding`.
4. An `AccessoryTransportSecurity` extension manages accessory key exchange. Its entitlement is `com.apple.developer.accessory-transport-security`; extension point is `com.apple.accessory-transport-security`.
5. An `AccessoryTransportAppExtension` relays encrypted messages over Bluetooth. Its entitlement is `com.apple.developer.accessory-transport-extension`; extension point is `com.apple.accessory-transport-extension`.

The accessory generates key material and decrypts forwarded data using HPKE; cipher suites include xWing and p256. WHOOP compatibility with this exchange has **not** been established. Knowing how to send WHOOP command 19 does not establish that it accepts this protocol. Treat any proposed software adaptation as an experiment needing evidence.

Apple permits **development/testing in any region**. Customer use is limited to iPhones physically in the EU with an EU Apple Account region. The owner is outside the EU; that alone does not rule out development testing. The current demonstrated block is free-team signing.

Use `AlertingContext.shouldAlert` if this route becomes usable, so Focus and notification preferences are respected. Local SDK interfaces use the current `messageReceived(_:completion:)` API; some documentation examples still show deprecated `dataEventHandler(event:)`.

### ANCS: possible hardware route, unconfirmed

Apple Notification Center Service (ANCS) lets a compatible Bluetooth accessory receive iPhone notifications directly. This requires accessory-side support; our phone app cannot simply become a universal notification listener through ANCS.

ANCS service UUID: `7905f431-b5ce-4e99-a40f-4b1e122d00d0`. An earlier raw-ACL search did not find its little-endian UUID bytes in any of the three saved captures. **Absence in those captures does not prove WHOOP lacks support.** No ANCS activation or notification forwarding was observed.

The owner checked **iPhone Settings → Bluetooth → the “i” beside WHOOP** and reported: **“No Share System Notification.”** There is no visible notification-sharing switch for this WHOOP connection. Combined with the captures, this gives us no demonstrated ANCS route. It does not by itself prove the firmware could never support ANCS or expose it after a different setup. Do not tell the owner to enable a switch that is absent.

### Other proposed triggers

No cloud webhook, WhatsApp Business API account, server, Mac notification listener, extra BLE hardware, or jailbreak has been set up. A WhatsApp Business Cloud API webhook is not automatically available merely because the owner uses the Business phone app, and a server changes the stated phone-only scope.

The newly found Shortcuts route has official documentation evidence: [Apple’s event triggers guide](https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/ios) now lists “The Notification trigger” with an App selector and optional message/subtitle/title filters. Direct live retrieval showed the iOS 27 page; a search-tool regional cached rendering still showed older iOS 26 content. The live HTML, retrieval date, and SHA-256 are saved in `references/apple-shortcuts-event-triggers-2026-10-09.html` and `references/apple-shortcuts-event-triggers-source.json`. The owner confirmed that the Notification trigger is available on their iPhone. Visibility, documentation, and compilation are not proof that a real incoming WhatsApp notification executes the action.

## Working buzz app

Project: `WhoopBuzz/WhoopBuzz.xcodeproj`; shared scheme: `WhoopBuzz`.

| File | Purpose |
|---|---|
| `Sources/WhoopFrame.swift` | Three allowed commands; frame encoding, CRC checks, reply buffering |
| `Sources/WhoopBluetooth.swift` | Foreground discovery, connect, subscribe, hello, serialized writes, response handling |
| `Sources/WhoopBuzzApp.swift` | SwiftUI connection controls, Test one buzz, Stop vibration, short research log |
| `Sources/BuzzWhoopIntent.swift` | iOS 27 Buzz WHOOP App Intent and App Shortcuts registration |
| `Info.plist` | Bluetooth usage description and `bluetooth-central` background mode |
| `Verification/main.swift` | Captured hello parity, fragmented reply parsing, corruption rejection, resynchronization |
| `Verification/result.txt` | Passing checks and exact outgoing frame hex |
| `prototype-status.json` | Latest deployment and owner-reported validation status |

The app retrieves already connected WHOOP peripherals by service UUID, then can scan in the foreground for up to 15 seconds. It discovers the custom command/reply characteristics, subscribes to replies, sends hello, and enables the buzz button after success. It uses `.withResponse` writes, checks the allowed write size, and matches vendor replies by command and echoed origin sequence.

Pending result 2 stays pending; success is 1, failure is 0, unsupported is 3. A Bluetooth write acknowledgement is separate from a vendor reply and physical vibration. Replies are buffered across fragments, with length/CRC validation and a 4096-byte bound. Commands have 10-second response limits; setup has a 15-second limit. Session-generation checks guard stale callbacks.

The new UI and App Intent share a single `WhoopBluetooth` instance. Successful hello saves the peripheral UUID in app-local preferences. The action reconnects to that saved peripheral without a background scan, rejects overlapping tests, and awaits the one-shot reply with a 20-second overall limit. Normal success requires command result 1, revision 1 and detail 5, followed by the short cooldown; no extra stop is sent on this path. The intent supports background execution, targets the main app process, and permits execution without unlocking. Research log entries are persisted locally for checking failures after a background run. Actual locked-phone operation remains untested. Connect the band once in the updated app before using the action.

The Test button sends one finite pattern and holds the app busy for a two-second cooldown. At that guard deadline, a confirmed one-shot finishes without sending a stop; an unconfirmed request still gets a stop fallback. The Stop button is available during a test. A suspended app's timer is not a validated background stop mechanism. A failed or timed-out stop disables readiness until reconnecting while clearing the busy flag. No alarm schedule, history transfer, feature-setting writes, or firmware update command is used by this app.

## WHOOP protocol needed for a buzz

These UUIDs were confirmed by actual service discovery in the reconnect capture. Attribute handles below belong to this recorded database; use UUID discovery in code.

| UUID | Recorded handle | Role |
|---|---|---|
| `fd4b0001-cce1-4033-93ce-002d5875f58a` | — | Custom service |
| `fd4b0002-cce1-4033-93ce-002d5875f58a` | `0x099b` | Command write; both write modes advertised |
| `fd4b0003-cce1-4033-93ce-002d5875f58a` | `0x099d` | Command reply notifications |
| `fd4b0004-cce1-4033-93ce-002d5875f58a` | `0x09a0` | Event-capable channel |
| `fd4b0005-cce1-4033-93ce-002d5875f58a` | `0x09a3` | Live data, stored data, metadata, logs, events |
| `fd4b0007-cce1-4033-93ce-002d5875f58a` | `0x09a6` | Notify-capable; purpose unconfirmed |

WHOOP 5 format-1 envelope, offsets starting at zero after removing Bluetooth wrappers:

```text
0..1    AA 01
2..3    declared length, uint16 little endian = inner length + 4
4..5    outgoing header bytes 00 01
6..7    CRC16 Modbus of bytes 0..5; init FFFF, polynomial A001, little endian
8..N-5  inner payload
N-4..N-1 CRC32 of inner payload, zlib-compatible, little endian
total length = declared length + 8
```

Outgoing command inner payload is `[35, sequence, command] + body`, **padded with zeros to a multiple of four bytes before CRC32**. Incoming reply inner payload is `[36 or 38, replySequence, command, originSequence, result] + body`.

| Command | Body | Evidence |
|---|---|---|
| 145 hello | `03` | Revision used by the owner's official-app capture; exact frame parity checked |
| 19 one notification buzz | `01 2F 98 00 00 00 00 00 00 00 00 00` | Public WHOOP 5 reference; physical vibration confirmed by owner |
| 122 stop haptics | `01` | WHOOP 5 revision-1 reference; app processes reply, physical completion not separately observed |

Exact generated examples:

```text
hello, sequence 1: aa0108000001e671230191031a5f5263
buzz, sequence 2:  aa0114000001e1e1230213012f9800000000000000000000e1a1feb4
stop, sequence 2:  aa0108000001e67123027a0148aa9032
```

The buzz frame is 28 bytes after padding. WHOOP 4 haptic commands/body variants should not be substituted into this WHOOP 5 experiment.

## Existing architecture research

Three original PacketLogger captures are present. Each has `.decoded.json` and `.frames.jsonl` outputs containing raw WHOOP frames, validity checks, timestamps, record indices, and offsets.

| Capture | PacketLogger records | Valid complete WHOOP frames | Main observation |
|---|---:|---:|---|
| `whoop-baseline-01.pklg` | 1,922 | 567 | 339 stored records; 42 live frames; command/reply traffic |
| `whoop-reconnect-01.pklg` | 3,674 | 968 | Service discovery and encrypted reconnection; 441 contiguous stored records |
| `whoop-live-hr-01.pklg` | 2,445 | 305 | 91 live frames over 90.001 seconds, approximately 1 Hz |

All complete frames passed declared length, CRC16, and CRC32 checks. The offline decoder is `decode_capture.py`; run `python3 decode_capture.py CAPTURE.pklg` from the research folder. It reads saved files and sends no Bluetooth commands. Unsupported fragments are counted; do not mistake its complete-frame count for every transmitted byte.

Reconnect findings: successful connection → encryption at +0.273 seconds → MTU 247 at +0.365 seconds → characteristics at +0.875 seconds → hello at +1.502 seconds → data-range query at +2.015 seconds → stored-data request at +3.366 seconds. The first post-reconnect stored record arrives at +3.558 seconds. Its 142-record burst ends at +5.060 seconds. Across the capture, counters 101565–102005 are unique and consecutive. This is reconnection to an already paired band, not a first bond.

Live HR candidate: full-frame byte 16 for the observed 32-byte type-40 shape with raw byte 9 equal to 2. Candidate values stay in a plausible resting range, and several samples equal the one untimed reading the owner took from the app. **No timed app comparison has validated the field yet.** Byte 17's candidate RR count is zero throughout. Device seconds are at byte 10, an unresolved additional time field at 14. Do not parse byte 10 as a command code in live messages.

Device-time interpretation is about ten hours behind PacketLogger time; clock alignment is unresolved. Use record order and relative capture intervals. Captures include unrelated Bluetooth devices; identify WHOOP connections before assigning HCI events. ATT UUID128 values are reversed as a full 16-byte value for display, not interpreted as a mixed-endian GUID.

Read `research-plan.md`, `reconnect-findings.md`, `reconnect-comparison.json`, and `live-hr-findings.md` for details. These Bluetooth traces do not establish WHOOP cloud traffic or proprietary score calculations.

## Build and device commands

Use separate output paths for Claude experiments to avoid colliding with Codex builds. These commands describe the known working baseline:

```sh
cd <project>/WhoopBuzz
swiftc Sources/WhoopFrame.swift Verification/main.swift -o /tmp/whoop-framing-check
/tmp/whoop-framing-check

xcodebuild -project WhoopBuzz.xcodeproj -scheme WhoopBuzz \
  -sdk iphoneos -configuration Debug \
  -destination id=<DEVICE-UDID> -derivedDataPath Build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

xcrun devicectl device install app \
  --device <DEVICE-UDID> \
  Build/Build/Products/Debug-iphoneos/WhoopBuzz.app

xcrun devicectl device process launch \
  --device <DEVICE-UDID> dev.yajat.WhoopBuzzResearch
```

Signing team in the baseline project: `<TEAM-ID>`, free Personal Team. The development profile expires **15 October 2026 at 23:23:59 UTC**; the installed prototype may need rebuilding/reinstallation after expiry. Signing was repaired by refreshing Xcode's Apple Account/Manage Certificates screen; no certificates were revoked. The baseline's signed build/install/launch evidence is in `install-build.log`, `install-result.json`, and `launch-result.json`.

PacketLogger app: `/Volumes/Additional Tools/Hardware/PacketLogger.app`. Although downloaded from the Additional Tools for Xcode 27 package, this app reports version 26.0. With the phone connected by USB, **File → New iOS Trace** produces a live source named <phone-name>. After stopping, no live source name is normal. Do not overwrite original captures. Avoid dumping the entire PacketLogger accessibility tree; it can be enormous.

SDK frameworks: `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks`. Accessory framework Swift interfaces include `Modules/FRAMEWORK.swiftmodule/arm64e-apple-ios.swiftinterface`.

## References and verification

Local snapshots and source hashes are in `references/sources.json`.

- [Goose protocol code, pinned revision](https://github.com/b-nnett/goose/blob/ba9ae0280c9b5b9a1545baab8e944cb3b7563c62/Rust/core/src/protocol.rs).
- [Goose command definitions, pinned revision](https://github.com/b-nnett/goose/blob/ba9ae0280c9b5b9a1545baab8e944cb3b7563c62/Rust/core/src/commands.rs).
- [NOOP WHOOP 5 haptics reference, pinned revision](https://github.com/ryanbr/noop/blob/8e94d559be273ec8d74832fe5db78898be83cc11/docs/PROTOCOL_ALARMS.md).
- [NOOP sensor reference, pinned revision](https://github.com/ryanbr/noop/blob/8e94d559be273ec8d74832fe5db78898be83cc11/docs/PROTOCOL_SENSORS.md).
- [Apple Accessory Notifications](https://developer.apple.com/documentation/accessorynotifications).
- [Apple: Receiving iOS notifications on an accessory](https://developer.apple.com/documentation/accessorytransportextension/receiving-ios-notifications-on-an-accessory).
- [Apple transport security/key exchange](https://developer.apple.com/documentation/accessorytransportextension/accessorytransportsecurity).
- [Apple accessory setup](https://developer.apple.com/documentation/accessorysetupkit/discovering-and-configuring-accessories).
- [Apple ANCS specification](https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleNotificationCenterServiceSpecification/Introduction/Introduction.html).

Apple documentation may return a JavaScript-only page. Appending `.md` to the documentation URL worked for direct retrieval. Recheck current docs and the local SDK for any new claimed capability; distinguish official API support, community interpretation, compile success, signing success, and actual hardware behavior.

## Where to resume

1. Test the new iOS 27 Shortcuts **Notification** trigger and **Buzz WHOOP** action first. Connect the band once in the updated app, create a shortcut with the action, and run it manually. Then bind the Notification trigger to WhatsApp or WhatsApp Business and prove it fires from a real incoming alert. The Share System Notifications check is complete and that separate switch is absent.
2. If researching another trigger, identify the exact supported event and prove it fires for a real incoming WhatsApp or WhatsApp Business notification. Avoid fake notifications or a timer as a substitute for that proof.
3. Reuse the working frame encoder and buzz command when a real trigger is available. Then verify locked-phone/background operation, Focus behavior, disconnection/reconnection, and prevention of repeated or overlapping buzzes.
4. If no viable path is found, report the evidence and the constraint that would have to change. Do not promise that a paid account, a background mode, a Shortcut, or a firmware command solves the bridge without a test.
