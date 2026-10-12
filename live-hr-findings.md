# Live heart-rate capture: first findings

Evidence: `whoop-live-hr-01.pklg`, SHA-256 `17b536cabe583def57f4c1008ece2103c23a132deb2f64f0a50dabc49aa3e587`.
The original capture is unchanged. Raw frames are in `whoop-live-hr-01.frames.jsonl`,
and extracted candidate values are in `whoop-live-hr-01.hr.json`.

## What this recording shows

- 305 complete WHOOP frames; all pass length, header CRC16 and payload CRC32 checks.
- 91 incoming type-40 frames over 90.001 seconds.
- Median spacing: 1.004 seconds, approximately one update per second.
- Three command-3 writes carry `01`. The first live frame arrives 0.860 seconds after the first such write.
- All live frames are 32 bytes, with raw byte 9 equal to 2. Its meaning remains unassigned.
- The candidate HR field stays in a plausible resting range throughout. The values are left out of this public copy.
- The owner reports one app reading without a time or experiment phase.
  The candidate field equals that reading in five packets.
  This is consistent with the app reading, but is not a timed validation.
- The reference R-R count is zero in every live frame. This capture provides no R-R samples.

## Field interpretation

[NOOP's published WHOOP 5/MG sensor reference](https://github.com/ryanbr/noop/blob/8e94d559be273ec8d74832fe5db78898be83cc11/docs/PROTOCOL_SENSORS.md#packet-40-live-hr-and-r-r)
places live HR at byte 16, a little-endian seconds field at 10,
an additional time field at 14, and the interval count at 17.
Offsets start at zero in the complete WHOOP frame, after removing Bluetooth wrappers.
This is a community interpretation with firmware limits; our band firmware
and repeated timed app agreement have not yet been established.

The offline decoder applies the candidate fields only to this observed 32-byte
shape. It keeps the raw bytes and makes no guess for other live shapes.
The additional time field remains raw. Device seconds are not used to place
points on the chart because clock alignment is still unresolved.

## What this adds to the architecture study

The phone sends a live-output request; the band then supplies a compact
numeric stream about once per second through the same incoming attribute
that carries history and logs. This shows that a candidate HR value is
already present in the band-to-phone message. The capture does not reveal
the optical algorithm or the app/cloud health-score calculations.

## Next check

Repeat a 60-second live capture while seated. Record the app BPM every
10 seconds and each observation's time. Keep the live-HR screen open.
Compare those readings against byte 16, allowing for display delay.
Repeated time-aligned agreement would strengthen the field mapping.
Then run the internet-off experiment in `research-plan.md`.
