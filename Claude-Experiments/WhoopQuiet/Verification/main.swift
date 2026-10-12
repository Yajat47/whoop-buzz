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

print(failures == 0 ? "PASS: burst rule, 8 checks" : "FAILED: \(failures) check(s)")
exit(failures == 0 ? 0 : 1)
