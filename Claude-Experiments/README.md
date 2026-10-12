# Claude experiments — iPhone-only notification bridge

9 October 2026. Nothing in this folder has been installed on the phone or has sent a Bluetooth command. The only device access was copying the buzz app's saved log over USB.

## Result

A supported, free-account, phone-only trigger exists: the iOS 27 Shortcuts **Notification** automation ("When I receive a notification from [apps]"). Paired with a background App Intent that sends the already-proven buzz, it completes the bridge without any restricted entitlement.

Codex reached the same route in parallel and has installed a **Buzz WHOOP** action in the main app. This folder adds independent evidence from the phone's own OS build, a defect found in the first live run with a fixed build, the risks to check next, and a tool that proves from the Mac whether a Shortcuts-started buzz ran.

**Status 12:05:** the bridge works with the phone unlocked: Shortcuts-started buzzes are confirmed by the band, and the owner reports starting runs by sending a WhatsApp text. Not yet proven: WhatsApp Business, and a run with the phone locked.

## Resolved 12:05: a second automation was switching Bluetooth off

Owner's report: "it was another automation". With that out of the way, two Shortcuts-started buzzes ran back to back with Bluetooth staying on:

| Time | Event |
|---|---|
| 12:05:02 | Shortcuts request; buzz reply result 1, detail 5; confirmed 12:05:04 |
| 12:05:10 | Shortcuts request; buzz reply result 1, detail 5; confirmed 12:05:12 |

No system Bluetooth power change followed. The owner did not say what the other automation contained or whether these two runs came from WhatsApp messages; the earlier 11:59:30 run was WhatsApp-triggered by the owner's account.

Still to prove: a WhatsApp Business alert, a run with the phone locked, and behaviour when several alerts arrive at once (the main app still fails overlapping requests instead of joining them).

Owner, 12:1x: tested with the phone locked, and it works.

## SideStore: installed and working, 13:21

Full runbook, including what the nightly refresh needs and how to recover: `sidestore/README.md`.

The app on the phone is now signed and refreshed by SideStore instead of Xcode.

| Item | State |
|---|---|
| SideStore | 0.7.0 alpha (build 20260911), installed with iloader 2.3.6, bundle `com.SideStore.SideStore.<TEAM-ID>` |
| WHOOP Buzz | **New bundle ID `dev.yajat.WhoopBuzzResearch.<TEAM-ID>`**, installed by SideStore from `sidestore/WhoopBuzz-main.ipa` (Release build of the main sources as of 11:03) |
| Signing expiry | 16 October 2026, 02:21 UTC for WHOOP Buzz; SideStore itself 02:18 UTC. Each refresh resets the 7 days |
| On-phone refresh on iOS 27.0 | Worked: SideStore's log shows `Finished refreshing … success` at 13:18 |
| Bridge after the move | Three Shortcuts-started buzzes requested and confirmed from 13:21:53; owner reports the WhatsApp test worked |
| Xcode certificate | Still valid at Apple (serial removed). SideStore added its own and revoked nothing |

What changed on the phone to make room (three free-signed apps is the device limit): another development app and the Xcode-installed WHOOP Buzz were removed at the owner's request. A third development app remains.

**For Codex:** do not `devicectl install` the Xcode build any more. It would arrive as a fourth free-signed app (`dev.yajat.WhoopBuzzResearch`) and the phone will refuse it. Updates now go in as an IPA through SideStore, which replaces the app in place and keeps its data and the Shortcuts automation. To make one: Release build, put `WhoopBuzz.app` in a `Payload` folder, zip it as `.ipa`, copy it to SideStore's Documents with `devicectl device copy to --domain-type appDataContainer --domain-identifier com.SideStore.SideStore.<TEAM-ID>`, then add it in SideStore with +.

Keeping it alive: within every 7 days, with Wi-Fi on and LocalDevVPN connected, open SideStore and refresh. SideStore also tries in the background. If the pairing file stops working (often after an iOS update), it has to be replaced with iloader on the Mac.

`pull-buzz-log.sh` and `bluetooth-off/live-watch.sh` now default to the new bundle ID.

