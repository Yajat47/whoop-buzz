import SwiftUI

@main
struct WhoopBuzzApp: App {
    @StateObject private var band = WhoopBluetooth.shared

    init() {
        if #available(iOS 27.0, *) { WhoopBuzzShortcuts.updateAppShortcutParameters() }
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
                    Section("Tap on the band (experiment)") {
                        Toggle("Listen for double taps", isOn: $band.listensForTaps)
                        Text("When on, a double tap on the band should buzz back once, and every event the band reports is logged below. Listening wakes this app more often, so it uses more battery.")
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
