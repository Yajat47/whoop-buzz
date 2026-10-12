import Foundation
func data(_ hex: String) -> Data {
    let a = Array(hex)
    return Data(stride(from: 0, to: a.count, by: 2).map { i in UInt8(String(a[i..<(i + 2)]), radix: 16)! })
}
let hello = WhoopFrame.command(.hello, sequence: 188)
precondition(hello == data("aa0108000001e67123bc91035932d4ae"), "Hello differs from owner's capture")
// Captured reply with the band's serial number and device string replaced
// by zeros and the checksum recomputed.
let reply = data("aa01780001003ce124c591bc01030e02000000bc84c76a3333000030303030303030303030003030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030300d0000000000000045000000322a01000000000c000400010000000029173b00f12b3e31")
precondition(WhoopFrame.valid(Array(reply)))
for split in 1..<reply.count {
    var stream = WhoopReplies()
    precondition(stream.feed(reply.prefix(split)).isEmpty)
    precondition(stream.feed(reply.dropFirst(split)) == [Array(reply)])
}
var bad = Array(reply)
bad[12] ^= 1
precondition(!WhoopFrame.valid(bad), "Corrupt payload was accepted")
var stream = WhoopReplies()
precondition(stream.feed(Data([0, 0, 0xaa, 0, 0])).isEmpty)
precondition(stream.feed(reply) == [Array(reply)], "Did not resync after invalid header")
for command in [WhoopCommand.hello, .buzz, .stop] {
    let value = WhoopFrame.command(command, sequence: command == .hello ? 1 : 2)
    precondition(WhoopFrame.valid(Array(value)))
    print("\(command.rawValue):" + value.map { String(format: "%02x", $0) }.joined())
}
print("PASS: captured hello parity, every reply split, CRC corruption and resynchronization")
// Reproduce the owner's observed successful command-19 reply. It can finish
// without sending command 122 after the finite pattern has stopped naturally.
precondition(WhoopHapticReply(result: 1, body: [1, 5]).oneShotSucceeded)
for (result, body): (UInt8, [UInt8]) in [
    (0, [1, 5]), // Generic failure, even with a success-like detail.
    (2, [1, 0]), // Pending is not final success.
    (1, [1, 0]), // Operation-specific detail was not confirmed.
    (1, [0, 5]), // Wrong revision.
    (1, []),     // Truncated body.
    (1, [1])
] {
    precondition(!WhoopHapticReply(result: result, body: body).oneShotSucceeded)
}
print("PASS: one-shot completion requires final success, revision 1 and detail 5")
