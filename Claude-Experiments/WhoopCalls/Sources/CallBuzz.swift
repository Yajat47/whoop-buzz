import CallKit
import Combine
import CoreLocation
import Foundation

// Incoming-call buzz. iOS 27 Shortcuts has no call trigger, and a ringing call
// is not a notification, so the app watches call state itself. CallKit reports
// state changes for every call on the phone, including WhatsApp calls, but
// only while this app is running. It gives no caller name, number or app.
@MainActor
final class CallBuzz: NSObject, ObservableObject,
    @preconcurrency CXCallObserverDelegate, @preconcurrency CLLocationManagerDelegate {
    static let shared = CallBuzz()
    private static let enabledKey = "whoop.callBuzzEnabled"
    private static let maximumBuzzes = 10

    @Published private(set) var isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    @Published private(set) var keepAliveStatus = "Off"

    private let observer = CXCallObserver()
    private let location = CLLocationManager()
    private var ringing: Set<UUID> = []
    private var ringTask: Task<Void, Never>?

    override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
        location.delegate = self
        if isEnabled { startKeepAlive() }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        WhoopBluetooth.shared.record("Call buzz turned \(enabled ? "on" : "off").")
        if enabled { startKeepAlive() } else { stopKeepAlive(); stopRinging() }
    }

    // MARK: Call state

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let state = call.hasEnded ? "ended" : call.hasConnected ? "answered"
            : call.isOutgoing ? "outgoing" : "ringing"
        // Logged even when the feature is off, to show which calls iOS reports.
        WhoopBluetooth.shared.record("Call \(call.uuid.uuidString.prefix(4)) \(state).")
        if state == "ringing" { ringing.insert(call.uuid) } else { ringing.remove(call.uuid) }
        guard isEnabled, !ringing.isEmpty else { stopRinging(); return }
        guard ringTask == nil else { return }
        ringTask = Task { [weak self] in
            for _ in 0..<Self.maximumBuzzes {
                guard let self, !Task.isCancelled, !self.ringing.isEmpty else { break }
                let band = WhoopBluetooth.shared
                while band.isBusy || band.isRunningShortcut {
                    try? await Task.sleep(for: .milliseconds(200))
                    if Task.isCancelled { return }
                }
                guard !self.ringing.isEmpty else { break }
                try? await band.requestBuzz(source: "Call")
                try? await Task.sleep(for: .seconds(1))
            }
            self?.ringTask = nil
        }
    }

    private func stopRinging() {
        ringTask?.cancel()
        ringTask = nil
    }

    // MARK: Keep-alive
    //
    // A suspended app is not told about calls. A low-accuracy background
    // location session is the keep-alive that needs no paid capability. No
    // location is read or stored; the delegate ignores every fix.

    private func startKeepAlive() {
        location.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        location.distanceFilter = 3000
        location.pausesLocationUpdatesAutomatically = false
        location.allowsBackgroundLocationUpdates = true
        location.showsBackgroundLocationIndicator = false
        location.requestAlwaysAuthorization()
        location.startUpdatingLocation()
        // With Always access this relaunches the app after a restart or a kill.
        location.startMonitoringSignificantLocationChanges()
        describeKeepAlive()
    }

    private func stopKeepAlive() {
        location.stopUpdatingLocation()
        location.stopMonitoringSignificantLocationChanges()
        keepAliveStatus = "Off"
    }

    private func describeKeepAlive() {
        guard isEnabled else { keepAliveStatus = "Off"; return }
        switch location.authorizationStatus {
        case .authorizedAlways: keepAliveStatus = "Running (Always)"
        case .authorizedWhenInUse: keepAliveStatus = "Running until the app is closed. Choose Always in Settings → WHOOP Buzz → Location."
        case .notDetermined: keepAliveStatus = "Waiting for location permission"
        default: keepAliveStatus = "Blocked: location access is off, so calls are missed in the background."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        describeKeepAlive()
        WhoopBluetooth.shared.record("Call keep-alive: \(keepAliveStatus)")
        if isEnabled { manager.startUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
