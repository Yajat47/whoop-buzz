#!/usr/bin/env python3
"""Inspect a saved Apple PacketLogger capture. Never connects to a device.

Reference snapshots and their hashes are in references/sources.json.
This intentionally decodes complete WHOOP 5 frames carried in complete ATT
messages only. Unsupported fragments are counted, not guessed or discarded
silently. Message names are community interpretations, not vendor guarantees.
"""

import argparse
import collections
import datetime
import hashlib
import json
from pathlib import Path
import struct
import uuid
import zlib


TYPES = {
    35: "COMMAND", 36: "COMMAND_RESPONSE", 37: "PUFFIN_COMMAND",
    38: "PUFFIN_COMMAND_RESPONSE", 40: "REALTIME_DATA",
    43: "REALTIME_RAW_DATA", 47: "HISTORICAL_DATA", 48: "EVENT",
    49: "METADATA", 50: "CONSOLE_LOGS", 51: "REALTIME_IMU_DATA_STREAM",
    52: "HISTORICAL_IMU_DATA_STREAM", 53: "RELATIVE_PUFFIN_EVENTS",
    54: "PUFFIN_EVENTS_FROM_STRAP", 55: "RELATIVE_BATTERY_PACK_CONSOLE_LOGS",
    56: "PUFFIN_METADATA",
}
COMMANDS = {
    3: "TOGGLE_REALTIME_HR", 22: "SEND_HISTORICAL_DATA",
    23: "HISTORICAL_DATA_RESULT", 34: "GET_DATA_RANGE",
    117: "START_FEATURE_FLAG_KEY_EXCHANGE", 118: "SEND_NEXT_FEATURE_FLAG",
    120: "SET_FEATURE_FLAG_VALUE", 141: "GET_ADVERTISING_NAME",
    145: "GET_HELLO",
}


def bluetooth_uuid(data):
    if len(data) == 2:
        return f"0000{int.from_bytes(data, 'little'):04x}-0000-1000-8000-00805f9b34fb"
    if len(data) == 16:
        # Bluetooth's 128-bit UUID is little-endian as a whole, unlike the
        # mixed-endian GUID representation used by uuid.UUID(bytes_le=...).
        return str(uuid.UUID(bytes=data[::-1]))
    raise ValueError("Unsupported Bluetooth UUID width")


def transport_details(data):
    events, characteristics, mtu_exchanges = [], [], []
    pending_types, pending_mtu = {}, {}
    for index, offset, seconds, kind, body in read_records(data):
        common = {"record_index": index, "capture_time_utc": utc(seconds)}
        if kind == 1 and len(body) >= 6:
            if body[0] == 0x3e and body[2] in (1, 0x0a, 0x29):
                events.append({**common, "event": "connection_complete", "status": body[3], "connection_handle": f"0x{struct.unpack_from('<H', body, 4)[0]:04x}"})
            elif body[0] in (5, 8):
                events.append({**common, "event": "disconnection_complete" if body[0] == 5 else "encryption_change", "status": body[2], "connection_handle": f"0x{struct.unpack_from('<H', body, 3)[0]:04x}", "reason" if body[0] == 5 else "encryption_enabled": body[5]})
        if kind not in (2, 3) or len(body) < 9:
            continue
        flags, acl_length, l2_length, cid = struct.unpack_from("<HHHH", body)
        if acl_length != len(body) - 4 or l2_length != len(body) - 8 or cid != 4 or ((flags >> 12) & 3) == 1:
            continue
        handle = f"0x{flags & 0xfff:04x}"
        att = body[8:]
        if att[0] == 8 and len(att) in (7, 21):
            pending_types[(handle, kind)] = bluetooth_uuid(att[5:])
        elif att[0] == 9 and len(att) >= 2:
            request_type = pending_types.pop((handle, 5 - kind), None)
            width = att[1]
            if request_type != "00002803-0000-1000-8000-00805f9b34fb" or width not in (7, 21) or (len(att) - 2) % width:
                continue
            for pos in range(2, len(att), width):
                declaration, properties, value_handle = struct.unpack_from("<HBH", att, pos)
                identifier = bluetooth_uuid(att[pos + 5:pos + width])
                if identifier.startswith("fd4b"):
                    characteristics.append({**common, "connection_handle": handle, "declaration_handle": f"0x{declaration:04x}", "attribute_handle": f"0x{value_handle:04x}", "uuid": identifier, "properties": properties})
        elif att[0] in (2, 3) and len(att) == 3:
            offered = struct.unpack_from("<H", att, 1)[0]
            if att[0] == 2:
                pending_mtu[(handle, kind)] = offered
            else:
                requested = pending_mtu.pop((handle, 5 - kind), None)
                if requested is not None:
                    mtu_exchanges.append({**common, "connection_handle": handle, "requested": requested, "response": offered, "negotiated": min(requested, offered)})
    return events, characteristics, mtu_exchanges


