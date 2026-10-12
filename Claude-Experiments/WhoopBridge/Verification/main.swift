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
