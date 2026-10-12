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
                            .disabled(!band.isConnected)
                        Text("A stop request follows the test after two seconds. Keep this app open during the test.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Notification bridge") {
                        Text("Connect your band here once. In Shortcuts, use the Buzz WHOOP action for your automation. Notification-trigger and locked-phone operation still need testing.")
                            .font(.footnote)
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
