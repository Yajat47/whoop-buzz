# WHOOP 5.0: first reconnect experiment

Evidence: `whoop-reconnect-01.pklg`, with 3,674 PacketLogger records and
968 complete WHOOP protocol frames. All 968 frames pass length, header
CRC16, and payload CRC32 checks. Raw evidence and offsets are preserved in
`whoop-reconnect-01.frames.jsonl`. The summary and capture hash are in
`whoop-reconnect-01.decoded.json`; comparison measurements are in
`reconnect-comparison.json`.

## What changed

| Message type | Baseline | Reconnect capture |
|---|---:|---:|
| Phone commands | 14 | 144 |
| Band replies | 16 | 150 |
| Stored records | 339 | 441 |
| Live data | 42 | 0 |
| Transfer metadata | 18 | 22 |
| Firmware logs | 134 | 206 |
| Band events | 4 | 5 |

The reconnect capture includes an existing WHOOP connection with handle
`0x004a`, then a newly established WHOOP connection with handle `0x0040`.
Traffic from other Bluetooth connections is also present in the file;
the WHOOP findings below use the connection carrying validated WHOOP
frames and its matching service discovery.

## Reconnect sequence observed

Times are relative to the successful new WHOOP Bluetooth connection.
Absolute clock alignment with the band is still unverified.

| Time after connection | Observation |
|---|---|
| 0.000 s | Bluetooth connection completes successfully |
| 0.273 s | Link encryption becomes enabled |
| 0.365 s | ATT MTU negotiation completes at 247 bytes |
| 0.875 s | Five vendor characteristics are discovered |
| 1.502 s | First identity/hello command is written |
| 2.015 s | App requests the stored-record range |
| 3.366 s | App requests historical transfer |
| 3.558 s | First stored record arrives |
| 5.060 s | Last stored record in this catch-up arrives |

The app also exchanges named configuration settings. Their interpretation
uses the public Goose command table: codes 117 and 118 enumerate settings,
and code 120 writes their values. This capture has 60 code-118 requests and
60 code-120 writes. Twenty distinct setting names appear in those writes,
each three times.
Examples include `enable_r22_packets`, `make_hrfm_visible`, and
`wear_detect_bias`. The names alone do not establish their behavior or how
the app chooses their values.

## Device data channels are now mapped

The following UUIDs come from actual characteristic discovery in the
new WHOOP connection. All share suffix
`-cce1-4033-93ce-002d5875f58a`.

| Attribute handle | UUID prefix | Observed use |
|---|---|---|
| `0x099b` | `fd4b0002` | Phone command writes |
| `0x099d` | `fd4b0003` | Band command replies |
| `0x09a0` | `fd4b0004` | No WHOOP frame observed here in this recording; one event in the baseline |
| `0x09a3` | `fd4b0005` | Stored records, metadata, logs, and events |
| `0x09a6` | `fd4b0007` | Notify-capable channel; its purpose remains open |

The command characteristic advertises both write modes. The other four
characteristics advertise notification support. These are actual device
declarations, separate from the community's packet labels.

## Stored-record continuity

The capture transfers 299 records before the new connection and 142 after
it. The decoded record counter runs from 101,565 through 102,005. All 441
counters are unique and every adjacent step is exactly one. The first
post-reconnect counter is 101,864, directly after the earlier transfer's
101,863. This supports successful continuation of this record stream
across reconnection. It does not prove completeness of every sensor
stream or behavior during longer outages.

The 142 post-reconnect records arrive over approximately 1.502 seconds.
They are a burst of stored records, rather than observations collected
only as each message is delivered.

Every decoded WHOOP command has at least one later vendor reply matching
its code and request sequence. PacketLogger also records separate ATT
write responses. These transport responses and vendor replies remain
distinct layers.

## What this experiment does not establish

- A WHOOP-specific HCI disconnect event was not recorded. An unrelated
  connection's disconnect was excluded from the WHOOP timeline.
- This is a reconnection to an already paired device, not first-time pairing.
- No command-3 live-stream enable request or type-40 live-data frame appears.
- Bluetooth capture does not show phone-to-server requests, server processing,
  or proprietary Recovery, Strain, or Sleep calculations.
- The earlier device/capture clock difference still needs investigation.

## Next experiment: match live data to the app

Start a new iPhone trace. Open a WHOOP screen that displays live heart rate.
Record for one minute at rest, noting the displayed BPM and time every
ten seconds. Continue during a short normal walk, then record another
minute seated. Save as `whoop-live-hr-01.pklg` and keep the BPM notes.

First check whether opening that screen produces a command-3 enable write
and type-40 data. Then compare candidate byte values with repeated app
readings and their changes. This is necessary before labelling any byte
as a measured heart rate.

## Reference and method

Public command and frame interpretations use the pinned
[Goose source revision](https://github.com/b-nnett/goose/tree/ba9ae0280c9b5b9a1545baab8e944cb3b7563c62).
Reference files and hashes are recorded in `references/sources.json`.
Connection events and ATT service discovery use standard Bluetooth field
layouts, independently checked against the
[Wireshark dissectors](https://github.com/wireshark/wireshark/tree/master/epan/dissectors).
No new commands were sent to the band by the decoder; the captured commands
were sent by the official WHOOP app.
