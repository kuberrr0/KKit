import Foundation

/// An app using the microphone.
public struct DeviceUser: Identifiable, Hashable, Sendable {
    public var pid: Int32
    public var name: String
    public var bundleID: String?

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, bundleID: String?) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
    }
}

/// Whether the microphone or a camera is in use right now.
public struct DeviceUsage: Sendable, Equatable {
    public var micInUse: Bool
    public var cameraInUse: Bool
    /// Apps capturing audio input, where macOS says (macOS 14+ audio process objects).
    public var micUsers: [DeviceUser]

    public init(micInUse: Bool = false, cameraInUse: Bool = false, micUsers: [DeviceUser] = []) {
        self.micInUse = micInUse
        self.cameraInUse = cameraInUse
        self.micUsers = micUsers
    }

    public static let idle = DeviceUsage()
}

/// Watches microphone and camera use with CoreAudio and CoreMediaIO listeners. No
/// permission is needed to observe. Listeners are only installed while someone
/// subscribes.
@MainActor
public protocol DeviceUsageService: AnyObject {
    var usage: DeviceUsage { get }
    /// The current usage, then every change.
    func updates() -> AsyncStream<DeviceUsage>
}