def utc(seconds):
    return datetime.datetime.fromtimestamp(
        seconds, datetime.timezone.utc
    ).isoformat(timespec="microseconds")


def crc16_modbus(data):
    value = 0xffff
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = (value >> 1) ^ (0xa001 if value & 1 else 0)
    return value


def read_records(data):
    """Read the little-endian format emitted by this Mac's PacketLogger."""
    offset = 0
    index = 0
    while offset < len(data):
        if len(data) - offset < 13:
            raise ValueError(f"Truncated PacketLogger header at byte {offset}")
        length, seconds, micros = struct.unpack_from("<III", data, offset)
        end = offset + 4 + length
        if not 9 <= length < 65536 or end > len(data) or micros >= 1000000:
            raise ValueError(f"Invalid PacketLogger record at byte {offset}")
        index += 1
        yield index, offset, seconds + micros / 1e6, data[offset + 12], data[offset + 13:end]
        offset = end


def inspect(path):
    data = path.read_bytes()
    connection_events, characteristics, mtu_exchanges = transport_details(data)
    uuid_map = {(c["connection_handle"], c["attribute_handle"]): c["uuid"] for c in characteristics}
    counters = collections.Counter()
    records = collections.Counter()
    frames = []
    for index, offset, seconds, kind, body in read_records(data):
        records[f"0x{kind:02x}"] += 1
        if kind not in (2, 3):
            continue
        counters["acl_records"] += 1
        if len(body) < 4:
            counters["malformed_acl"] += 1
            continue
        flags, acl_length = struct.unpack_from("<HH", body)
        if acl_length != len(body) - 4:
            counters["malformed_acl"] += 1
            continue
        if ((flags >> 12) & 3) == 1:
            counters["unsupported_acl_continuations"] += 1
            continue
        if len(body) < 8:
            counters["malformed_l2cap"] += 1
            continue
        l2_length, cid = struct.unpack_from("<HH", body, 4)
        if l2_length != len(body) - 8:
            counters["unsupported_l2cap_fragments"] += 1
            continue
        if cid != 4 or len(body) < 9:
            counters["non_att_acl"] += 1
            continue
        att = body[8:]
        if att[0] == 0x13:
            counters["att_write_responses"] += 1
            continue
        if att[0] not in (0x12, 0x52, 0x1b, 0x1d) or len(att) < 3:
            counters["other_att_operations"] += 1
            continue
        attribute = struct.unpack_from("<H", att, 1)[0]
        frame = att[3:]
        if not frame.startswith(b"\xaa\x01"):
            counters["non_whoop5_att_values"] += 1
            continue
        if len(frame) < 15:
            counters["short_whoop5_values"] += 1
            continue
        declared = struct.unpack_from("<H", frame, 2)[0]
        valid_length = len(frame) == declared + 8
        valid_header = crc16_modbus(frame[:6]) == struct.unpack_from("<H", frame, 6)[0]
        valid_payload = zlib.crc32(frame[8:-4]) == struct.unpack_from("<I", frame, len(frame) - 4)[0]
        entry = {
            "record_index": index, "file_offset": offset,
            "capture_time_utc": utc(seconds),
            "direction": "phone_to_peer" if kind == 2 else "peer_to_phone",
            "connection_handle": f"0x{flags & 0xfff:04x}",
            "attribute_handle": f"0x{attribute:04x}",
            "att_opcode": f"0x{att[0]:02x}", "frame_bytes": len(frame),
            "checks": {"length": valid_length, "header_crc16": valid_header, "payload_crc32": valid_payload},
            "raw_frame_hex": frame.hex(),
        }
        entry["characteristic_uuid"] = uuid_map.get((entry["connection_handle"], entry["attribute_handle"]))
        if not all(entry["checks"].values()):
            counters["invalid_whoop5_frames"] += 1
            frames.append(entry)
            continue
        counters["valid_whoop5_frames"] += 1
        inner = frame[8:-4]
        packet_type = inner[0]
        entry.update({"type": packet_type, "reference_type_name": TYPES.get(packet_type, "UNKNOWN"), "inner_hex": inner.hex()})
        if packet_type in (35, 37):
            entry.update({"sequence": inner[1], "command": inner[2], "reference_command_name": COMMANDS.get(inner[2], "UNKNOWN"), "command_data_hex": inner[3:].hex()})
        elif packet_type in (36, 38) and len(inner) >= 5:
            entry.update({"sequence": inner[1], "command": inner[2], "reference_command_name": COMMANDS.get(inner[2], "UNKNOWN"), "origin_sequence": inner[3], "result_code": inner[4], "response_data_hex": inner[5:].hex()})
        elif packet_type == 47 and len(inner) >= 13:
            entry.update({"reference_variant": inner[1], "reference_record_counter": struct.unpack_from("<I", inner, 3)[0], "reference_device_time_utc": utc(struct.unpack_from("<I", inner, 7)[0])})
        elif packet_type == 40 and len(frame) == 32 and inner[1] == 2:
            # Restrict semantic decoding to the shape present in our capture.
            # Byte 9's meaning is not established; retain its raw value.
            # NOOP documents absolute frame offset 16 as HR for WHOOP 5/MG.
            # An untimed app reading supports this candidate but cannot prove
            # sample-by-sample agreement. Do not treat trailing zeros as beats.
            entry.update({
                "raw_byte_9": inner[1],
                "reference_device_seconds": struct.unpack_from("<I", frame, 10)[0],
                "reference_additional_time_raw": struct.unpack_from("<H", frame, 14)[0],
                "reference_heart_rate_bpm": frame[16],
                "reference_rr_count": frame[17],
                "live_hr_validation": "Candidate field; repeated timed app comparison still needed.",
            })
        frames.append(entry)

    valid = [f for f in frames if all(f["checks"].values())]
    replies = [f for f in valid if "origin_sequence" in f]
    requests = [f for f in valid if f.get("type") in (35, 37) and f["direction"] == "phone_to_peer"]
    for request in requests:
        # Restrict to later replies on the same Bluetooth connection. Short
        # sequence values can repeat in longer captures, so retain all matches.
        request["matching_response_record_indices"] = [
            reply["record_index"] for reply in replies
            if reply["record_index"] > request["record_index"]
            and reply["connection_handle"] == request["connection_handle"]
            and reply["command"] == request["command"]
            and reply["origin_sequence"] == request["sequence"]
        ]
    channel_counts = collections.defaultdict(collections.Counter)
    for frame in valid:
        channel_counts[frame["attribute_handle"]][frame["reference_type_name"]] += 1
    reference_file = path.parent / "references" / "sources.json"
    whoop_connections = {f["connection_handle"] for f in valid}
    summary = {
        "capture": str(path.resolve()), "capture_sha256": hashlib.sha256(data).hexdigest(),
        "record_count": sum(records.values()), "packetlogger_type_counts": dict(records),
        "counters": dict(counters),
        "whoop_frame_window_utc": {"first": valid[0]["capture_time_utc"] if valid else None, "last": valid[-1]["capture_time_utc"] if valid else None},
        "message_type_counts": dict(collections.Counter(f["reference_type_name"] for f in valid)),
        "observed_channels": {k: dict(v) for k, v in channel_counts.items()},
        "command_counts": dict(collections.Counter(f["reference_command_name"] for f in requests)),
        "commands_without_response": [f["record_index"] for f in requests if not f["matching_response_record_indices"]],
        "whoop_connection_events": [e for e in connection_events if e["connection_handle"] in whoop_connections],
        "observed_whoop_characteristics": characteristics,
        "whoop_mtu_exchanges": [e for e in mtu_exchanges if e["connection_handle"] in whoop_connections],
        "reference_manifest": json.loads(reference_file.read_text()) if reference_file.exists() else None,
        "limits": ["No Bluetooth connection, writes, or command replay.", "Complete WHOOP 5 frames only; unsupported fragments are counted.", "UUID mappings apply to the connection where discovery was captured.", "Community names and record timestamps need experimental validation.", "Live HR is a candidate decoded only for the observed 32-byte type-40 shape with raw byte 9 equal to 2; timed app comparison is still needed.", "R-R intervals and proprietary health scores are not decoded."],
    }
    return frames, summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    args = parser.parse_args()
    frames, summary = inspect(args.capture)
    args.capture.with_suffix(".frames.jsonl").write_text("".join(json.dumps(f) + "\n" for f in frames))
    target = args.capture.with_suffix(".decoded.json")
    target.write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({"summary": str(target), "record_count": summary["record_count"], "counters": summary["counters"], "message_type_counts": summary["message_type_counts"], "command_counts": summary["command_counts"], "commands_without_response": summary["commands_without_response"]}, indent=2))


if __name__ == "__main__":
    main()
