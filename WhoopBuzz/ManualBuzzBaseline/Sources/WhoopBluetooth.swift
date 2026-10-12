import CoreBluetooth
import Combine
import Foundation

@MainActor
final class WhoopBluetooth: NSObject, ObservableObject,
    @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private static let service = CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a")
    private static let writeID = CBUUID(string: "fd4b0002-cce1-4033-93ce-002d5875f58a")
    private static let replyID = CBUUID(string: "fd4b0003-cce1-4033-93ce-002d5875f58a")

    @Published private(set) var devices: [CBPeripheral] = []
    @Published private(set) var status = "Allow Bluetooth access to find your WHOOP."
    @Published private(set) var log: [String] = []
    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false

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

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func note(_ text: String) {
        status = text
        log.insert(Date().formatted(date: .omitted, time: .standard) + "  " + text, at: 0)
        if log.count > 40 { log.removeLast(log.count - 40) }
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
    }

    func buzz() {
        guard isReady && !isBusy else { return }
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
                let body = Array(inner.dropFirst(5))
                if isReady, body.count >= 98 {
                    let version = "\(body[91]).\(body[92]).\(body[93]).\(UInt32(body[94]) | UInt32(body[95]) << 8 | UInt32(body[96]) << 16 | UInt32(body[97]) << 24)"
                    note("WHOOP \(version) is ready. Tap Test one buzz.")
                } else { note(isReady ? "WHOOP is ready. Tap Test one buzz." : "Band refused session setup (result \(result)).") }
            } else if command == .buzz {
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
