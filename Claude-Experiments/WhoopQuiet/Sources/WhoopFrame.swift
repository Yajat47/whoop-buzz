import Foundation

// WHOOP 5 format-1 framing, checked against this owner's saved captures.
// Haptics reference: ryanbr/noop, commit 8e94d559be273ec8d74832fe5db78898be83cc11.
enum WhoopCommand: UInt8 {
    case hello = 145
    case buzz = 19
    case stop = 122

    var body: [UInt8] {
        switch self {
        case .hello: return [3] // Revision used by the owner's official-app capture.
        case .stop: return [1]
        case .buzz: return [1, 47, 152, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }
    }
}

// Command 19's final reply carries revision and operation-specific detail.
// A generic success or pending acknowledgement alone is insufficient.
struct WhoopHapticReply {
    let result: UInt8
    let revision: UInt8?
    let detail: UInt8?

    init(result: UInt8, body: [UInt8]) {
        self.result = result
        revision = body.first
        detail = body.count > 1 ? body[1] : nil
    }

    var oneShotSucceeded: Bool { result == 1 && revision == 1 && detail == 5 }
}

// Burst rule for alerts. Messages often arrive several at once; one buzz
// covers every alert that lands while it runs or within the quiet time after.
enum BuzzGate {
    static func allows(now: Date, lastBuzz: Date?, quietSeconds: Int, busy: Bool) -> Bool {
        if busy { return false }
        guard let lastBuzz else { return true }
        return now.timeIntervalSince(lastBuzz) >= Double(quietSeconds)
    }
}

enum WhoopFrame {
    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var value: UInt16 = 0xffff
        for byte in bytes {
            value ^= UInt16(byte)
            for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 1 ? 0xa001 : 0) }
        }
        return value
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var value: UInt32 = 0xffffffff
        for byte in bytes {
            value ^= UInt32(byte)
            for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 1 ? 0xedb88320 : 0) }
        }
        return value ^ 0xffffffff
    }

    static func littleEndian(_ value: UInt32, count: Int) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }

    static func command(_ command: WhoopCommand, sequence: UInt8) -> Data {
        var inner: [UInt8] = [35, sequence, command.rawValue] + command.body
        inner += Array(repeating: 0, count: (4 - inner.count % 4) % 4)
        var header: [UInt8] = [0xaa, 1]
        header += littleEndian(UInt32(inner.count + 4), count: 2)
        header += [0, 1]
        header += littleEndian(UInt32(crc16(header)), count: 2)
        return Data(header + inner + littleEndian(crc32(inner), count: 4))
    }

    static func valid(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 13, bytes[0] == 0xaa, bytes[1] == 1 else { return false }
        let declared = Int(bytes[2]) | Int(bytes[3]) << 8
        let headerCRC = UInt16(bytes[6]) | UInt16(bytes[7]) << 8
        let tail = bytes.count - 4
        let payloadCRC = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[tail + $1]) << ($1 * 8) }
        return declared + 8 == bytes.count
            && crc16(Array(bytes[0..<6])) == headerCRC
            && crc32(Array(bytes[8..<tail])) == payloadCRC
    }
}

struct WhoopReplies {
    private var buffer: [UInt8] = []

    mutating func feed(_ data: Data) -> [[UInt8]] {
        buffer += data
        var frames: [[UInt8]] = []
        while !buffer.isEmpty {
            guard let start = buffer.firstIndex(of: 0xaa) else { buffer.removeAll(); break }
            buffer.removeFirst(start)
            guard buffer.count >= 8 else { break }
            let count = (Int(buffer[2]) | Int(buffer[3]) << 8) + 8
            guard buffer[1] == 1, (13...4096).contains(count),
                  WhoopFrame.crc16(Array(buffer[0..<6])) == UInt16(buffer[6]) | UInt16(buffer[7]) << 8
            else { buffer.removeFirst(); continue }
            guard buffer.count >= count else { break }
            let frame = Array(buffer.prefix(count))
            buffer.removeFirst(count)
            if WhoopFrame.valid(frame) { frames.append(frame) }
        }
        return frames
    }
}
