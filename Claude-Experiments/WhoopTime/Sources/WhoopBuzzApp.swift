import SwiftUI

@main
struct WhoopBuzzApp: App {
    @StateObject private var band = WhoopBluetooth.shared
    @State private var practiceTime = Date()

    init() {
        if #available(iOS 27.0, *) { WhoopBuzzShortcuts.updateAppShortcutParameters() }
        // Start Bluetooth on every launch, including background relaunches
        // where no screen is drawn, so the band reconnects by itself.
        _ = WhoopBluetooth.shared
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    Section("Connect your band") {
                        Text(band.status)
                        Button("Find my WHOOP") { band.scan() }
                            .disabled(band.isConnected || band.isConnecting || band.isRunningShortcut)
                        ForEach(band.devices, id: \.identifier) { device in
                            HStack {
                                Text(device.name ?? "WHOOP 5")
                                Spacer()
                                Button("Connect") { band.connect(device) }
                                    .disabled(band.isConnected || band.isConnecting || band.isRunningShortcut)
                            }
                        }
                        Button("Disconnect") { band.disconnect() }
                            .disabled(!band.isConnected && !band.isConnecting)
                    }
                    Section("Vibration test") {
                        Button("Test one buzz") { band.buzz() }
                            .disabled(!band.isReady || band.isBusy || band.isRunningShortcut)
                        Button("Stop vibration") { band.stop() }
                            .disabled(!band.isConnected || !band.isBusy)
                        Text("The band plays one short pattern. Stop vibration can end a test early.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Notification bridge") {
                        Text("Connect your band here once. In Shortcuts, use the Buzz WHOOP action for your automation.")
                            .font(.footnote)
                        Picker("Quiet time after a buzz", selection: $band.quietSeconds) {
                            ForEach(WhoopBluetooth.quietChoices, id: \.self) { seconds in
                                Text(seconds < 60 ? "\(seconds) seconds" : "\(seconds / 60) min").tag(seconds)
                            }
                        }
                        Text("When several alerts arrive together, the band buzzes once. Alerts within this time of a buzz do not buzz again.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Tap the band for the time") {
                        Toggle("Listen for taps", isOn: $band.listensForTaps)
                        Picker("Trigger", selection: $band.tapTrigger) {
                            Text("Single or double tap").tag("either")
                            Text("Double tap only").tag("double")
                            Text("Single tap only").tag("single")
                        }
                        Button("Play the time now") { band.playTime() }
                            .disabled(!band.isReady || band.isBusy || band.isRunningShortcut)
                        DatePicker("Practise a time", selection: $practiceTime, displayedComponents: .hourAndMinute)
                        Button("Play the practice time") { band.playTime(practiceTime) }
                            .disabled(!band.isReady || band.isBusy || band.isRunningShortcut)
                        Text("The hour first: a buzz is 5, a tap is 1. Then a pause, then one buzz for each quarter hour passed. 7:40 is buzz, tap, tap, pause, buzz, buzz. Nothing after the pause means less than a quarter past.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("A single tap is the one that lights the band's battery indicator. It is picked up more reliably than a double tap, but a knock can set it off. Listening wakes this app more often, so it uses more battery.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Battery study") {
                        Text("Band battery: \(band.bandBattery)")
                        Text("While listening is on, the app saves a band battery reading about every ten minutes, with how much it has buzzed. Run the report on the Mac to see the drain.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Research log") {
                        ForEach(Array(band.log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption).textSelection(.enabled)
                        }
                    }
                }
                .navigationTitle("WHOOP Buzz")
            }
        }
    }
}
