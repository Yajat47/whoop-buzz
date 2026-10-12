#!/usr/bin/env python3
"""List Bluetooth power, reset and disconnect events in a saved PacketLogger
capture, plus any text log lines the phone's Bluetooth stack wrote into it.
Reads a file only. Usage: python3 -I pklg_power_events.py CAPTURE.pklg [--text PATTERN]
"""
import collections
import datetime
import re
import struct
import sys

REASONS = {0x08: "connection timeout", 0x13: "remote user ended", 0x15: "remote powering off",
           0x16: "ended by this phone", 0x22: "LL response timeout", 0x3e: "failed to establish"}


def records(data):
    offset = 0
    while offset + 13 <= len(data):
        length, seconds, micros = struct.unpack_from("<III", data, offset)
        end = offset + 4 + length
        if not 9 <= length < 65536 or end > len(data):
            break
        yield seconds + micros / 1e6, data[offset + 12], data[offset + 13:end]
        offset = end


def stamp(seconds):
    return datetime.datetime.fromtimestamp(seconds).strftime("%H:%M:%S.%f")[:-3]


def main():
    path = sys.argv[1]
    pattern = re.compile(sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == "--text"
                         else r"power|reset|airplane|disabl|turn(ed|ing)? off|state chang", re.I)
    kinds = collections.Counter()
    for seconds, kind, body in records(open(path, "rb").read()):
        kinds[kind] += 1
        if kind == 0 and len(body) >= 3:                      # HCI command
            opcode = struct.unpack_from("<H", body)[0]
            if opcode == 0x0c03:
                print(stamp(seconds), "HCI Reset sent to controller")
        elif kind == 1 and len(body) >= 2:                    # HCI event
            if body[0] == 0x05 and len(body) >= 6:
                handle, reason = struct.unpack_from("<H", body, 3)[0], body[5]
                print(stamp(seconds), f"disconnect handle 0x{handle:04x} reason 0x{reason:02x}"
                      f" ({REASONS.get(reason, 'other')})")
            elif body[0] == 0x10:
                print(stamp(seconds), f"HARDWARE ERROR event code 0x{body[2]:02x}")
        elif kind not in (2, 3):                              # text or vendor records
            text = body.decode("utf-8", "replace").replace("\x00", " ").strip()
            if pattern.search(text):
                print(stamp(seconds), f"[type 0x{kind:02x}]", text[:300])
    print("record types:", {f"0x{k:02x}": v for k, v in sorted(kinds.items())})


if __name__ == "__main__":
    main()
