import SwiftUI

@main
struct WhoopBuzzApp: App {
    @StateObject private var band = WhoopBluetooth()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    Section("Connect your band") {
                        Text(band.status)
                        Button("Find my WHOOP") { band.scan() }
                            .disabled(band.isConnected || band.isConnecting)
                        ForEach(band.devices, id: \.identifier) { device in
                            HStack {
                                Text(device.name ?? "WHOOP 5")
                                Spacer()
                                Button("Connect") { band.connect(device) }
                                    .disabled(band.isConnected || band.isConnecting)
                            }
                        }
                        Button("Disconnect") { band.disconnect() }
                            .disabled(!band.isConnected && !band.isConnecting)
                    }
                    Section("Vibration test") {
                        Button("Test one buzz") { band.buzz() }
                            .disabled(!band.isReady || band.isBusy)
                        Button("Stop vibration") { band.stop() }
                            .disabled(!band.isConnected)
                        Text("A stop request follows the test after two seconds. Keep this app open during the test.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Notification bridge") {
                        Text("WhatsApp and other app alerts are not connected yet. This first test checks whether your iPhone can make the band buzz.")
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
