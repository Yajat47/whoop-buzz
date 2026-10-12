import CoreBluetooth
import Combine
import Foundation
import UIKit

@MainActor
final class WhoopBluetooth: NSObject, ObservableObject,
    @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    static let shared = WhoopBluetooth()
    private static let savedBandKey = "whoop.savedPeripheral"
    private static let logKey = "whoop.researchLog"
    private static let quietKey = "whoop.quietSeconds"
    static let quietChoices = [5, 10, 30, 60, 120]
    private static let tapKey = "whoop.listenForTaps"
    private static let triggerKey = "whoop.tapTrigger"
    private static let batteryLogKey = "whoop.batteryLog"
    private static let pulsesKey = "whoop.stat.pulses"
    private static let packetsKey = "whoop.stat.dataPackets"
    private static let cpuKey = "whoop.stat.cpuSeconds"
    private static let dataID = CBUUID(string: "fd4b0005-cce1-4033-93ce-002d5875f58a")
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
    // Seconds after a buzz during which further alerts do not buzz again.
    // Experiment: watch the band's event stream for a double tap.
    @Published var listensForTaps = UserDefaults.standard.bool(forKey: WhoopBluetooth.tapKey) {
        didSet {
            UserDefaults.standard.set(listensForTaps, forKey: Self.tapKey)
            applyTapListening()
        }
    }
    // Which tap starts the action: "either", "double" or "single". The band's
    // own double-tap detection misses some taps; the single tap that lights
    // its battery indicator is more dependable.
    @Published var tapTrigger = UserDefaults.standard.string(forKey: WhoopBluetooth.triggerKey) ?? "either" {
        didSet { UserDefaults.standard.set(tapTrigger, forKey: Self.triggerKey) }
    }
    @Published var quietSeconds: Int = {
        let saved = UserDefaults.standard.integer(forKey: WhoopBluetooth.quietKey)
        return saved > 0 ? saved : 10
    }() {
        didSet { UserDefaults.standard.set(quietSeconds, forKey: Self.quietKey) }
    }

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
    private var lastBuzzReply: WhoopHapticReply?
    private var lastShortcutBuzz: Date?
    private var dataChannel: CBCharacteristic?
    private var dataFrames = WhoopReplies()
    private var ignoreTapsUntil = Date.distantPast
    private var ignoredTaps = 0
    private var ignoreSingleTapsUntil = Date.distantPast
    private var recentSingleTriggers: [Date] = []
    private var playingSequence = false
    private var busyRetries = 0
    private var userDisconnected = false
    private var restoredBand: CBPeripheral?

    // Battery study. Each band battery reading is saved with running totals
    // so drain can be set against buzzing and against this app's own work.
    @Published private(set) var bandBattery = "no reading yet"
    private var batteryLog = UserDefaults.standard.stringArray(forKey: batteryLogKey) ?? []
    private var pulsesBySequence: [UInt8: Int] = [:]
    private var lastCPU = 0.0
    private var lastBatterySample: (tenths: Int, at: Date)?

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    }

    private func add(_ amount: Double, to key: String) {
        UserDefaults.standard.set(UserDefaults.standard.double(forKey: key) + amount, forKey: key)
    }

    // One line per reading: time, band battery (tenths of a percent), pulses
    // played, data-channel packets handled, CPU seconds used by this app,
    // phone battery percent, phone charging, listening for taps.
    private func recordBattery(_ tenths: Int) {
        bandBattery = String(format: "%.1f%% at %@", Double(tenths) / 10, Date().formatted(date: .omitted, time: .shortened))
        if let last = lastBatterySample, last.tenths == tenths, Date().timeIntervalSince(last.at) < 300 { return }
        lastBatterySample = (tenths, Date())
        let cpu = Self.cpuSeconds()
        add(cpu - lastCPU, to: Self.cpuKey)
        lastCPU = cpu
        UIDevice.current.isBatteryMonitoringEnabled = true
        let phone = UIDevice.current.batteryLevel
        let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        let defaults = UserDefaults.standard
        batteryLog.append([
            ISO8601DateFormatter().string(from: Date()), String(tenths),
            String(Int(defaults.double(forKey: Self.pulsesKey))), String(Int(defaults.double(forKey: Self.packetsKey))),
            String(format: "%.2f", defaults.double(forKey: Self.cpuKey)),
            phone < 0 ? "" : String(Int((phone * 100).rounded())), charging ? "1" : "0", listensForTaps ? "1" : "0",
        ].joined(separator: ","))
        if batteryLog.count > 1000 { batteryLog.removeFirst(batteryLog.count - 1000) }
        defaults.set(batteryLog, forKey: Self.batteryLogKey)
    }
    private var joinedAlerts = 0

    override init() {
        super.init()
        // The restore identifier lets iOS relaunch the app for band events
        // after it has ended it in the background.
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "whoop-buzz-central"])
        note("App process \(ProcessInfo.processInfo.processIdentifier) started.")
    }

    private func note(_ text: String) {
        status = text
        log.insert(Date().formatted(date: .omitted, time: .standard) + "  " + text, at: 0)
        if log.count > 120 { log.removeLast(log.count - 120) }
        UserDefaults.standard.set(log, forKey: Self.logKey)
    }

    // Log line that leaves the status text alone.
    private func logOnly(_ text: String) {
        let current = status
        note(text)
        status = current
    }

    // The data channel carries the band's events. It also carries stored
    // data whenever the WHOOP app syncs, so listening wakes this app more.
    private func applyTapListening() {
        guard let peripheral, let dataChannel, isConnected,
              dataChannel.properties.contains(.notify),
              dataChannel.isNotifying != listensForTaps else { return }
        peripheral.setNotifyValue(listensForTaps, for: dataChannel)
    }

    private func handleBandData(_ data: Data) {
        add(1, to: Self.packetsKey)
        for frame in dataFrames.feed(data) {
            guard let event = WhoopEvent(frame: frame) else { continue }
            if let tenths = event.batteryTenths { recordBattery(tenths) }
            let detail = event.data.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")
            if WhoopEvent.hapticReports.contains(event.id) { continue }
            if event.id == WhoopEvent.doubleTap {
                handleTap(isDouble: true)
                continue
            }
            logOnly("Band event \(event.name)" + (detail.isEmpty ? "." : " [\(detail)]."))
            if WhoopEvent.batteryLight.contains(event.id) { handleTap(isDouble: false) }
        }
    }

    // The band reports extra double taps around a buzz (seen 9 Oct: two more
    // within a second of each reply), most likely its own vibration. Taps are
    // therefore ignored while anything plays and for three seconds afterwards.
    private func handleTap(isDouble: Bool) {
        guard tapTrigger == "either" || tapTrigger == (isDouble ? "double" : "single") else { return }
        guard isReady, !isBusy, !isRunningShortcut, Date() >= ignoreTapsUntil else {
            if isDouble { ignoredTaps += 1 }
            return
        }
        if !isDouble {
            // If the band's own buzzing ever lit the battery indicator, each
            // playback would start the next. A longer wait after any buzz and
            // a cap of three a minute stop that from running away.
            guard Date() >= ignoreSingleTapsUntil else { return }
            recentSingleTriggers = recentSingleTriggers.filter { Date().timeIntervalSince($0) < 60 }
            guard recentSingleTriggers.count < 3 else {
                logOnly("Single-tap trigger paused: three in the last minute.")
                return
            }
            recentSingleTriggers.append(Date())
        }
        if ignoredTaps > 0 {
            logOnly("\(ignoredTaps) double-tap event\(ignoredTaps == 1 ? "" : "s") ignored around the last buzz.")
            ignoredTaps = 0
        }
        logOnly((isDouble ? "Double tap" : "Single tap (battery light)") + ": playing the time.")
        playTime()
    }

    private enum Started { case yes, motorBusy, no }

    // Sends one haptic command and waits for the band's final reply.
    private func sendEffects(_ effects: [UInt8]) async -> Started {
        guard isReady, isConnected else { return .no }
        lastBuzzReply = nil
        enqueue(.buzz, body: WhoopFrame.hapticBody(effects))
        let deadline = ContinuousClock().now.advanced(by: .seconds(6))
        while lastBuzzReply == nil, isReady, isConnected, ContinuousClock().now < deadline {
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard let reply = lastBuzzReply else { return .no }
        if reply.oneShotSucceeded { return .yes }
        return reply.result == 0 && reply.detail == 7 ? .motorBusy : .no
    }

    // The band's success reply means "started", not "finished": on 9 Oct every
    // lab pulse was confirmed within 0.6 s, and a second command sent while
    // the first pattern was still running came back about a second later as
    // result 0, detail 7. The band waits roughly that long for the motor, so
    // resending until it starts makes one pattern follow the other.
    private func playEffects(_ effects: [UInt8]) async -> Bool {
        for _ in 0..<8 {
            switch await sendEffects(effects) {
            case .yes: return true
            case .motorBusy: busyRetries += 1
            case .no: return false
            }
        }
        return false
    }

    // Holds the app busy until the last pattern has had time to finish, then
    // keeps ignoring taps for three more seconds.
    private func finishPlayback(lastCommand: [UInt8]) async {
        try? await Task.sleep(for: .milliseconds(Int(TimeCode.estimatedSeconds(lastCommand) * 1000)))
        playingSequence = false
        isBusy = false
        ignoreTapsUntil = Date().addingTimeInterval(3)
        ignoreSingleTapsUntil = Date().addingTimeInterval(10)
    }

    // Plays the time now, or a chosen time for practice.
    func playTime(_ chosen: Date = Date()) {
        guard isReady, !isBusy, !isRunningShortcut else { return }
        let now = Calendar.current.dateComponents([.hour, .minute], from: chosen)
        let hour = now.hour ?? 0, minute = now.minute ?? 0
        let commands = TimeCode.commands(hour: hour, minute: minute)
        isBusy = true
        playingSequence = true
        busyRetries = 0
        buzzGeneration = UUID()
        let started = Date()
        logOnly(String(format: "Time %d:%02d as %@.", hour, minute, TimeCode.describe(hour: hour, minute: minute)))
        Task { [weak self] in
            guard let self else { return }
            var sent = 0
            for effects in commands {
                var ok = await self.playEffects(effects)
                // If the band refuses a command that begins with a pause,
                // wait here instead and send the pulses without it.
                if !ok, let first = effects.first, first >= 128, self.lastBuzzReply?.detail != 7 {
                    try? await Task.sleep(for: .milliseconds(1200))
                    ok = await self.playEffects(Array(effects.dropFirst()))
                }
                guard ok else { break }
                sent += 1
            }
            await self.finishPlayback(lastCommand: sent > 0 ? commands[sent - 1] : [])
            let reply = self.lastBuzzReply
            self.logOnly(sent == commands.count
                ? String(format: "Time played: %d commands started over %.1f s, %d resent while the motor was busy.",
                         sent, Date().timeIntervalSince(started), self.busyRetries)
                : "Time playback stopped at command \(sent + 1) of \(commands.count): result \(reply.map { String($0.result) } ?? "none"), detail \(reply?.detail.map { String($0) } ?? "none").")
        }
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
        userDisconnected = false
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
            self.retryConnection("Connection setup timed out. Waiting for the band.")
        }
    }

    // The Disconnect button. The app stays disconnected until the owner
    // connects again or an alert arrives.
    func disconnect() {
        userDisconnected = true
        central.stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        clearSession()
        note("Disconnected.")
    }

    // Keeps a standing request to the saved band. Core Bluetooth holds it with
    // no time limit, also while the app is suspended, and completes it when
    // the band is back in range or Bluetooth is back on. Before this, a lost
    // connection stayed lost until the next alert or a manual reconnect, and
    // taps on the band did nothing in between.
    private func reconnectWhenAvailable() {
        guard central.state == .poweredOn, !userDisconnected, !isConnected, !isConnecting else { return }
        let saved = UserDefaults.standard.string(forKey: Self.savedBandKey).flatMap { UUID(uuidString: $0) }
        guard let device = restoredBand ?? saved.flatMap({ central.retrievePeripherals(withIdentifiers: [$0]).first })
        else { return }
        restoredBand = nil
        sessionGeneration = UUID()
        peripheral = device
        device.delegate = self
        isConnecting = true
        note("Waiting for your WHOOP.")
        if device.state == .connected { centralManager(central, didConnect: device) } else { central.connect(device) }
    }

    // Drops a connection that is not working and waits for the band again.
    private func retryConnection(_ message: String) {
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        clearSession()
        note(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.reconnectWhenAvailable() }
    }

    private func clearSession() {
        scanGeneration = UUID()
        buzzGeneration = UUID()
        sessionGeneration = UUID()
        peripheral = nil
        writer = nil
        replies = WhoopReplies()
        dataChannel = nil
        dataFrames = WhoopReplies()
        playingSequence = false
        pending.removeAll()
        writeQueue.removeAll()
        writing = nil
        nextSequence = 2
        isConnecting = false
        isConnected = false
        isReady = false
        isBusy = false
        lastBuzzReply = nil
    }

    func buzz() {
        guard isReady && !isBusy else { return }
        lastBuzzReply = nil
        isBusy = true
        let generation = UUID()
        buzzGeneration = generation
        enqueue(.buzz)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.buzzGeneration == generation, self.isConnected,
                  self.isReady, self.isBusy else { return }
            // The finite pattern already finishes on the band. The owner's
            // trace shows success before this guard, then failure from a late
            // stop. Keep the two-second cooldown, without an unnecessary stop.
            if self.lastBuzzReply?.oneShotSucceeded == true {
                self.isBusy = false
                self.note("One buzz confirmed. Ready for the next alert.")
            } else {
                self.stop()
            }
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
        // Extra alerts in a burst succeed without buzzing, so the automation
        // neither fails nor buzzes once per message.
        guard BuzzGate.allows(now: Date(), lastBuzz: lastShortcutBuzz, quietSeconds: quietSeconds,
                              busy: isRunningShortcut || isBusy) else {
            joinedAlerts += 1
            if joinedAlerts == 1 { note("More alerts arrived; no extra buzz during the quiet time.") }
            return
        }
        if joinedAlerts > 0 {
            note("\(joinedAlerts) alert\(joinedAlerts == 1 ? "" : "s") skipped during the last quiet time.")
            joinedAlerts = 0
        }
        isRunningShortcut = true
        defer { isRunningShortcut = false }
        let deadline = ContinuousClock().now.advanced(by: .seconds(20))
        note("Shortcuts requested one buzz.")
        do {
            while central.state == .unknown || central.state == .resetting {
                try await waitForShortcutUpdate(until: deadline)
            }
            // With Bluetooth off or the band out of reach there is nothing to
            // buzz. The alert is skipped quietly instead of failing, so the
            // phone does not show an automation error for every message.
            guard central.state == .poweredOn else {
                note("Alert not buzzed: Bluetooth is \(bluetoothStateName).")
                return
            }
            if !isReady {
                userDisconnected = false
                reconnectWhenAvailable()
                // A band in range finishes setup within a second or two.
                let patience = ContinuousClock().now.advanced(by: .seconds(8))
                while !isReady, ContinuousClock().now < patience {
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard isReady else {
                    note("Alert not buzzed: the band is not connected. Still waiting for it.")
                    return
                }
            }
            try Task.checkCancellation()
            let started = Date()
            buzz()
            while isBusy {
                guard isReady && isConnected else {
                    throw ShortcutFailure(message: "WHOOP connection changed during the test. Bluetooth is \(bluetoothStateName). Reconnect in WHOOP Buzz.")
                }
                try await waitForShortcutUpdate(until: deadline)
            }
            guard central.state == .poweredOn else {
                throw ShortcutFailure(message: "Bluetooth became \(bluetoothStateName) during the test. Reconnect once it is ready.")
            }
            guard isReady && isConnected else {
                throw ShortcutFailure(message: "WHOOP lost its connection during the test. Reconnect in WHOOP Buzz.")
            }
            guard lastBuzzReply?.oneShotSucceeded == true else {
                throw ShortcutFailure(message: "WHOOP did not confirm the buzz command. Check the research log.")
            }
            // The quiet time starts only after a buzz the band confirmed, so
            // a failed attempt does not mute the alerts that follow it.
            lastShortcutBuzz = started
            note("Shortcuts one-buzz reply confirmed.")
        } catch {
            // A rejected stop disables readiness. Do not automatically repeat
            // that failed command while reporting the Shortcut error.
            if isBusy && isConnected && isReady { stop() }
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

    private var bluetoothStateName: String {
        switch central.state {
        case .unknown: "not ready yet"
        case .resetting: "resetting"
        case .unsupported: "unsupported"
        case .unauthorized: "not authorised"
        case .poweredOff: "turned off"
        case .poweredOn: "ready"
        @unknown default: "unavailable"
        }
    }

    private func enqueue(_ command: WhoopCommand, sequence supplied: UInt8? = nil, body: [UInt8]? = nil) {
        guard let peripheral, let writer else { isBusy = false; return }
        let sequence = supplied ?? nextSequence
        guard pending[sequence] == nil else { note("A command is still pending. Wait for its response."); return }
        if supplied == nil { nextSequence &+= 1; if nextSequence < 2 { nextSequence = 2 } }
        let frame = WhoopFrame.command(command, sequence: sequence, body: body)
        guard frame.count <= peripheral.maximumWriteValueLength(for: .withResponse), writer.properties.contains(.write)
        else { note("This connection cannot send the test command."); isBusy = false; return }
        pending[sequence] = command
        if command == .buzz {
            pulsesBySequence[sequence] = TimeCode.pulseCount(Array((body ?? command.body).dropFirst().prefix(8)))
        }
        writeQueue.append((sequence, frame))
        let generation = sessionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.sessionGeneration == generation,
                  self.pending[sequence] == command else { return }
            self.pending.removeValue(forKey: sequence)
            if command == .hello { self.isReady = false }
            // A timeout is not evidence that the band stopped. Keep another
            // buzz disabled until reconnecting after a failed stop.
            if command == .stop {
                self.isReady = false
                self.isBusy = false
                self.buzzGeneration = UUID()
            }
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
        if central.state == .poweredOn {
            note("Bluetooth is ready.")
            reconnectWhenAvailable()
        } else {
            clearSession()
            note(central.state == .unauthorized ? "Bluetooth is not authorised. Allow this app in Settings → Privacy & Security → Bluetooth." : "Bluetooth is \(bluetoothStateName).")
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
        let generation = sessionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.sessionGeneration == generation, !self.isReady else { return }
            self.retryConnection("Band setup did not finish. Waiting for the band.")
        }
    }

    // iOS hands back the band the app was connected to, or waiting for, when
    // it relaunches the app in the background.
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        restoredBand = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect device: CBPeripheral, error: Error?) {
        guard device == peripheral else { return }
        retryConnection("Could not connect: \(error?.localizedDescription ?? "unknown reason"). Waiting for the band.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral device: CBPeripheral, error: Error?) {
        guard device == peripheral else { return }
        clearSession()
        note("WHOOP disconnected.")
        reconnectWhenAvailable()
    }

    func peripheral(_ device: CBPeripheral, didDiscoverServices error: Error?) {
        guard device == peripheral else { return }
        guard error == nil, let service = device.services?.first(where: { $0.uuid == Self.service })
        else { note("WHOOP 5 service was not available on this connection."); return }
        device.discoverCharacteristics([Self.writeID, Self.replyID, Self.dataID], for: service)
    }

    func peripheral(_ device: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard device == peripheral else { return }
        guard error == nil, let chars = service.characteristics,
              let write = chars.first(where: { $0.uuid == Self.writeID }),
              let reply = chars.first(where: { $0.uuid == Self.replyID }), reply.properties.contains(.notify)
        else { note("The band's command channel was not available."); return }
        writer = write
        dataChannel = chars.first(where: { $0.uuid == Self.dataID })
        device.setNotifyValue(true, for: reply)
    }

    func peripheral(_ device: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if device == peripheral, characteristic.uuid == Self.dataID {
            logOnly(error != nil ? "Could not listen for taps: \(error!.localizedDescription)"
                    : characteristic.isNotifying ? "Listening for taps on the band." : "Stopped listening for taps.")
            return
        }
        guard device == peripheral, characteristic.uuid == Self.replyID else { return }
        guard error == nil, characteristic.isNotifying else { note("Could not receive band replies."); return }
        enqueue(.hello, sequence: 1)
    }

    func peripheral(_ device: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard device == peripheral, characteristic.uuid == Self.writeID else { return }
        if let error {
            if let writing { pending.removeValue(forKey: writing) }
            isReady = false
            isBusy = false
            buzzGeneration = UUID()
            note("Bluetooth write failed: \(error.localizedDescription). Reconnect.")
            writeQueue.removeAll()
        }
        writing = nil
        writeNext()
    }

    func peripheral(_ device: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if device == peripheral, characteristic.uuid == Self.dataID {
            if error == nil, let data = characteristic.value { handleBandData(data) }
            return
        }
        guard device == peripheral, characteristic.uuid == Self.replyID,
              error == nil, let data = characteristic.value else { return }
        for frame in replies.feed(data) {
            let inner = Array(frame[8..<(frame.count - 4)])
            guard inner.count >= 5, inner[0] == 36 || inner[0] == 38,
                  let command = pending[inner[3]], command.rawValue == inner[2] else { continue }
            let result = inner[4]
            if result == 2 {
                if !(playingSequence && command == .buzz) { note("Band is processing \(command)…") }
                continue
            }
            pending.removeValue(forKey: inner[3])
            if command == .hello {
                isReady = result == 1
                if isReady { UserDefaults.standard.set(device.identifier.uuidString, forKey: Self.savedBandKey) }
                if isReady { applyTapListening() }
                let body = Array(inner.dropFirst(5))
                if isReady, body.count >= 98 {
                    let version = "\(body[91]).\(body[92]).\(body[93]).\(UInt32(body[94]) | UInt32(body[95]) << 8 | UInt32(body[96]) << 16 | UInt32(body[97]) << 24)"
                    note("WHOOP \(version) is ready. Tap Test one buzz.")
                } else { note(isReady ? "WHOOP is ready. Tap Test one buzz." : "Band refused session setup (result \(result)).") }
            } else if command == .buzz {
                lastBuzzReply = WhoopHapticReply(result: result, body: Array(inner.dropFirst(5)))
                // Count pulses only for commands the band started.
                if lastBuzzReply?.oneShotSucceeded == true { add(Double(pulsesBySequence[inner[3]] ?? 0), to: Self.pulsesKey) }
                pulsesBySequence.removeValue(forKey: inner[3])
                let revision = lastBuzzReply?.revision.map { String($0) } ?? "unknown"
                let detail = lastBuzzReply?.detail.map { String($0) } ?? "unknown"
                // A time playback logs one summary line instead of every reply.
                if !playingSequence {
                    note("Buzz reply: result \(result), revision \(revision), detail \(detail). Check whether you felt it.")
                }
                ignoreTapsUntil = Date().addingTimeInterval(3)
                ignoreSingleTapsUntil = Date().addingTimeInterval(10)
                // Keep the button locked for the short pattern's cooldown.
            } else if command == .stop {
                if result == 1 { isBusy = false; note("Band confirmed the stop request. You can test again.") }
                else {
                    isReady = false
                    isBusy = false
                    buzzGeneration = UUID()
                    note("Stop was not confirmed (result \(result)). Reconnect.")
                }
            }
        }
    }
}
