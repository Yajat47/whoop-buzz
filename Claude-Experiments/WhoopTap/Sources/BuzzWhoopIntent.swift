import AppIntents

@available(iOS 27.0, *)
struct BuzzWhoopIntent: AppIntent {
    static var title: LocalizedStringResource { "Buzz WHOOP" }
    static var description: IntentDescription {
        IntentDescription("Run one vibration test on the WHOOP 5 connected in WHOOP Buzz.")
    }
    static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await WhoopBluetooth.shared.buzzFromShortcut()
        return .result()
    }
}

@available(iOS 27.0, *)
struct WhoopBuzzShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BuzzWhoopIntent(),
            phrases: ["Buzz my band with \(.applicationName)"],
            shortTitle: "Buzz WHOOP",
            systemImageName: "waveform"
        )
    }
}
