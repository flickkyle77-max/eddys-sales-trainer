import AVFoundation
import Combine
import Foundation
import UIKit
import WebKit
import ObjectionIQCore

struct TrainingFailure {
    let title: String
    let message: String
}

struct TrainingDialog: Identifiable {
    let id = UUID()
    let message: String
    let requiresConfirmation: Bool
    let resolve: (Bool) -> Void
}

@MainActor
final class TrainingBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let server: ServerOrigin
    @Published var isLoading = true
    @Published var failure: TrainingFailure?
    @Published var dialog: TrainingDialog?
    private var started = false

    // Always load the real HTTPS document. Bundled file/data/HTML origins cannot
    // stand in for the secure website's getUserMedia context or cookie origin.
    lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 11/255, green: 16/255, blue: 24/255, alpha: 1)
        view.scrollView.backgroundColor = view.backgroundColor
        view.allowsBackForwardNavigationGestures = false
        view.accessibilityLabel = "ObjectionIQ training"
        return view
    }()

    init(server: ServerOrigin) {
        self.server = server
        super.init()
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        reload()
    }

    func reload() {
        failure = nil
        isLoading = true
        // A sleeping host may need time to wake. Preserve the trusted HTTPS origin.
        webView.load(URLRequest(url: server.url, timeoutInterval: 90))
    }

    func openInSafari() {
        UIApplication.shared.open(server.url)
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        failure = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showLoadingFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadingFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoading = false
        failure = TrainingFailure(title: "Training was interrupted", message: "The app's browser stopped. Reload to reconnect. An unfinished practice session will need to be restarted.")
    }

    private func showLoadingFailure(_ error: Error) {
        let issue = error as NSError
        guard issue.domain != NSURLErrorDomain || issue.code != NSURLErrorCancelled else { return }
        isLoading = false
        let message: String
        if issue.domain == NSURLErrorDomain && issue.code == NSURLErrorNotConnectedToInternet {
            message = "Check your internet connection, then try again."
        } else if issue.domain == NSURLErrorDomain && issue.code == NSURLErrorTimedOut {
            message = "The training server took too long to respond. It may be waking up. Try again shortly."
        } else {
            message = "The secure training page could not be loaded. Try again, or open it in Safari to check the connection."
        }
        failure = TrainingFailure(title: "Couldn't load training", message: message)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if server.contains(url) {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
            return
        }
        // Only an explicit tap may open a different HTTPS website outside this app.
        // Script redirects and arbitrary schemes never acquire trusted-origin privileges.
        if navigationAction.navigationType == .linkActivated && url.scheme?.lowercased() == "https" {
            UIApplication.shared.open(url)
        } else if navigationAction.targetFrame?.isMainFrame == true {
            isLoading = false
            failure = TrainingFailure(title: "Unexpected training address", message: "The page tried to leave this app's configured server. Contact your administrator if the server address has changed.")
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame,
           let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
            isLoading = false
            failure = TrainingFailure(title: "Training is temporarily unavailable", message: "The server returned an error. Try again shortly.")
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let device: ServerOrigin.CaptureDevice
        switch type {
        case .microphone: device = .microphone
        case .camera: device = .camera
        case .cameraAndMicrophone: device = .cameraAndMicrophone
        @unknown default: device = .unknown
        }
        let frameOrigin = frame.securityOrigin
        guard server.permitsMicrophoneRequest(
            scheme: origin.protocol, host: origin.host, port: origin.port,
            frameScheme: frameOrigin.protocol, frameHost: frameOrigin.host, framePort: frameOrigin.port,
            isMainFrame: frame.isMainFrame, device: device, currentURL: webView.url
        ) else { decisionHandler(.deny); return }

        // This runs only when Phone Training calls getUserMedia after Start Call.
        // WebKit permission is separate from the application's iOS permission.
        let finish: (Bool) -> Void = { [weak self, weak webView] granted in
            DispatchQueue.main.async {
                guard let self, let webView, self.server.contains(webView.url) else {
                    decisionHandler(.deny)
                    return
                }
                decisionHandler(granted ? .grant : .deny)
            }
        }
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: finish)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(finish)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard dialog == nil else { completionHandler(); return }
        dialog = TrainingDialog(message: String(message.prefix(3000)), requiresConfirmation: false,
                                resolve: { _ in completionHandler() })
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard dialog == nil else { completionHandler(false); return }
        dialog = TrainingDialog(message: String(message.prefix(3000)), requiresConfirmation: true,
                                resolve: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        completionHandler(nil)
    }
}
