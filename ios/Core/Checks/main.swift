import Foundation
import ObjectionIQCore

var count = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    count += 1
    guard condition() else { fatalError("Policy check failed: \(message)") }
}
func rejects(_ value: String) {
    count += 1
    do {
        _ = try ServerOrigin(value)
        fatalError("Unsafe server configuration was accepted: \(value)")
    } catch ServerOrigin.ConfigurationError.invalidServerURL {
        // Expected: invalid configurations must fail before a web view is loaded.
    } catch {
        fatalError("Unexpected validation failure: \(error)")
    }
}

let origin = try ServerOrigin("  https://TRAINING.example.test  ")
check(origin.url.absoluteString == "https://training.example.test/", "normalized HTTPS root")
check(origin.port == 443, "default HTTPS port")
for value in ["", "training.example.test", "http://training.example.test", "file:///index.html",
              "https://user:password@training.example.test", "https://training.example.test/app",
              "https://training.example.test:0", "https://training.example.test?redirect=other", "https://training.example.test/#anything"] {
    rejects(value)
}
check(origin.contains(URL(string: "https://training.example.test/api/session")), "same-origin API path")
check(origin.contains(URL(string: "https://TRAINING.example.test:443/?mode=phone")), "explicit HTTPS port")
for value in ["http://training.example.test/", "https://training.example.test.attacker.test/",
              "https://other.example.test/", "https://training.example.test:444/",
              "https://user@training.example.test/", "https://training.example.test:0/"] {
    check(!origin.contains(URL(string: value)), "reject untrusted navigation: \(value)")
}
check(!origin.contains(nil), "reject missing URL")
check(origin.matches(scheme: "https", host: "training.example.test", port: 0), "WebKit default port")
let custom = try ServerOrigin("https://training.example.test:8443")
check(custom.matches(scheme: "https", host: "training.example.test", port: 8443), "explicit configured port")
check(!custom.matches(scheme: "https", host: "training.example.test", port: 0), "no custom-port downgrade")

func mayCapture(host: String = "training.example.test", frame: String = "training.example.test",
                main: Bool = true, device: ServerOrigin.CaptureDevice = .microphone,
                current: String = "https://training.example.test/") -> Bool {
    origin.permitsMicrophoneRequest(
        scheme: "https", host: host, port: 443,
        frameScheme: "https", frameHost: frame, framePort: 443,
        isMainFrame: main, device: device, currentURL: URL(string: current))
}
check(mayCapture(), "trusted microphone request reaches iOS consent")
check(!mayCapture(host: "untrusted.example.test"), "untrusted requester denied")
check(!mayCapture(frame: "untrusted.example.test"), "untrusted frame denied")
check(!mayCapture(main: false), "embedded frame denied")
check(!mayCapture(device: .camera), "camera denied")
check(!mayCapture(device: .cameraAndMicrophone), "combined capture denied")
check(!mayCapture(device: .unknown), "unknown device denied")
check(!mayCapture(current: "https://untrusted.example.test/"), "navigation away revokes capture eligibility")
print("\(count) Swift permission-policy checks passed.")
