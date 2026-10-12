import CoreBluetooth
import Combine
import Foundation

@MainActor
final class WhoopBluetooth: NSObject, ObservableObject,
    @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    static let shared = WhoopBluetooth()
    private static let savedBandKey = "whoop.savedPeripheral"
    private static let logKey = "whoop.researchLog"
    private static let service = CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a")
    private static let writeID = CBUUID(string: "fd4b0002-cce1-4033-93ce-002d5875f58a")
    private static let replyID = CBUUID(string: "fd4b0003-cce1-4033-93ce-002d5875f58a")

    @Published private(set) var devices: [CBPeripheral] = []
    @Published private(set) var status = "Allow Bluetooth access to find your WHOOP."
    @Published private(set) var log: [String] = UserDefaults.standard.stringArray(forKey: logKey) ?? []
    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var isRunningShortcut = false

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writer: CBCharacteristic?
    private var replies = WhoopReplies()
    private var nextSequence: UInt8 = 2
    private var pending: [UInt8: WhoopCommand] = [:]
    private var writeQueue: [(UInt8, Data)] = []
    private var writing: UInt8?
    private var scanGeneration = UUID()
    private var buzzGeneration = UUID()
    private var sessionGeneration = UUID()
    private var lastBuzzResult: UInt8?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func note(_ text: String) {
        status = text
        log.insert(Date().formatted(date: .omitted, time: .standard) + "  " + text, at: 0)
        if log.count > 40 { log.removeLast(log.count - 40) }
        UserDefaults.standard.set(log, forKey: Self.logKey)
    }

    func scan() {
        guard central.state == .poweredOn else { note("Turn on Bluetooth and allow access in Settings."); return }
        guard !isConnected && !isConnecting else { return }
        devices = central.retrieveConnectedPeripherals(withServices: [Self.service])
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        note("Looking for WHOOP. Choose your band below.")
        let generation = UUID()
        scanGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.scanGeneration == generation else { return }
            self.central.stopScan()
            if self.devices.isEmpty { self.note("WHOOP was not found. Keep the band nearby and try again.") }
        }
    }

    func connect(_ device: CBPeripheral) {
        guard !isConnected && !isConnecting else { return }
        central.stopScan()
        scanGeneration = UUID()
        sessionGeneration = UUID()
        peripheral = device
        device.delegate = self
        isConnecting = true
        note("Connecting to your WHOOP…")
        central.connect(device)
        let generation = sessionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.sessionGeneration == generation, !self.isReady else { return }
            self.disconnect()
            self.note("Connection setup timed out. Open WHOOP, check that the band is connected, then retry.")
        }
    }

    func disconnect() {
        central.stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        clearSession()
        note("Disconnected.")
    }

    private func clearSession() {
        scanGeneration = UUID()
        buzzGeneration = UUID()
        sessionGeneration = UUID()
        peripheral = nil
        writer = nil
        replies = WhoopReplies()
        pending.removeAll()
        writeQueue.removeAll()
        writing = nil
        nextSequence = 2
        isConnecting = false
        isConnected = false
        isReady = false
        isBusy = false
        lastBuzzResult = nil
    }

    func buzz() {
        guard isReady && !isBusy else { return }
        lastBuzzResult = nil
        isBusy = true
        let generation = UUID()
        buzzGeneration = generation
        enqueue(.buzz)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.buzzGeneration == generation, self.isConnected else { return }
            self.stop()
        }
    }

    func stop() {
        guard isConnected, writer != nil else { return }
        guard !pending.values.contains(.stop) else { return }
        isBusy = true
        enqueue(.stop)
    }

    // App Intents uses the same manager as the UI. A saved peripheral avoids
    // background scanning; the intent awaits replies instead of returning
    // immediately after scheduling a Bluetooth write.
    func buzzFromShortcut() async throws {
        guard !isRunningShortcut && !isBusy else {
            throw ShortcutFailure(message: "WHOOP is already running a vibration test.")
        }
        isRunningShortcut = true
        defer { isRunningShortcut = false }
        let deadline = ContinuousClock().now.advanced(by: .seconds(20))
        note("Shortcuts requested one buzz.")
        do {
            while central.state == .unknown || central.state == .resetting {
                try await waitForShortcutUpdate(until: deadline)
            }
            guard central.state == .poweredOn else {
                throw ShortcutFailure(message: "Turn on Bluetooth and allow WHOOP Buzz to use it.")
            }
            if !isReady {
                if !isConnected && !isConnecting {
                    guard let stored = UserDefaults.standard.string(forKey: Self.savedBandKey),
                          let identifier = UUID(uuidString: stored),
                          let device = central.retrievePeripherals(withIdentifiers: [identifier]).first else {
                        throw ShortcutFailure(message: "Open WHOOP Buzz and connect your band once before using this action.")
                    }
                    connect(device)
                }
                while !isReady {
                    guard isConnected || isConnecting else {
                        throw ShortcutFailure(message: "WHOOP could not connect. Keep the band nearby and reconnect in WHOOP Buzz.")
                    }
                    try await waitForShortcutUpdate(until: deadline)
                }
            }
            try Task.checkCancellation()
            buzz()
            while isBusy {
                guard isReady && isConnected else {
                    throw ShortcutFailure(message: "WHOOP did not complete the vibration test. Reconnect in WHOOP Buzz.")
                }
                try await waitForShortcutUpdate(until: deadline)
            }
            guard isReady && isConnected && lastBuzzResult == 1 else {
                throw ShortcutFailure(message: "WHOOP did not confirm the buzz command. Check the research log.")
            }
            note("Shortcuts buzz and stop replies confirmed.")
        } catch {
            if isBusy && isConnected { stop() }
            note("Shortcuts test failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func waitForShortcutUpdate(until deadline: ContinuousClock.Instant) async throws {
        guard ContinuousClock().now < deadline else {
            throw ShortcutFailure(message: "WHOOP timed out. Open WHOOP Buzz and reconnect your band.")
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    private struct ShortcutFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func enqueue(_ command: WhoopCommand, sequence supplied: UInt8? = nil) {
        guard let peripheral, let writer else { isBusy = false; return }
        let sequence = supplied ?? nextSequence
        guard pending[sequence] == nil else { note("A command is still pending. Wait for its response."); return }
        if supplied == nil { nextSequence &+= 1; if nextSequence < 2 { nextSequence = 2 } }
        let frame = WhoopFrame.command(command, sequence: sequence)
        guard frame.count <= peripheral.maximumWriteValueLength(for: .withResponse), writer.properties.contains(.write)
        else { note("This connection cannot send the test command."); isBusy = false; return }
        pending[sequence] = command
        writeQueue.append((sequence, frame))
        let generation = sessionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.sessionGeneration == generation,
                  self.pending[sequence] == command else { return }
            self.pending.removeValue(forKey: sequence)
            if command == .hello { self.isReady = false }
            // A timeout is not evidence that the band stopped. Keep another
            // buzz disabled until reconnecting after a failed stop.
            if command == .stop { self.isReady = false }
            self.note("No final reply for \(command). Reconnect before another test.")
        }
        writeNext()
    }

    private func writeNext() {
        guard writing == nil, !writeQueue.isEmpty, let peripheral, let writer else { return }
        let (sequence, frame) = writeQueue.removeFirst()
        writing = sequence
        peripheral.writeValue(frame, for: writer, type: .withResponse)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { note("Bluetooth is ready. Tap Find my WHOOP.") }
        else {
            clearSession()
            note(central.state == .unauthorized ? "Allow this app in Settings → Privacy & Security → Bluetooth." : "Bluetooth is unavailable or turned off.")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover device: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertised = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? device.name ?? ""
        guard name.uppercased().contains("WHOOP") || advertised.contains(Self.service) else { return }
        if !devices.contains(where: { $0.identifier == device.identifier }) { devices.append(device) }
    }

    func centralManager(_ central: CBCentralManager, didConnect device: CBPeripheral) {
        guard device == peripheral else { return }
        isConnecting = false
        isConnected = true
        note("Connected. Preparing the vibration test…")
        device.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect device: CBPeripheral, error: Error?) {
        guard device == peripheral else { return }
        clearSession()
        note("Could not connect: \(error?.localizedDescription ?? "try again").")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral device: CBPeripheral, error: Error?) {
        guard device == peripheral else { return }
        clearSession()
        note("WHOOP disconnected. Find the band again.")
    }

    func peripheral(_ device: CBPeripheral, didDiscoverServices error: Error?) {
        guard device == peripheral else { return }
        guard error == nil, let service = device.services?.first(where: { $0.uuid == Self.service })
        else { note("WHOOP 5 service was not available on this connection."); return }
        device.discoverCharacteristics([Self.writeID, Self.replyID], for: service)
    }

    func peripheral(_ device: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard device == peripheral else { return }
        guard error == nil, let chars = service.characteristics,
              let write = chars.first(where: { $0.uuid == Self.writeID }),
              let reply = chars.first(where: { $0.uuid == Self.replyID }), reply.properties.contains(.notify)
        else { note("The band's command channel was not available."); return }
        writer = write
        device.setNotifyValue(true, for: reply)
    }

    func peripheral(_ device: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard device == peripheral, characteristic.uuid == Self.replyID else { return }
        guard error == nil, characteristic.isNotifying else { note("Could not receive band replies."); return }
        enqueue(.hello, sequence: 1)
    }

    func peripheral(_ device: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard device == peripheral, characteristic.uuid == Self.writeID else { return }
        if let error {
            if let writing { pending.removeValue(forKey: writing) }
            isReady = false
            note("Bluetooth write failed: \(error.localizedDescription). Reconnect.")
            writeQueue.removeAll()
        }
        writing = nil
        writeNext()
    }

    func peripheral(_ device: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard device == peripheral, characteristic.uuid == Self.replyID,
              error == nil, let data = characteristic.value else { return }
        for frame in replies.feed(data) {
            let inner = Array(frame[8..<(frame.count - 4)])
            guard inner.count >= 5, inner[0] == 36 || inner[0] == 38,
                  let command = pending[inner[3]], command.rawValue == inner[2] else { continue }
            let result = inner[4]
            if result == 2 { note("Band is processing \(command)…"); continue }
            pending.removeValue(forKey: inner[3])
            if command == .hello {
                isReady = result == 1
                if isReady { UserDefaults.standard.set(device.identifier.uuidString, forKey: Self.savedBandKey) }
                let body = Array(inner.dropFirst(5))
                if isReady, body.count >= 98 {
                    let version = "\(body[91]).\(body[92]).\(body[93]).\(UInt32(body[94]) | UInt32(body[95]) << 8 | UInt32(body[96]) << 16 | UInt32(body[97]) << 24)"
                    note("WHOOP \(version) is ready. Tap Test one buzz.")
                } else { note(isReady ? "WHOOP is ready. Tap Test one buzz." : "Band refused session setup (result \(result)).") }
            } else if command == .buzz {
                lastBuzzResult = result
                let detail = inner.count >= 7 ? String(inner[6]) : "unknown"
                note("Buzz reply: result \(result), detail \(detail). Check whether you felt it.")
                // Keep the button locked until the separate stop completes.
            } else if command == .stop {
                if result == 1 { isBusy = false; note("Band confirmed the stop request. You can test again.") }
                else { isReady = false; note("Stop was not confirmed (result \(result)). Reconnect.") }
            }
        }
    }
}
