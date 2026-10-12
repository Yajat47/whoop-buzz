# WHOOP 5.0 connection study

Study equipment: the owner's WHOOP 5.0, iPhone reported as running iOS 27,
and Mac with Xcode 27. Apple Bluetooth logging is now installed on the
iPhone. PacketLogger successfully captured the phone's Bluetooth traffic.

## What the first capture shows

Original evidence: `whoop-baseline-01.pklg`. Preserve this file. Its SHA-256
and the exact reference-source revision are recorded in
`whoop-baseline-01.decoded.json`. Individual frames, bytes, checks, and
record locations are in `whoop-baseline-01.frames.jsonl`.

The capture contains 1,922 PacketLogger records. Of these, 567 are complete
WHOOP 5 protocol frames. Every one passes its declared-length check, header
CRC16, and payload CRC32. The observed WHOOP frame window spans about
65 seconds. The capture's opening controller notes have older timestamps;
they should not be used to measure the experiment's duration.

| Message label from the public decoder | Frames |
|---|---:|
| Phone command | 14 |
| Band command reply | 16 |
| Stored historical data | 339 |
| Live data | 42 |
| Transfer metadata | 18 |
| Firmware console text | 134 |
| Band event | 4 |

These labels are interpretations from the public Goose code. Their frame
structure matches this band, but sensor meanings still need checking
against controlled actions and the official app.

The observed command sequence includes two range queries (code 34), two
stored-data transfer requests (22), eight transfer-result messages (23),
and two live-heart-rate toggles (3). Every request has a later vendor reply
with the same command and echoed request sequence. Two range queries each
receive two replies. There are also 14 separate Bluetooth write responses:
transport acknowledgement and vendor command reply are different messages.

Observed attribute handles in this band:

| Handle | Observed use |
|---|---|
| `0x099b` | Phone command writes |
| `0x099d` | Band command replies |
| `0x09a0` | One band event |
| `0x09a3` | Stored data, live data, metadata, logs, and events |

These are local attribute addresses, not universal UUIDs. Service discovery
was not recorded, so the handle-to-UUID map remains unproven.

All 339 stored-data frames use variant 18. The public decoder's record
counter field runs from 99,424 through 99,762 without gaps or duplicates.
This supports an ordered transfer of stored records. It does not establish
the rate of raw optical or movement measurements.

## Questions we will test next

1. What happens during reconnection and how does stored-data transfer resume?
2. Which live bytes match the heart rate shown in the official app?
3. Does band-to-phone transfer continue when internet access is removed?
4. Which displayed results need the cloud, and which are merely cached?

## Experiment 1: reconnect and catch up

Start a fresh iPhone trace in PacketLogger with the iPhone still connected
to the Mac by USB. Open WHOOP and wait for the band to show connected.
Record 30 seconds, switch Bluetooth off in iPhone Settings for 30 seconds,
then switch it back on. Return to WHOOP and record until syncing finishes,
plus another 30 seconds. Stop and save as `whoop-reconnect-01.pklg`.

Write down the times of Bluetooth off, Bluetooth on, band connected, and
sync completed. Keep internet access and band wearing position constant.
Repeat the same experiment twice more as separate captures.

Compare command order, disconnection and connection events, stored-record
counters, duplicate records, transfer-result cursors, and time until live
data returns. Existing Bluetooth pairing stays part of the setup; this
experiment observes reconnection rather than first-time pairing.

## Experiment 2: live heart-rate meaning

Use a WHOOP screen showing live heart rate. Sit still and record its value
with the time every 10 seconds for one minute. Continue recording during a
brief normal walk and after sitting again. Compare app values against
candidate fields in type-40 messages. Repeat to distinguish heart rate
from counters, flags, and unrelated measurements. Treat byte meanings as
candidates until they follow the displayed values repeatedly.

## Experiment 3: internet dependency

Keep Bluetooth enabled and the band connected. Record an online baseline.
Turn off Wi-Fi and mobile data on the iPhone for two minutes while leaving
WHOOP open. Restore internet access and record the recovery.

Check whether Bluetooth writes and incoming data continue, whether fresh
app values update, and which requests resume when internet returns. An
unchanged number may be cached. A feature failing offline does not by
itself prove its calculation runs on a server: authentication or app
scheduling can also require internet access.

## Clock alignment is an open issue

Device timestamps interpreted using the reference layout are about ten
hours behind the PacketLogger timestamps, even for recent data. This may
be a clock or timestamp-interpretation issue. It is not yet diagnosed.
Compare record order and relative intervals first. Record a simultaneous
known event before aligning device data with the app or cloud timestamps.

## Reuse the offline decoder

Run from this folder:

```sh
python3 decode_capture.py whoop-reconnect-01.pklg
```

It produces a `.decoded.json` summary and `.frames.jsonl` containing raw
frames and checks. It only reads saved files. It has no Bluetooth control
or command-sending code. Unsupported fragments are counted explicitly;
this first capture needed no fragment reassembly. It does not decode
health scores. The latest decoder labels the observed live HR field as a
candidate; its values still need repeated timed comparison with the app.

## References

- [Goose protocol source](https://github.com/b-nnett/goose/blob/ba9ae0280c9b5b9a1545baab8e944cb3b7563c62/Rust/core/src/protocol.rs)
- [Goose command definitions](https://github.com/b-nnett/goose/blob/ba9ae0280c9b5b9a1545baab8e944cb3b7563c62/Rust/core/src/commands.rs)
- [Wireshark PacketLogger reader](https://github.com/wireshark/wireshark/blob/master/wiretap/packetlogger.c)
- [Apple Bluetooth capture walkthrough](https://developer.apple.com/videos/play/wwdc2019/901/)

Reference snapshots are stored in `references/`; `sources.json` records
their URLs, revision, and hashes. Raw capture evidence takes precedence
when a public interpretation and this band's behavior disagree.

## Completed reconnect experiment

The first reconnect recording is now decoded. See
[reconnect-findings.md](reconnect-findings.md) for its measured timeline,
confirmed characteristic UUIDs, and stored-record continuity. The next
experiment is live heart-rate matching. The decoder now also extracts
WHOOP service discovery, connection/encryption events, and ATT MTU exchange.

## First live heart-rate capture

The live recording contains 91 valid type-40 frames over about 90 seconds.
The reference HR field stays in a plausible resting range and includes the owner's
untimed app observation five times. This is consistent evidence,
not a sample-by-sample validation. See [live-hr-findings.md](live-hr-findings.md),
the extracted values in `whoop-live-hr-01.hr.json`, and the chart in
`whoop-live-hr-01.chart.png`. Record app values with times in the next repeat.
