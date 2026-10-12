import Foundation

// Checks the burst rule used by the Buzz WHOOP action. Runs on the Mac:
//   swiftc Sources/WhoopFrame.swift Verification/main.swift -o /tmp/gate-check && /tmp/gate-check
var failures = 0
func expect(_ condition: Bool, _ label: String) {
    if !condition { failures += 1; print("FAIL: \(label)") }
}

let start = Date(timeIntervalSince1970: 1_000_000)
func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

expect(BuzzGate.allows(now: at(0), lastBuzz: nil, quietSeconds: 10, busy: false), "first alert buzzes")
expect(!BuzzGate.allows(now: at(0), lastBuzz: nil, quietSeconds: 10, busy: true), "alert during a running buzz does not buzz")
expect(!BuzzGate.allows(now: at(0.5), lastBuzz: at(0), quietSeconds: 10, busy: false), "alert 0.5 s after a buzz is quiet")
expect(!BuzzGate.allows(now: at(9.9), lastBuzz: at(0), quietSeconds: 10, busy: false), "alert just inside the quiet time is quiet")
expect(BuzzGate.allows(now: at(10), lastBuzz: at(0), quietSeconds: 10, busy: false), "alert at the end of the quiet time buzzes")
expect(BuzzGate.allows(now: at(61), lastBuzz: at(0), quietSeconds: 60, busy: false), "alert after a longer quiet time buzzes")
expect(!BuzzGate.allows(now: at(59), lastBuzz: at(0), quietSeconds: 60, busy: false), "longer quiet time holds")

// A burst: 12 alerts over 6 seconds, then one 20 s later. Quiet time 10 s.
var last: Date? = nil
var buzzes = 0
for moment in stride(from: 0.0, to: 6.0, by: 0.5).map(at) + [at(26)] {
    if BuzzGate.allows(now: moment, lastBuzz: last, quietSeconds: 10, busy: false) { buzzes += 1; last = moment }
}
expect(buzzes == 2, "13 alerts in a burst plus a later one give 2 buzzes, got \(buzzes)")

// Band events, using frames from this owner's captures.
func bytes(_ hex: String) -> [UInt8] {
    stride(from: 0, to: hex.count, by: 2).map {
        UInt8(hex[hex.index(hex.startIndex, offsetBy: $0)..<hex.index(hex.startIndex, offsetBy: $0 + 2)], radix: 16)!
    }
}
let connectionDown = bytes("aa01100001002081300d0c006584c76aae670000afcf4565")
let condition = bytes("aa011c00010023d1306a1d00fb7bc76a47010c0002000000000010020b0001004bc68678")
let hello = Array(WhoopFrame.command(.hello, sequence: 1))
expect(WhoopEvent(frame: connectionDown)?.id == 12, "captured BLE_CONNECTION_DOWN parses as event 12")
expect(WhoopEvent(frame: connectionDown)?.data.isEmpty == true, "event 12 carries no data")
expect(WhoopEvent(frame: condition)?.id == 29, "captured STRAP_CONDITION_REPORT parses as event 29")
expect(WhoopEvent(frame: condition)?.data.count == 12, "event 29 carries 12 data bytes")
expect(WhoopEvent(frame: hello) == nil, "a command frame is not an event")
var corrupt = connectionDown; corrupt[10] ^= 0x01
expect(WhoopEvent(frame: corrupt) == nil, "a corrupted event frame is rejected")
// The same framing with event ID 14 is what a double tap should look like.
var tap = connectionDown; tap[10] = 14
let inner = Array(tap[8..<(tap.count - 4)])
tap.replaceSubrange((tap.count - 4)..., with: WhoopFrame.littleEndian(WhoopFrame.crc32(inner), count: 4))
expect(WhoopEvent(frame: tap)?.id == WhoopEvent.doubleTap, "a frame with event ID 14 is read as DOUBLE_TAP")
expect(WhoopEvent(frame: tap)?.name == "DOUBLE_TAP", "event 14 is named DOUBLE_TAP")
var feeder = WhoopReplies()
expect(feeder.feed(Data(connectionDown.prefix(9))).isEmpty && feeder.feed(Data(connectionDown.dropFirst(9))).count == 1,
       "an event split across two notifications is reassembled")

// Time code: Apple Watch "Terse" on a 12-hour clock.
let L: [UInt8] = [47, 152], S: [UInt8] = [1, 152]
expect(TimeCode.long == L && TimeCode.short == S, "long is the buzz and short is the tap")
expect(TimeCode.hour(4) == (0, 4), "4 is four short")
expect(TimeCode.hour(5) == (1, 0), "5 is one long")
expect(TimeCode.hour(7) == (1, 2), "7 is one long and two short")
expect(TimeCode.hour(9) == (1, 4), "9 is one long and four short")
expect(TimeCode.hour(10) == (2, 0), "10 is two long")
expect(TimeCode.hour(12) == (2, 2) && TimeCode.hour(0) == (2, 2), "noon and midnight are 12: two long and two short")
expect(TimeCode.hour(19) == TimeCode.hour(7), "19:00 uses the 12-hour clock")
expect((0..<24).allSatisfy { h in let c = TimeCode.hour(h); return c.long <= 2 && c.short <= 4 && c.long * 5 + c.short == (h % 12 == 0 ? 12 : h % 12) },
       "every hour adds up, with at most two long and four short")
