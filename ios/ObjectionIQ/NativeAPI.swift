import Foundation
import Security
import Combine
import ObjectionIQCore

enum TrainerError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

private final class OriginRedirectPolicy: NSObject, URLSessionTaskDelegate {
    let server: ServerOrigin
    init(server: ServerOrigin) { self.server = server }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(server.contains(request.url) ? request : nil)
    }
}

/// Credentials are device-only Keychain items. No password, OpenAI key, or Supabase service key is stored in the app.
private struct CookieVault {
    let account: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "ObjectionIQ") + ".session",
         kSecAttrAccount as String: account]
    }
    func read() throws -> Data? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TrainerError.message("Unlock this device and try opening ObjectionIQ again.") }
        return result as? Data
    }
    func write(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data,
                                       kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let add = query.merging(attributes) { _, new in new }
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw TrainerError.message("Could not securely save your sign-in on this device.") }
        } else if status != errSecSuccess { throw TrainerError.message("Could not securely update your sign-in. Please try again.") }
    }
    func remove() { SecItemDelete(query as CFDictionary) }
}

@MainActor
final class NativeAPI {
    private struct StoredCookie: Codable { let name: String; let value: String; let expires: Date? }
    let server: ServerOrigin
    private let vault: CookieVault
    private let policy: OriginRedirectPolicy
    private var session: URLSession
    private var generation = UUID()
    var onAuthenticationExpired: (() -> Void)?

    init(server: ServerOrigin) {
        self.server = server
        vault = CookieVault(account: server.url.absoluteString)
        policy = OriginRedirectPolicy(server: server)
        session = Self.makeSession(delegate: policy)
    }
    private static func makeSession(delegate: OriginRedirectPolicy) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .onlyFromMainDocumentDomain
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 100
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
    func restore() throws {
        guard let data = try vault.read() else { return }
        for stored in try JSONDecoder().decode([StoredCookie].self, from: data) {
            guard ["trainer_access", "trainer_refresh"].contains(stored.name), stored.expires.map({ $0 > Date() }) ?? true else { continue }
            var properties: [HTTPCookiePropertyKey: Any] = [.name: stored.name, .value: stored.value,
                                                           .domain: server.host, .path: "/", .secure: "TRUE"]
            if let expires = stored.expires { properties[.expires] = expires }
            if let cookie = HTTPCookie(properties: properties) { session.configuration.httpCookieStorage?.setCookie(cookie) }
        }
    }
    private func persist() throws {
        let cookies = session.configuration.httpCookieStorage?.cookies(for: server.url) ?? []
        let stored = cookies.filter { ["trainer_access", "trainer_refresh"].contains($0.name) }
            .map { StoredCookie(name: $0.name, value: $0.value, expires: $0.expiresDate) }
        if stored.isEmpty { vault.remove() } else { try vault.write(JSONEncoder().encode(stored)) }
    }
    func clear() {
        generation = UUID()
        session.invalidateAndCancel()
        session.configuration.httpCookieStorage?.cookies?.forEach { session.configuration.httpCookieStorage?.deleteCookie($0) }
        vault.remove()
        session = Self.makeSession(delegate: policy)
    }
    func signOut() {
        let old = session
        var request = URLRequest(url: server.url.appendingPathComponent("api/logout"))
        request.httpMethod = "POST"
        // Capture the existing Cookie header before deleting the local credentials.
        let cookies = old.configuration.httpCookieStorage?.cookies(for: server.url) ?? []
        request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: cookies)
        clear()
        let configuration = URLSessionConfiguration.ephemeral
        let logoutSession = URLSession(configuration: configuration, delegate: policy, delegateQueue: nil)
        Task { _ = try? await logoutSession.data(for: request); logoutSession.finishTasksAndInvalidate() }
    }
    func data(_ path: String, body: [String: Any]? = nil) async throws -> Data {
        let epoch = generation
        guard path.hasPrefix("/api/"), let url = URL(string: path, relativeTo: server.url)?.absoluteURL,
              server.contains(url) else { throw TrainerError.message("Invalid training endpoint.") }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard generation == epoch else { throw CancellationError() }
        guard let response = response as? HTTPURLResponse, server.contains(response.url) else { throw TrainerError.message("The training server returned an unexpected response.") }
        guard (200...299).contains(response.statusCode) else {
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
            if response.statusCode == 401, path != "/api/login", message?.hasPrefix("This drill") != true {
                clear(); onAuthenticationExpired?()
            }
            throw TrainerError.message(message ?? "The server is unavailable (\(response.statusCode)). Please try again.")
        }
        try persist()
        return data
    }
    func request<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        try JSONDecoder().decode(T.self, from: await data(path, body: body))
    }
}

@MainActor
final class AppSession: ObservableObject {
    enum Phase: Equatable { case checking, signedOut, signedIn }
    @Published var phase = Phase.checking
    @Published var email = ""
    @Published var history: [SavedSession] = []
    @Published var historyError: String?
    @Published var checkingError: String?
    @Published var historyLoading = false
    let api: NativeAPI
    private var epoch = UUID()
    init(server: ServerOrigin) {
        api = NativeAPI(server: server)
        api.onAuthenticationExpired = { [weak self] in self?.reset() }
    }
    private struct Identity: Decodable { let name: String }
    func restore() async {
        let current = epoch; checkingError = nil
        do {
            try api.restore()
            let user: Identity = try await api.request("/api/me")
            guard epoch == current else { return }
            email = user.name; phase = .signedIn
            await loadHistory()
        } catch {
            guard epoch == current, phase == .checking else { return }
            checkingError = error.localizedDescription
        }
    }
    func login(email: String, password: String) async throws {
        let current = epoch
        let user: Identity = try await api.request("/api/login", body: ["email": email, "password": password])
        guard current == epoch else { throw CancellationError() }
        self.email = user.name; phase = .signedIn
        await loadHistory()
    }
    func signOut() { api.signOut(); reset() }
    func reset() { epoch = UUID(); email = ""; history = []; historyError = nil; historyLoading = false; phase = .signedOut }
    func loadHistory() async {
        guard phase == .signedIn, !historyLoading else { return }
        let current = epoch; historyLoading = true; historyError = nil
        // Keep whichever history succeeds, and explicitly indicate a partial load.
        var loaded: [SavedSession] = []; var failures = 0
        for path in ["/api/history", "/api/text/history"] {
            do { let records: [SavedSession] = try await api.request(path); loaded += records }
            catch { failures += 1 }
            guard current == epoch else { return }
        }
        history = loaded.sorted { $0.created_at > $1.created_at }
        historyError = failures > 0 ? "Some history could not be loaded. Pull to refresh and try again." : nil
        historyLoading = false
    }
}
