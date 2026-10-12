import AccessoryTransportExtension
import ExtensionFoundation

// Signing check only. This probe rejects sessions and never contacts a band.
@main
struct NotificationProbe: AccessoryTransportAppExtension {
    @AppExtensionPoint.Bind
    static var boundExtensionPoint: AppExtensionPoint {
        Identifier("com.apple.accessory-transport-extension")
    }

    func accept(sessionRequest: AccessoryTransportSession.Request) -> AccessoryTransportSession.Request.Decision {
        sessionRequest.reject(error: nil)
    }
}