expect(TimeCode.quarters(0) == 0 && TimeCode.quarters(14) == 0, "before quarter past there are no quarter pulses")
expect(TimeCode.quarters(15) == 1 && TimeCode.quarters(29) == 1, "quarter past is one")
expect(TimeCode.quarters(30) == 2 && TimeCode.quarters(44) == 2, "half past is two")
expect(TimeCode.quarters(45) == 3 && TimeCode.quarters(59) == 3, "quarter to is three")

// Pause byte.
expect(TimeCode.pause(milliseconds: 240) == 152, "a 240 ms pause is byte 152, as in the band's own pattern")
expect(TimeCode.pause(milliseconds: 1200) == 248, "a 1.2 s pause is byte 248")
expect(TimeCode.pause(milliseconds: 9000) == 251, "pauses are capped at the largest accepted byte, 251")

// Commands sent to the band.
expect(TimeCode.commands(hour: 7, minute: 40) == [L + S + S, [248] + L + L], "7:40 is long short short, then pause long long")
expect(TimeCode.commands(hour: 16, minute: 5) == [S + S + S + S], "16:05 is four short and no second command")
expect(TimeCode.commands(hour: 12, minute: 50) == [L + L + S + S, [248] + L + L + L], "12:50 is long long short short, then pause and three long")
expect(TimeCode.commands(hour: 9, minute: 45) == [L, S + S + S + S, [248] + L + L + L], "9:45 splits the hour between its long and short pulses")
expect(TimeCode.commands(hour: 8, minute: 0) == [L + S + S + S], "8:00 fits the hour in one command")
var allFit = true, mostCommands = 0, mostPulses = 0
for h in 0..<24 { for m in 0..<60 {
    let commands = TimeCode.commands(hour: h, minute: m)
    if commands.contains(where: { $0.isEmpty || $0.count > 8 }) { allFit = false }
    mostCommands = max(mostCommands, commands.count)
    mostPulses = max(mostPulses, commands.flatMap { $0 }.filter { $0 < 128 }.count)
} }
expect(allFit, "every command for every minute of the day has one to eight effect bytes")
expect(mostCommands == 3, "no time needs more than three commands")
expect(mostPulses == 8, "no time needs more than eight pulses")
expect(TimeCode.describe(hour: 7, minute: 40) == "long short short, pause, long long", "7:40 is described in words")
expect(TimeCode.describe(hour: 16, minute: 5) == "short short short short, pause, nothing", "16:05 is described in words")
expect(abs(TimeCode.estimatedSeconds([248, 47, 152]) - 1.94) < 0.001, "pause 1.2 s + effect 0.5 s + pause 0.24 s is estimated at 1.94 s")

// Battery readings carried by events, using frames from this owner's captures.
expect(WhoopEvent(frame: condition)?.batteryTenths == 528, "the captured condition report reads 52.8%")
expect(WhoopEvent(frame: connectionDown)?.batteryTenths == nil, "an event without battery data gives no reading")
// BATTERY_LEVEL as logged on 9 Oct: data 02 dd 01 00 00 0a 0f 00 beside a condition report of 477.
var level = connectionDown
level.replaceSubrange(10..<12, with: [3, 0])
level.replaceSubrange(20..<(level.count - 4), with: [0x02, 0xdd, 0x01, 0x00, 0x00, 0x0a, 0x0f, 0x00])
level[2] = UInt8(level.count - 8)
level.replaceSubrange(6..<8, with: WhoopFrame.littleEndian(UInt32(WhoopFrame.crc16(Array(level[0..<6]))), count: 2))
let levelInner = Array(level[8..<(level.count - 4)])
level.replaceSubrange((level.count - 4)..., with: WhoopFrame.littleEndian(WhoopFrame.crc32(levelInner), count: 4))
expect(WhoopEvent(frame: level)?.id == 3, "the rebuilt battery-level frame is valid")
expect(WhoopEvent(frame: level)?.batteryTenths == 477, "battery level dd 01 reads 47.7%")
expect(TimeCode.pulseCount([47, 152, 1, 152, 0, 0, 0, 0]) == 2, "pauses and padding are not counted as pulses")
expect(TimeCode.pulseCount([248, 47, 152, 47, 152, 47, 152]) == 3, "a leading pause is not a pulse")
expect(TimeCode.commands(hour: 9, minute: 45).map(TimeCode.pulseCount).reduce(0, +) == 8, "9:45 counts eight pulses")

// Events used as the single-tap trigger, and the ones kept out of the log.
expect(WhoopEvent.batteryLight == [3, 63, 110], "battery-light events are 3, 63 and 110")
expect(!WhoopEvent.batteryLight.contains(WhoopEvent.doubleTap), "a double tap is not a battery-light event")
expect(WhoopEvent.hapticReports == [60, 100], "late haptic reports are events 60 and 100")
expect(WhoopEvent.batteryLight.isDisjoint(with: WhoopEvent.hapticReports), "trigger events and haptic reports do not overlap")

// The generated haptic body must reproduce the proven buzz frame exactly.
expect(WhoopFrame.hapticBody([47, 152]) == WhoopCommand.buzz.body, "body for the proven pulse matches the fixed buzz body")
expect(WhoopFrame.command(.buzz, sequence: 2, body: WhoopFrame.hapticBody([47, 152])) == WhoopFrame.command(.buzz, sequence: 2),
       "frame for the proven pulse is byte-identical to the working buzz frame")
expect(WhoopFrame.hapticBody([1, 2, 3, 4, 5, 6, 7, 8, 9]).count == 12, "a haptic body is always 12 bytes")

print(failures == 0 ? "PASS: burst rule, band events and time code, 58 checks" : "FAILED: \(failures) check(s)")
exit(failures == 0 ? 0 : 1)
