import SwiftUI
import ObjectionIQCore

@MainActor
struct TrainingView: View {
    @StateObject private var session: AppSession
    init(server: ServerOrigin) { _session = StateObject(wrappedValue: AppSession(server: server)) }
    var body: some View {
        Group {
            switch session.phase {
            case .checking:
                VStack(spacing: 20) {
                    BrandMark()
                    if let error = session.checkingError {
                        Text(error).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Try Again") { Task { await session.restore() } }.buttonStyle(.borderedProminent)
                        Button("Return to Sign In") { session.api.clear(); session.reset() }
                    } else { ProgressView("Opening your training…") }
                }.padding(32)
            case .signedOut: SignInView()
            case .signedIn:
                TabView {
                    NavigationStack { TrainingHome() }.tabItem { Label("Train", systemImage: "square.grid.2x2.fill") }
                    NavigationStack { ProgressScreen() }.tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                    NavigationStack { AccountScreen() }.tabItem { Label("Account", systemImage: "person.crop.circle") }
                }
            }
        }.environmentObject(session).tint(.teal).task { await session.restore() }
    }
}

struct BrandMark: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 42, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
                .accessibilityHidden(true)
            Text("ObjectionIQ").font(.largeTitle.bold())
        }
    }
}

private struct SignInView: View {
    @EnvironmentObject private var session: AppSession
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Field?
    private enum Field { case email, password }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    BrandMark().frame(maxWidth: .infinity).padding(.top, 36)
                    Text("Build confidence. One conversation at a time.").font(.title2.weight(.medium)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Sign in to your training account").font(.headline)
                        TextField("Email", text: $email).textContentType(.username).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .email)
                            .submitLabel(.next).onSubmit { focused = .password }.padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        SecureField("Password", text: $password).textContentType(.password).focused($focused, equals: .password)
                            .submitLabel(.go).onSubmit(signIn).padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        if let error { ErrorBanner(message: error) }
                        Button(action: signIn) {
                            HStack { if busy { ProgressView().tint(.white) }; Text(busy ? "Signing in…" : "Sign In").fontWeight(.semibold) }.frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).disabled(busy || email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                    }.padding(22).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    Text("Use the same account as your web training. Need access or a password reset? Contact your team administrator.").font(.footnote).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }.background(Color(uiColor: .systemGroupedBackground)).scrollDismissesKeyboard(.interactively)
        }
    }
    private func signIn() {
        guard !busy, !password.isEmpty else { return }; busy = true; error = nil; focused = nil
        Task {
            do { try await session.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password); password = "" }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill").font(.callout).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14)).accessibilityElement(children: .combine)
    }
}

enum TrainingKind: String, Identifiable {
    case phone, objection, text
    var id: String { rawValue }
    var title: String { switch self { case .phone: return "Phone Training"; case .objection: return "Objection Lab"; case .text: return "Text Training" } }
    var icon: String { switch self { case .phone: return "phone.fill"; case .objection: return "target"; case .text: return "message.fill" } }
    var color: Color { switch self { case .phone: return .teal; case .objection: return .indigo; case .text: return .blue } }
    var subtitle: String { switch self { case .phone: return "Practice a live customer conversation"; case .objection: return "Find the concern. Earn the next step."; case .text: return "Write messages that move things forward" } }
}

let scenarioOptions: [(String, String)] = [
    ("internet", "Internet lead"), ("unsold", "Unsold follow-up"), ("cold", "Cold call"),
    ("upgrade", "Customer upgrade"), ("price", "Price shopper"), ("marketplace", "Marketplace lead"),
    ("service", "Service upgrade"), ("random", "Surprise scenario")
]
func scenarioTitle(_ key: String) -> String {
    let titles = ["payment": "Monthly payment", "trade": "Trade value", "think": "Need to think", "spouse": "Talk to my spouse", "competitor": "Competitor offer", "credit": "Credit worries", "time": "No time to visit", "otd": "Out-the-door price", "down": "Down payment", "rate": "Interest rate", "warranty": "Warranty concerns", "price": "Price is too high", "noshow": "Missed appointment"]
    if key.hasPrefix("objection_") { let topic = String(key.dropFirst(10)); return titles[topic] ?? topic.capitalized }
    return scenarioOptions.first { $0.0 == key }?.1 ?? titles[key] ?? key.capitalized
}