Refresh by Shortcuts, tested 13:36: the owner's "Refresh SideStore" shortcut (Set VPN connect to LocalDevVPN, wait, SideStore's Refresh All Apps, Set VPN disconnect) ran SideStore's background refresh. Its log shows new profiles installed for both apps (`misagent_install succeeded`, `completed successfully`) and expiry moved to 16 October 02:36 UTC. A daily Time of Day automation runs the same shortcut.

Scheduled run, tested 14:11: with the automation set to 14:11 and the phone locked and on USB, SideStore was started fresh in the background (new log `console_20261009_141108_329.log`), installed new profiles for both apps and finished in 6.2 s. Expiry moved to 16 October 03:11 UTC. The phone reported itself locked 25 seconds later. Not yet seen: the same run with the phone unplugged, or on a later night.

## Burst fix: `WhoopQuiet/` (built 15:12, not yet on the phone)

Owner's report: several WhatsApp alerts at once give too many buzzes, and then the automation fails.

Cause, read from the installed app's code (the phone was unplugged, so its log was not checked): every alert outside the two-second cooldown buzzes again, and a request that arrives while a buzz is running throws "WHOOP is already running a vibration test", which Shortcuts reports as a failed automation.

Fix, in `WhoopQuiet/` (main sources as of 11:03 plus `quiet.patch`, which applies cleanly to them):

- One buzz covers every alert that lands while it runs or within a quiet time after it. The extra requests return success without buzzing.
- Quiet time is a setting in the app: 5, 10, 30, 60 or 120 seconds, default 10.
- The quiet time starts only after a buzz the band confirmed, so a failed attempt does not mute the alerts that follow.
- The log gets one line when alerts start being skipped and one count at the next buzz, not a line per alert.

Checked on the Mac: `WhoopQuiet/Verification/main.swift` passes 8 checks of the rule, including a 13-alert burst giving 2 buzzes; the framing checks still pass; Release build has no warnings. Installable file: `sidestore/WhoopBuzz-quiet.ipa`. **Not run on the phone.**

## Idea: double-tap the band to feel the time (`WhoopTap/`, built 16:01, not on the phone)

Proposed mechanism: the band reports a double tap as an event, the app is woken by it, works out the time and plays it back as a short pattern of buzzes.

What supports it:

- The Goose reference lists strap event 14 as `DOUBLE_TAP`.
- The owner's captures show the band sending events to the phone unprompted on the data channel `fd4b0005` (connection up/down, condition reports), so events do arrive live.
- A characteristic notification wakes an app that has the Bluetooth background mode, which is how band replies already reach it.

What is unknown:

- Whether WHOOP 5.0 firmware 50.42.1.0 reports a double tap outside an alarm. No capture contains one.
- Whether the band can play distinguishable long and short pulses. Only effects `[47, 152]` are proven. The values look like a standard haptic-driver library (47 a buzz, 152 a 240 ms pause); that reading is an inference.
- Battery cost. The data channel also carries stored data whenever the WHOOP app syncs, so listening wakes this app more often.

Experiment 1, in `WhoopTap/` (`WhoopQuiet` plus `tap.patch`): a switch "Listen for double taps". When on, the app subscribes to `fd4b0005`, logs every band event by name, and buzzes back once on event 14. Checked on the Mac: the event parser passes 9 checks against frames from the owner's captures; Release build has no warnings. Installable file: `sidestore/WhoopBuzz-quiet-tap.ipa`, which also contains the burst fix. **Not run on the phone.**

Time code proposed for step 2 (12-hour, 5-minute steps): hours as long = 5 and short = 1, a pause, then minutes as long = 15 and short = 5. Example 4:35 is four short, pause, two long and one short. Worst case 9:55 is ten pulses.

### Tap test result, 16:09–16:11: the band reports double taps

With `WhoopBuzz-quiet-tap.ipa` installed and listening on (`device-logs/20261009-161124.plist`):

