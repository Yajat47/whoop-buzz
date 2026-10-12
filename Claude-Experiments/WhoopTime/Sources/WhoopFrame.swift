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

// Band events arrive unprompted as type-48 frames on the data channel.
// Layout from the Goose reference, checked against events in this owner's
// captures: inner = [48, sequence, event ID u16, seconds u32, subseconds u16,
// two more bytes, data…], little endian.
struct WhoopEvent {
    static let doubleTap: UInt16 = 14
    // Sent when a single tap lights the band's battery indicator. Seen on
    // 9 Oct beside the owner's taps: BATTERY_LEVEL with event 63, sometimes
    // with event 110. Whether the band also sends them unprompted is unknown.
    static let batteryLight: Set<UInt16> = [3, 63, 110]
    // Reports about past buzzes. They arrive late and in batches.
    static let hapticReports: Set<UInt16> = [60, 100]
    private static let names: [UInt16: String] = [
        3: "BATTERY_LEVEL", 7: "CHARGING_ON", 8: "CHARGING_OFF", 9: "WRIST_ON", 10: "WRIST_OFF",
        11: "BLE_CONNECTION_UP", 12: "BLE_CONNECTION_DOWN", 14: "DOUBLE_TAP", 29: "STRAP_CONDITION_REPORT",
        33: "BLE_REALTIME_HR_ON", 34: "BLE_REALTIME_HR_OFF", 60: "HAPTICS_FIRED",
        63: "EXTENDED_BATTERY_INFORMATION",
        100: "HAPTICS_TERMINATED", 123: "GENERIC_FIRMWARE_EVENT",
    ]

    let id: UInt16
    let data: [UInt8]

    init?(frame: [UInt8]) {
        guard WhoopFrame.valid(frame) else { return nil }
        let inner = Array(frame[8..<(frame.count - 4)])
        guard inner.count >= 4, inner[0] == 48 else { return nil }
        id = UInt16(inner[2]) | UInt16(inner[3]) << 8
        data = inner.count > 12 ? Array(inner[12...]) : []
    }

    var name: String { Self.names[id] ?? "event \(id)" }

    // Band battery in tenths of a percent, where the event carries it. The
    // two events agreed on every reading on 9 Oct (477 beside 477, and so on),
    // and STRAP_CONDITION_REPORT arrives about every ten minutes unprompted.
    // That the unit is tenths of a percent is an assumption from the values.
    var batteryTenths: Int? {
        switch id {
        case 3 where data.count >= 3: return Int(data[1]) | Int(data[2]) << 8
        case 29 where data.count >= 8: return Int(data[6]) | Int(data[7]) << 8
        default: return nil
        }
    }
}

// The time as buzzes, following the Apple Watch "Terse" pattern on a 12-hour
// clock. For the hour a long pulse is 5 and a short pulse is 1. Then, after a
// pause, one long pulse for each quarter hour passed. 7:40 is long, short,
// short, pause, long, long. Two kinds of pulse and never more than four alike
// in a row, because touch takes in only three or four pulses at a glance.
enum TimeCode {
    static let short: [UInt8] = [1, 152]    // a tap
    static let long: [UInt8] = [47, 152]    // the buzz used for alerts

    // Effect bytes of 128 and above are read as pauses of (value - 128) x 10 ms,
    // which is what 152 does in the band's own notification pattern. That
    // reading is an inference from how the patterns feel, not a documented fact.
    static func pause(milliseconds: Int) -> UInt8 {
        UInt8(128 + min(max(milliseconds / 10, 1), 123))
    }

    // How long a command keeps the motor busy, erring on the long side:
    // pauses are exact and each effect is allowed half a second.
    // Pulses in a command body's effect bytes: every byte that is an effect
    // rather than a pause or padding.
    static func pulseCount(_ effects: [UInt8]) -> Int { effects.filter { $0 > 0 && $0 < 128 }.count }

    static func estimatedSeconds(_ effects: [UInt8]) -> Double {
        effects.reduce(0) { $0 + ($1 >= 128 ? Double($1 - 128) / 100 : $1 == 0 ? 0 : 0.5) }
    }

    static func hour(_ hour: Int) -> (long: Int, short: Int) {
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return (twelve / 5, twelve % 5)
    }

    static func quarters(_ minute: Int) -> Int { minute / 15 }

    // The haptic commands for a time. One command holds eight effect bytes,
    // which is four pulses. The hour goes in one command when it fits and is
    // split between its long and short pulses when it does not, which is only
    // nine o'clock. The pause before the quarters is the first byte of their
    // command, so the band times it.
    static func commands(hour: Int, minute: Int) -> [[UInt8]] {
        let count = self.hour(hour)
        let longs = Array(repeating: long, count: count.long).flatMap { $0 }
        let shorts = Array(repeating: short, count: count.short).flatMap { $0 }
        var commands = longs.count + shorts.count <= 8 ? [longs + shorts] : [longs, shorts]
        let quarterCount = quarters(minute)
        if quarterCount > 0 {
            commands.append([pause(milliseconds: 1200)] + Array(repeating: long, count: quarterCount).flatMap { $0 })
        }
        return commands
    }

    static func describe(hour: Int, minute: Int) -> String {
        let count = self.hour(hour)
        let hourWords = Array(repeating: "long", count: count.long) + Array(repeating: "short", count: count.short)
        let quarterWords = Array(repeating: "long", count: quarters(minute))
        return hourWords.joined(separator: " ") + ", pause, " + (quarterWords.isEmpty ? "nothing" : quarterWords.joined(separator: " "))
    }
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

    // Command 19 body: revision 1, eight effect bytes, effect-loop control
    // (two bytes) and overall repeats, the last three left at zero.
    static func hapticBody(_ effects: [UInt8]) -> [UInt8] {
        [1] + Array((effects + Array(repeating: 0, count: 8)).prefix(8)) + [0, 0, 0]
    }

    static func command(_ command: WhoopCommand, sequence: UInt8, body: [UInt8]? = nil) -> Data {
        var inner: [UInt8] = [35, sequence, command.rawValue] + (body ?? command.body)
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
