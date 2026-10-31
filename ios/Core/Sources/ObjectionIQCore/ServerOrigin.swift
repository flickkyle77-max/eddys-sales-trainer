import Foundation

/// The one HTTPS origin this build may load and authorize for microphone capture.
public struct ServerOrigin: Equatable, Sendable {
    public enum ConfigurationError: Error { case invalidServerURL }
    public let url: URL
    public let host: String
    public let port: Int

    public init(_ value: String) throws {
        guard var parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https",
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port == nil || (1...65535).contains(parts.port!)
        else { throw ConfigurationError.invalidServerURL }
        parts.scheme = "https"
        parts.host = host
        parts.path = "/"
        guard let url = parts.url else { throw ConfigurationError.invalidServerURL }
        self.url = url
        self.host = host
        self.port = parts.port ?? 443
    }

    public func contains(_ candidate: URL?) -> Bool {
        guard let candidate, candidate.user == nil, candidate.password == nil,
              let scheme = candidate.scheme, let host = candidate.host else { return false }
        if let port = candidate.port, !(1...65535).contains(port) { return false }
        return matches(scheme: scheme, host: host, port: candidate.port ?? 443)
    }

    /// WebKit can report a default HTTPS port as either 0 or 443.
    public func matches(scheme: String, host: String, port: Int) -> Bool {
        scheme.lowercased() == "https" && host.lowercased() == self.host &&
            (port == 0 ? 443 : port) == self.port
    }

    public enum CaptureDevice: Equatable, Sendable { case microphone, camera, cameraAndMicrophone, unknown }

    /// A microphone request must originate in the trusted top-level document.
    /// iOS consent is checked separately by the application, after this policy succeeds.
    public func permitsMicrophoneRequest(
        scheme: String, host: String, port: Int,
        frameScheme: String, frameHost: String, framePort: Int,
        isMainFrame: Bool, device: CaptureDevice, currentURL: URL?
    ) -> Bool {
        device == .microphone && isMainFrame && contains(currentURL) &&
            matches(scheme: scheme, host: host, port: port) &&
            matches(scheme: frameScheme, host: frameHost, port: framePort)
    }
}
