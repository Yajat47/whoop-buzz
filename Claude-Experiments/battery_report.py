#!/usr/bin/env python3
"""Battery study report for the buzz app. Reads a saved copy of the app's
preferences and works out the band's drain and the app's own work.
Reads a file only. Usage: python3 -I battery_report.py FILE.plist
"""
import datetime
import plistlib
import sys


def load(path):
    with open(path, "rb") as handle:
        lines = plistlib.load(handle).get("whoop.batteryLog", [])
    rows = []
    for line in lines:
        f = line.split(",")
        if len(f) < 8:
            continue
        rows.append({
            "t": datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).astimezone(),
            "band": int(f[1]) / 10, "pulses": int(f[2]), "packets": int(f[3]), "cpu": float(f[4]),
            "phone": int(f[5]) if f[5] else None, "charging": f[6] == "1", "listening": f[7] == "1",
        })
    return rows


def split_drain(rows):
    """Least-squares split of band drain into points per hour and per pulse."""
    gaps = [((b["t"] - a["t"]).total_seconds() / 3600, b["pulses"] - a["pulses"], a["band"] - b["band"])
            for a, b in zip(rows, rows[1:]) if b["band"] <= a["band"]]
    shh = sum(h * h for h, p, d in gaps)
    spp = sum(p * p for h, p, d in gaps)
    shp = sum(h * p for h, p, d in gaps)
    shd = sum(h * d for h, p, d in gaps)
    spd = sum(p * d for h, p, d in gaps)
    det = shh * spp - shp * shp
    if len(gaps) < 6 or det <= 1e-9:
        return None
    return (shd * spp - spd * shp) / det, (spd * shh - shd * shp) / det


def main():
    rows = load(sys.argv[1])
    if len(rows) < 2:
        print(f"{len(rows)} battery reading(s) saved so far; at least two are needed.")
        print("Turn on Listen for taps and leave the band connected for twenty minutes or more.")
        return

    print("time    band %   pulses  packets  app CPU s  phone %  listening")
    shown = rows if len(rows) <= 30 else rows[:5] + [None] + rows[-20:]
    for r in shown:
        if r is None:
            print(f"  ... {len(rows) - 25} more ...")
            continue
        phone = "" if r["phone"] is None else str(r["phone"]) + ("+" if r["charging"] else "")
        print(f"{r['t']:%H:%M}   {r['band']:5.1f}   {r['pulses']:6d}  {r['packets']:7d}  {r['cpu']:9.1f}"
              f"  {phone:>7}  {'yes' if r['listening'] else 'no'}")

    first, last = rows[0], rows[-1]
    hours = (last["t"] - first["t"]).total_seconds() / 3600
    drop = first["band"] - last["band"]
    pulses = last["pulses"] - first["pulses"]
    print(f"\nSpan: {hours:.1f} h from {first['t']:%d %b %H:%M} to {last['t']:%d %b %H:%M}, {len(rows)} readings")
    if hours <= 0:
        return

    if drop < 0:
        print("Band battery went up over the span (it was charged), so drain is not worked out.")
    else:
        rate = drop / hours
        print(f"Band: {drop:.1f} points lost, {rate:.2f} points per hour, with {pulses} pulses played")
        if rate > 0:
            print(f"      at this rate a full charge lasts about {100 / rate / 24:.1f} days")
        split = split_drain(rows) if pulses >= 20 else None
        if split:
            print(f"      split estimate: {split[0]:.2f} points per hour at rest, {split[1]:.4f} points per pulse")
            print("      (rough: readings step in tenths of a point, so short spans are unreliable)")
        else:
            print("      not enough varied readings yet to separate resting drain from buzzing")

    cpu = last["cpu"] - first["cpu"]
    packets = last["packets"] - first["packets"]
    print(f"App:  {cpu:.1f} s of CPU over the span ({cpu / hours:.1f} s per hour), "
          f"{packets} data packets handled ({packets / hours:.0f} per hour)")
    if first["phone"] is not None and last["phone"] is not None:
        note = " (charging at some point)" if any(r["charging"] for r in rows) else ""
        print(f"Phone battery: {first['phone']}% to {last['phone']}%{note}. This is the whole phone, not this app.")
    print("For this app's share of phone battery, check iPhone Settings > Battery > WHOOP Buzz.")


if __name__ == "__main__":
    main()