- The band sent `DOUBLE_TAP` (event 14) for the owner's taps, and the app buzzed back each time (result 1, detail 5). Four tap rounds at 16:09:31, 16:09:56, 16:10:41 and 16:11:12.
- Extra `DOUBLE_TAP` events arrive around a buzz: nine within two seconds in the first round, and two within a second of the reply in two later rounds. Most likely the band's own vibration is detected as taps; the owner may also have tapped more than once. Either way a cluster has to be treated as one tap.
- `HAPTICS_FIRED` and `HAPTICS_TERMINATED` for a buzz were delivered only at the start of the next round, 20 to 45 seconds later. They look batched, so they cannot be used to time anything live. That reading is an inference.
- Also seen: `BATTERY_LEVEL`, event 63 and `STRAP_CONDITION_REPORT` right after the first round, and event 110 `[01 01 …]` twice. Their meaning is not established.
- The phone was unlocked with the app open. Tap delivery to a backgrounded or locked app is untested.

### Step 2 build: `WhoopTime/` (built 16:15, copied to the phone, not yet run)

`WhoopTap` plus `time.patch`:

- A double tap plays the time (or one buzz, selectable). "Play the time now" does the same from the app.
- Taps are ignored while anything plays and for three seconds after any buzz, including notification buzzes, so the band's own vibration cannot retrigger it.
- Pulse lab: seven candidate pulses to try, and pickers for which one is "short" and which is "long". Only A (effects 47, 152) is proven; B to F try effect numbers 1, 10, 14, 15 and 16, and G is effect 47 three times. Defaults: short A, long G.
- Each group of pulses is packed into command-19 bodies of eight effect bytes, sent one after another, waiting for each final reply.

Checked on the Mac: 37 checks pass, covering the time code, the packing and that the generated frame for the proven pulse is byte-identical to the working buzz frame; Release build has no warnings. Unknown until run: whether the other effect numbers are accepted and how they feel, and whether back-to-back commands play cleanly.

### Owner's verdict on step 2, and the simpler time code (`WhoopBuzz-time2.ipa`, built 16:23)

Owner, after running `WhoopBuzz-time.ipa`: it works; pulses A (effect 47) and B (effect 1) feel right, C to G feel too long; the 5-and-1 time code was not understandable. The phone was unplugged afterwards, so the app log for that run was not read.

