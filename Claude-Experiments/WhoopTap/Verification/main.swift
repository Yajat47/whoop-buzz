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

print(failures == 0 ? "PASS: burst rule and band events, 17 checks" : "FAILED: \(failures) check(s)")
exit(failures == 0 ? 0 : 1)