Chosen replacement (owner's pick from three options): two plain counts. Pulses for the hour on a 12-hour clock, a 1.2 s pause, then pulses for the tens of minutes. 4:35 is four, pause, three; nothing after the pause means minutes 0 to 9. Worst case 12:5x is seventeen pulses.

The owner then asked for something shorter than up to twelve pulses and suggested using pulses B, C and A. Added format "Threes" (now the default; plain counting stays selectable in the app): pulse C counts as three and is played first, then single pulses, in both groups. Hour ones use B, minute ones use A. 4:35 is C B, pause, C. 11:50 is C C C B B, pause, C A A. Worst case is eight pulses (11:5x) instead of seventeen.

`WhoopTime/` implements both formats with pulses A (effect 47), B (effect 1) and C (effect 10); installable file `sidestore/WhoopBuzz-time3.ipa` (built 16:27, replaces time2). 43 checks pass on the Mac; Release build has no warnings. **This version has not run on the phone.** How C feels against A and B, and whether the owner reads the format easily, is untested.

### What the first time-playback run actually did (log read 16:30)

`device-logs/20261009-163014.plist`, from `WhoopBuzz-time.ipa`:

- All seven lab pulses were accepted (result 1, detail 5), each within 0.1 to 0.6 s. So the band takes effect numbers 1, 10, 14, 15 and 16, and its success reply means "started", not "finished".
- Every time playback failed at the second command: the hour command was accepted, the minute command came back about a second later as **result 0, detail 7**. Three runs, same result (16:19:01, 16:19:22, 16:21:12). Detail 7 is the timeout the reference describes after the band's start attempts, so the motor was still running the hour pattern. The owner only ever felt the hours.

Fix in `WhoopTime/` (in `WhoopBuzz-time3.ipa` as rebuilt at 16:33, which replaced the earlier file of that name on the phone):

- A command refused with detail 7 is resent until the band starts it, up to eight times, so one pattern follows the other.
- The pause before the minutes is the first byte of the first minute command (248, read as 1.2 s), so the band times it. If the band refuses a command that starts with a pause, the app waits 1.2 s itself and sends the pulses alone.
- The app stays busy, and keeps ignoring taps, until the last pattern has had time to finish.
- A playback writes one summary line with the number of commands and resends.

53 checks pass on the Mac; Release build has no warnings. **Not run on the phone.** Unverified assumptions: bytes of 128 and above are pauses of (value − 128) × 10 ms; the band starts a waiting command promptly once the motor is free.

### Second playback run, and the single-tap trigger (`WhoopBuzz-time4.ipa`, built 16:49)

`device-logs/20261009-164653.plist`, from the fixed `WhoopBuzz-time3.ipa`:

- Time playback now completes. Ten runs between 16:39 and 16:45 each ended "Time played: 3 commands started", taking 5.3 to 9.0 s with 1 to 6 resends while the motor was busy. The owner used plain counting and says the format is workable.
- The owner reports the band's double-tap detection misses some taps, while the single tap that lights the battery indicator is dependable.
- Events seen beside the owner's taps: `BATTERY_LEVEL` (3) with event 63, at 16:40:02 and 16:44:54, once with `STRAP_CONDITION_REPORT` and event 110. Earlier the same day: 16:09:33 and 16:19:03. At 16:40:02 they came with no `DOUBLE_TAP`. Whether the band also sends them unprompted, and how often, is not known.
- `HAPTICS_FIRED`/`HAPTICS_TERMINATED` reports flooded the 120-line log.

Added in `WhoopTime/`:

- Trigger setting: single or double tap (default), double only, single only. A single tap is taken from events 3, 63 or 110.
- Runaway guard for the single-tap trigger: ignored for 10 s after any buzz, and at most three a minute.
- Haptic report events are no longer logged.

57 checks pass on the Mac; Release build has no warnings. **Not run on the phone.** Risks: a knock that lights the battery indicator will play the time, and so will any battery report the band sends for another reason.

### Research check and the simplified build (`WhoopBuzz-time5.ipa`, built 17:00)

The owner found the options too complicated and asked what others have done. Web search, 9 October:

- Apple Watch "Taptic Time" already does this in three modes: Terse (hours long = 5, short = 1, then a long tap per quarter hour), Digits (long = 10, short = 1 for hours and again for minutes) and Morse.
- Touch takes in about 3 to 4 pulses at a glance; counting longer runs gets unreliable. Temporal grouping lowers errors only when the grouping is known in advance (Plaisier, Holt and Kappers, 2020). None of these counting studies used the wrist.
- Rhythm is the easiest tactile property to tell apart and intensity the hardest; adding dimensions lowers recognition (Brown, Brewster and Purchase: 48% for three-parameter patterns, 81% when simplified; Lee and Starner's BuzzWear).
- "Telling Time by Vibration" (Töyssy, Raisamo and Raisamo, 2008): 80% correct untrained, 88% after short training, most errors in the minutes. Its exact pattern was not retrieved.

Decision (owner agreed): copy Apple's Terse on a 12-hour clock and strip the app back.

`WhoopTime/` now:

- Hours as long = 5 and short = 1, a 1.2 s pause, then one long per quarter hour passed. Long is effect 47 (the alert buzz), short is effect 1 (the tap). 7:40 is long short short, pause, long long. Worst case 9:45, eight pulses, three commands.
- No format picker, pulse pickers or pulse lab. What remains: listen switch, trigger (single or double, double only, single only), "Play the time now".
- Unchanged underneath: resending while the motor is busy, band-timed pause, tap ignoring and the single-tap runaway guard.

51 checks pass on the Mac, including every minute of the day fitting in at most three commands of at most eight bytes; Release build has no warnings. Supersedes time3 and time4, whose files were removed locally. **Not run on the phone.**

### Practice times and the battery study (`WhoopBuzz-time6.ipa`, built 17:08)

Added to `WhoopTime/` at the owner's request:

- "Practise a time": a time picker and a button that plays the chosen time.
- Battery study logging. Whenever a band event carries the battery level (`BATTERY_LEVEL`, or `STRAP_CONDITION_REPORT`, which arrives about every ten minutes unprompted), the app saves a line: time, band battery, pulses the band started, data-channel packets handled, CPU seconds this app has used, phone battery, charging, listening. Kept under `whoop.batteryLog`, up to 1,000 lines. The app shows the latest band reading.
- `battery-report.sh` (with `battery_report.py`) pulls those lines and reports drain per hour, projected days per charge, a least-squares split into resting drain and cost per pulse, and the app's CPU and packet rates. Tested on synthetic readings with known values (0.30 per hour, 0.0100 per pulse): it returned 0.32 and 0.0097.

58 checks pass on the Mac, including the battery value read from a condition report in the owner's own capture (52.8%); Release build has no warnings. Supersedes time5. **Not run on the phone.**

First estimate from data already in hand (band only; nothing has been measured on the phone):

| Period | Band battery | Rate |
|---|---|---|
| 8 Oct about 22:18 to 9 Oct 16:09, mostly normal wear | 52.8% to 47.7% over 17.9 h | 0.29 points per hour, about 14.6 days per charge |
| 9 Oct 16:09 to 16:44, heavy testing, about 92 pulses | 47.7% to 46.7% over 35 min | 1.7 points per hour |

Taking the first rate as the resting drain, the testing period lost about 0.8 points more than rest for about 92 pulses: roughly 0.01 points per pulse, with the three sub-periods giving 0.005 to 0.02. That is an upper bound, since tapping also lights the band's battery indicator and the band was sending more over Bluetooth. Assumptions: the battery value is in tenths of a percent, the band was not charged between the readings, and the first reading's time is the capture file's time.

On that figure a time check (4 to 5 pulses on average) costs about 0.04 points and an alert buzz about 0.01. A day with 100 alerts and 20 time checks would add about 2 points to the usual 7, taking a charge from about 14 days to about 11.

### Losing Bluetooth or the band (`WhoopBuzz-time7.ipa`, built 9 Oct 23:44)

Owner's question: does it keep working if Bluetooth drops or the band goes away? Read from the code as it stood in time6:

| Situation | Alerts | Tap for the time |
|---|---|---|
| Bluetooth off | Each alert fails with an automation error | Nothing |
| Bluetooth back on, or band back in range | The next alert reconnects and buzzes | **Stays dead until the next alert or a manual reconnect**: nothing reconnected the app |
| Band out of range | Each alert waits up to 15 s, then fails with an error | Nothing |
| iOS ends the app in the background | The next alert relaunches it | Dead until then |
| Band taken off but nearby | Still connected, still buzzes | Still works |

Changes in `WhoopTime/`:

- A standing connection request to the saved band, with no time limit, started at launch, when Bluetooth comes back on, after any disconnect and after a failed setup. Core Bluetooth completes it when the band is reachable.
- An alert that cannot be delivered (Bluetooth off, or the band not ready within 8 s) is logged and skipped without an automation error.
- A Core Bluetooth restore identifier, so iOS can relaunch the app for band events after ending it in the background. Bluetooth is now started on every launch, including ones with no screen.
- The Disconnect button stops the standing request until the owner reconnects or an alert arrives.

58 checks still pass and the Release build has no warnings, but none of this connection logic can be exercised on the Mac. **Not run on the phone.** Not handled: buzzing a band that is off the wrist. The app logs `WRIST_ON`/`WRIST_OFF` if the band sends them; none has been seen yet.

## Next: calls (WhatsApp and normal)

- iOS 27 Shortcuts has no call trigger. The phone-build trigger list, the iOS 27 strings and Apple's guide page contain none.
- A ringing call is shown by the call screen, not as a notification, so the Notification trigger is not expected to fire while it rings. Untested on this phone. A missed-call alert afterwards is an ordinary notification.
- CallKit's `CXCallObserver` reports ringing, answered and ended for calls on the phone, including other apps' calls, but only to an app that is running. It gives no caller or app name.

Prototype: `WhoopCalls/` — a copy of the main app as of 11:03 plus `Sources/CallBuzz.swift`, with the changes to existing files in `calls.patch` (applies cleanly to the main sources).

- Logs every call state change, and buzzes about every three seconds while a call rings, up to 10 times.
- Keeps the app running with a low-accuracy background location session (needs Location set to Always). No location is read or stored.
- Shortcuts requests that arrive during a buzz now return quietly instead of failing.
- Checked: signed device build succeeded, same bundle ID, background modes `bluetooth-central` and `location`; framing checks pass. **Not installed. Nothing about call detection or the keep-alive has run on the phone.**

First test before installing anything: with the current automation, have someone WhatsApp-call the phone and watch the app log for a request at ring time.

## Next: the 7-day signing limit

| Option | Cost | What it does | Status |
|---|---|---|---|
| Paid Apple Developer account | US$99 a year | Profiles last a year | Known to work; owner has ruled it out so far |
| SideStore | Free | Re-signs on the phone itself and resets the 7 days at each refresh | **Chosen and working on iOS 27.0, see above** |
| AltStore with AltServer on the Mac | Free | Mac refreshes the app over Wi-Fi when both are on the same network | Needs the Mac weekly |
| App Store app with a BLE write action (Bluetooth Inspector, "Write Value" with Hex) | US$3.99 once, if Pro is needed | No self-signed app at all for message buzzes | Unknown whether it writes with the phone locked, and whether the band accepts the buzz frame without the hello. Does not cover calls |
| Rebuild from the Mac each week | Free | What happens today | Works; manual |

The investigation below is kept as the record of how the cause was narrowed down.

## Investigation: Bluetooth switched off as the action ran

Phone log, pulled 11:10 (`device-logs/20261009-111029.plist`):

| Time | What the app logged |
|---|---|
| 10:56:42 | Band disconnected, then Bluetooth off one second later. No Shortcuts request was running |
| 10:58:54 | Shortcuts request; Bluetooth already off |
| 10:59:52 | Bluetooth ready again (3 min 9 s after it went off) |
| 11:00:23 | Shortcuts request with a ready session; Bluetooth off in the same second; no buzz reply |
| 11:05:31 | New app process starts and finds Bluetooth off; ready 8 s later |
| 11:08:37 | Shortcuts request with a ready session; Bluetooth "turned off" (`poweredOff`) in the same second; no buzz reply |
| 11:09:41 | Bluetooth ready again (64 s later) |

Established:

- This is the phone's Bluetooth adapter state, not an app fault. In both 11:00 and 11:08 runs the app had a ready session and had issued the buzz write when the state changed under it.
- The Bluetooth daemon did not crash: `bluetoothd` still had its boot-time process ID (101) at 11:13, and the phone has no Bluetooth crash report today.
- No Mac-side tool in use can switch phone Bluetooth (`devicectl` has no such setting). No PacketLogger trace was running during these runs.
- The iOS 27 CoreBluetooth headers add no per-app background permission that could explain a false "off".
- A third-party app has no API to power Bluetooth off.

Inference, not proven: Bluetooth stayed off for one to five minutes each time. An app with the Bluetooth background mode is woken for state changes, so those times should be real. A chip fault normally recovers in seconds; minutes points to Bluetooth being switched off and later switched back on. What switches it off at the moment the action starts is unknown.

Could not get: the phone's system log. `devicectl device sysdiagnose` stops at Apple's privacy notice and needs the owner's consent, so it was not run. The phone was unplugged from 11:17, so the live watcher below has not been tested.

Tools in `bluetooth-off/`:

- `live-watch.sh [minutes]` — with the phone on USB, prints every Bluetooth power change, lock and screen event the phone posts, beside new app-log lines. Tested 11:58–12:03.
- `watch-bluetooth-power.sh` — the same phone events without the app log. Not run.
- `pklg_power_events.py CAPTURE.pklg` — reads a PacketLogger trace and lists disconnects, controller resets and hardware errors. On `whoop-reconnect-01.pklg` it shows what a phone-commanded switch-off looks like: disconnect reason 0x16, then an HCI reset 21 ms later. A chip fault would show a hardware error instead.

### Live watch, 11:58–12:03 (`bluetooth-off/live-watch-*.log`)

`live-watch.sh` now works: it prints the phone's own Bluetooth power, lock and screen notifications beside new app-log lines.

| Time | Event |
|---|---|
| 11:59:30 | Shortcuts request (owner says it was started by a WhatsApp text) |
| 11:59:31 | System `com.apple.bluetooth.power-changed`; app sees `poweredOff` |
| 12:00:25 | Power changed again; owner confirms switching Bluetooth back on by hand |
| 12:02:27 | Shortcuts request; buzz confirmed (result 1, detail 5); Bluetooth stays on |
| 12:02:38 | Shortcuts request |
| 12:02:39 | System power-changed; Bluetooth off; no buzz |
| 12:02:49 | Shortcuts request; Bluetooth already off |
| 12:02:54 | Power changed again (on) |

What this adds:

- The switch-off is system-wide and follows the request by about one second. My earlier idea that it happened before the request and was delivered late is wrong.
- It persists until the owner turns Bluetooth on, and `bluetoothd` still has its boot-time process ID. So it is a commanded switch-off, not a crash or self-healing reset.
- The Notification trigger does fire for a real WhatsApp text (owner's account of the 11:59:30 run).
- In-app Test one buzz at 11:26:23 and the 12:02:27 request both buzzed with Bluetooth staying on, so the buzz write is not the cause.
- The three 12:02 requests are exactly 11 seconds apart. Which were by hand and which were WhatsApp-triggered is not yet known; the owner has been asked.

Leading explanation, unproven: a step that turns Bluetooth off runs when the WhatsApp-triggered automation fires (inside that automation or in a second one). The automation has not been seen.

Smallest tests that split the causes:

1. In WHOOP Buzz, in the foreground: connect, tap **Test one buzz**. If Bluetooth drops here too, the buzz write itself is involved. If it buzzes and Bluetooth stays on, the cause is on the Shortcuts side.
2. If Shortcuts side: check every automation on the phone for a Bluetooth, Airplane Mode or Focus action, and run a brand-new shortcut containing only Buzz WHOOP.
3. Capture one failing run with the watcher or a PacketLogger trace.

## First live Shortcuts run: buzz accepted, then the app locked itself

Pulled from the phone (`device-logs/20261009-105324.plist`, newest first):

```text
10:53:01  Stop was not confirmed (result 0). Reconnect.
10:53:00  Shortcuts test failed: WHOOP did not complete the vibration test. Reconnect in WHOOP Buzz.
10:53:00  Stop was not confirmed (result 0). Reconnect.
10:52:59  Band is processing stop…
10:52:57  Buzz reply: result 1, detail 5. Check whether you felt it.
10:52:57  Band is processing buzz…
10:52:57  Shortcuts requested one buzz.
```

- The Shortcuts action ran and the band gave its final success reply for the buzz (result 1, detail 5) within the same second. Whether this run was started by hand or by a notification is not recorded.
- The automatic stop sent two seconds later was refused twice (result 0). The likeliest reason is that the pattern had already finished; that reading is an inference.
- The app treats a refused stop as a fault and clears its ready state. So the action reported a failure for a buzz that succeeded, and **every later Shortcuts buzz will wait 20 seconds and fail until the band is reconnected by hand in the app.** The foreground Test button has the same flaw after its first buzz.

This blocks the bridge from working more than once. It is still present in `WhoopBuzz/Sources/WhoopBluetooth.swift` as of 10:56.

## Earlier fixed build: `WhoopBridge/` (superseded)

Codex installed its own stop fix at 11:05, so this copy is now behind the main app and should not be installed. It is kept for two things the main app still lacks: burst requests return quietly instead of failing, and a connected-but-not-ready session reconnects by itself.

A copy of the app as Codex had it at 10:47 (kept in `WhoopBridge/codex-snapshot/`) with these changes, also provided as `WhoopBridge/stop-fix.patch`:

1. No automatic stop after a buzz. The band's final buzz reply ends the operation.
2. A refused stop after a confirmed buzz is logged and no longer locks the app. A refused stop with no confirmed buzz still locks it, as before.
3. An unanswered buzz (10 seconds) triggers one stop request.
4. Shortcuts requests that arrive during a buzz, or within three seconds after one, return quietly instead of failing.
5. If the app is connected but not ready, the action reconnects by itself instead of timing out.
6. Timeouts and write failures always clear the busy state, so requests cannot be swallowed forever.

Checked: framing verification passes; signed device build succeeded (`WhoopBridge/build.log`) with the existing profile, same bundle ID `dev.yajat.WhoopBuzzResearch`, and the Buzz WHOOP action in background mode. **Not installed and not run against the band**, because the phone was in use for Codex's test. Installing it updates the app in place and keeps the saved band, Bluetooth permission and any existing automation:

```sh
xcrun devicectl device install app --device <DEVICE-UDID> \
  <project>/Claude-Experiments/WhoopBridge/Build/Build/Products/Debug-iphoneos/WhoopBuzz.app
```

## Evidence from the phone's OS build

`trigger-evidence/check-notification-trigger.sh` inspects WorkflowKit as Xcode copied it from this iPhone (build 24A437). Output is in `trigger-evidence/output.txt`.

| Observation | Meaning |
|---|---|
| `WFNotificationTrigger` class present, with `selectedBundleIdentifiers` | The trigger is in this exact build and filters by app bundle ID |
| Absent from the iOS 18.4 simulator runtime's WorkflowKit | New since iOS 18 |
| `+[WFNotificationTrigger isAllowedToRunAutomatically]` returns 1 (base class returns 0) | "Run Immediately" is permitted, so no confirmation tap |
| No `isSupportedOnThisDevice` override; base returns 1 | No per-device gate in this class, so not limited to Apple Intelligence phones |
| Flag name `new_system_automations` beside the trigger definition | Availability is flag-controlled; the iOS 27.0 simulator runtime marks it FeatureComplete. The phone's flag file is not readable from the Mac; the owner's "Notification is available" report covers this |
| Log strings for not firing: no app configured, bundle ID mismatch, missing or invalid value, failed Spotlight content hydration | These are the OS's own refusal reasons |

The iOS 27.0 simulator runtime (24A434) carries the matching user-facing text: "When I receive a notification from ${SelectedApps}" and "Only run when the notification title / subtitle / message contains this text."

Outside reports, not verified here: Derek Seaman (10 Aug 2026, updated 30 Aug) says the trigger runs with the device locked, that filters were broken before developer beta 5, and that a notification needs message text to match. MacStories (about 6 Oct 2026) reports roughly one second from notification to shortcut execution.

## Risks to check in the live test

1. **Use no filters first.** Pick the app only. Content filters depend on the "Spotlight content hydration" step, which is a separate way to fail. I could not confirm from the disassembly whether hydration also runs with no filter set.
2. **Hidden previews.** If previews are set to "When Unlocked" or "Never", whether the trigger still gets message text on a locked phone is unknown. Test locked with previews in the owner's normal setting.
3. **Bursts.** In the main app, `buzzFromShortcut()` throws when a buzz is already running, so three WhatsApp messages in two seconds give one buzz and two failed automation runs. Handled in `WhoopBridge/`.
4. **Calls.** WhatsApp calls ring through CallKit, not as a normal banner. Whether the Notification trigger fires for an incoming call is unknown; a missed-call alert afterwards probably does.
5. **Focus and muted chats.** Unknown whether the trigger fires for alerts that Focus silences. If it does, the band buzzes for alerts the phone suppressed.
6. **Profile expiry.** The free-team profile ends 15 October 2026 23:23 UTC. After that the action stops working until the app is rebuilt and reinstalled from the Mac. A free account cannot avoid the 7-day cycle.

## Proving a run from the Mac

```sh
./pull-buzz-log.sh
```

Copies the app's saved log from the phone over USB and marks Shortcuts-started lines. A real WhatsApp-triggered buzz shows `Shortcuts requested one buzz.` followed by a `Shortcuts buzz … confirmed` line at the message's arrival time. Copies are kept in `device-logs/`. The log shows that the action ran; it cannot show which notification caused it, so compare the timestamp with the message time.

## Other routes assessed

| Route | Status |
|---|---|
| Shortcuts Notification trigger + App Intent | Viable; live test pending |
| Accessory Notifications | Blocked by free-team signing. New reading of the SDK 27 interface: the data-provider extension's `addNotification(_:alertingContext:)` receives title, body and source in plain form on the phone. Encryption applies to what the extension sends onward. So WHOOP firmware would not need to speak HPKE; signing is the real gate. Untested at runtime; the other two entitlements were not signing-tested |
| ANCS | Needs the band's firmware to act as the ANCS client. No switch in Settings, none seen in captures. Not re-verified here |
| Ordinary notification APIs, notification service extension | Own-app notifications only |
| Packet-tunnel traffic watching, Screen Time, CallKit observer, microphone or motion side channels | Need a paid capability, or are non-specific and unreliable. Not pursued once the Shortcuts trigger was found |
