import SwiftUI
import ObjectionIQCore

@MainActor
final class NativePractice: ObservableObject {
    @Published var messages: [ConversationMessage] = []
    @Published var draft = ""
    @Published var busy = false
    @Published var status = "Preparing your customer…"
    @Published var error: String?
    @Published var coaching: Coaching?
    @Published var review: TrainingReview?
    @Published var drill: DrillState?
    let kind: TrainingKind
    let settings: PracticeSettings
    private let api: NativeAPI
    private var epoch = UUID()
    private var started = false
    init(api: NativeAPI, settings: PracticeSettings, kind: TrainingKind) { self.api = api; self.settings = settings; self.kind = kind }
    var turnCount: Int { messages.filter { $0.role == "salesperson" }.count }
    var atLimit: Bool { kind == .objection ? turnCount >= (drill?.maxTurns ?? 12) : messages.count >= 43 }
    private var body: [String: Any] {
        var result: [String: Any] = settings.body
        result["messages"] = messages.map { ["role": $0.role, "text": $0.text] }
        return result
    }
    func close() { epoch = UUID() }
    private func perform(_ status: String, action: (UUID) async throws -> Void) async {
        guard !busy else { return }; busy = true; error = nil; self.status = status
        let current = epoch
        do { try await action(current) }
        catch { if current == epoch { self.error = error.localizedDescription } }
        if current == epoch { busy = false; self.status = review != nil ? "Review ready" : "Your turn" }
    }
    func start() async {
        guard !started else { return }
        await perform("Preparing your customer…") { current in
            if kind == .objection {
                let state: DrillState = try await api.request("/api/objections/start", body: settings.body)
                guard current == epoch else { return }; drill = state; messages = state.messages
            } else {
                struct Reply: Decodable { let reply: String }
                let result: Reply = try await api.request("/api/text/reply", body: body)
                guard current == epoch else { return }; messages = [ConversationMessage(role: "customer", text: result.reply)]
            }
            started = true
        }
    }
    func send() async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard started, review == nil, !message.isEmpty, message.count <= 1500, !atLimit else { return }
        await perform("Customer is responding…") { current in
            if kind == .objection {
                guard let drill else { return }
                let result: DrillState = try await api.request("/api/objections/reply", body: ["token": drill.token, "message": message])
                guard current == epoch else { return }; self.drill = result; messages = result.messages
            } else {
                struct Reply: Decodable { let reply: String }
                let next = messages + [ConversationMessage(role: "salesperson", text: message)]
                var payload = body; payload["messages"] = next.map { ["role": $0.role, "text": $0.text] }
                let result: Reply = try await api.request("/api/text/reply", body: payload)
                guard current == epoch else { return }; messages = next + [ConversationMessage(role: "customer", text: result.reply)]
            }
            draft = ""; coaching = nil
        }
    }
    func coach() async {
        guard settings.mode == "coaching", !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, review == nil else { return }
        await perform("Looking at your draft…") { current in
            var payload = body; payload["draft"] = draft
            if kind == .objection { payload = ["token": drill?.token ?? "", "draft": draft] }
            let result: Coaching = try await api.request(kind == .objection ? "/api/objections/coach" : "/api/text/coach", body: payload)
            guard current == epoch else { return }; coaching = result
        }
    }
    func finish() async {
        guard turnCount > 0, review == nil else { return }
        await perform("Reviewing your conversation…") { current in
            let payload: [String: Any] = kind == .objection ? ["token": drill?.token ?? ""] : body
            let result: TrainingReview = try await api.request(kind == .objection ? "/api/objections/finish" : "/api/text/finish", body: payload)
            guard current == epoch else { return }; review = result; coaching = nil
        }
    }
    func retrySave() async {
        guard let token = review?.saveToken else { return }
        await perform("Saving your review…") { current in
            struct Saved: Decodable { let saved: Bool }
            let result: Saved = try await api.request("/api/objections/save", body: ["token": token])
            guard current == epoch else { return }
            if result.saved { review?.saved = true; review?.saveToken = nil; review?.save_warning = nil }
        }
    }
}

@MainActor
struct PracticeScreen: View {
    @StateObject private var practice: NativePractice
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingClose = false
    @State private var confirmingScore = false
    @FocusState private var composing: Bool
    init(api: NativeAPI, settings: PracticeSettings, kind: TrainingKind) {
        _practice = StateObject(wrappedValue: NativePractice(api: api, settings: settings, kind: kind))
    }
    var body: some View {
        NavigationStack {
            Group {
                if let review = practice.review {
                    VStack(spacing: 0) {
                        if let error = practice.error { ErrorBanner(message: error).padding() }
                        if review.saveToken != nil { Button("Retry Saving Review") { Task { await practice.retrySave() } }.disabled(practice.busy).padding() }
                        ReviewScreen(review: review, kind: practice.kind, conversation: practice.messages)
                    }
                } else { conversation }
            }
            .navigationTitle(practice.kind == .objection ? (practice.drill?.customer ?? "Objection Lab") : "Text Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button(practice.review == nil ? "Close" : "Done") {
                    if practice.review != nil { dismiss() } else { confirmingClose = true }
                } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if practice.review == nil { Button("End & Score") { composing = false; confirmingScore = true }.disabled(practice.busy || practice.turnCount == 0) }
                }
            }
            .confirmationDialog("Leave this practice?", isPresented: $confirmingClose, titleVisibility: .visible) {
                Button("Discard Unfinished Practice", role: .destructive) { dismiss() }
            } message: { Text("The unfinished conversation and draft will be cleared. Score it first to save a review.") }
            .confirmationDialog("Finish and score?", isPresented: $confirmingScore, titleVisibility: .visible) {
                Button("End & Score") { Task { await practice.finish() } }
            } message: { Text("Your conversation will end. Any unsent draft is not included in the review.") }
            .interactiveDismissDisabled().task { await practice.start() }.onDisappear { practice.close() }
        }
    }
    private var conversation: some View {
        VStack(spacing: 0) {
            HStack {
                Label(practice.settings.mode == "coaching" ? "Coached" : "Independent", systemImage: practice.kind.icon)
                Spacer()
                Text("\(practice.turnCount) / \(practice.kind == .objection ? (practice.drill?.maxTurns ?? 12) : 21) turns")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.vertical, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(Array(practice.messages.enumerated()), id: \.offset) { _, message in MessageBubble(role: message.role, text: message.text) }
                        if practice.busy { HStack { ProgressView(); Text(practice.status).font(.callout).foregroundStyle(.secondary); Spacer() }.padding() }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding().frame(maxWidth: 800).frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively).onChange(of: practice.messages.count) { _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("latest", anchor: .bottom) }
                }
            }
            if let error = practice.error {
                VStack(alignment: .leading) {
                    ErrorBanner(message: error)
                    if practice.messages.isEmpty { Button("Retry Starting Practice") { Task { await practice.start() } }.disabled(practice.busy) }
                }.padding(.horizontal).padding(.bottom, 8)
            }
            if let coaching = practice.coaching {
                DisclosureGroup("Coach’s suggestion") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(coaching.assessment); if let question = coaching.question { Text(question).italic() }
                        Text(coaching.suggestion).fontWeight(.medium); Text(coaching.reason).foregroundStyle(.secondary)
                        Button("Use in Draft") { practice.draft = coaching.suggestion; composing = true }
                    }.font(.callout).padding(.top, 8)
                }.padding().background(.thinMaterial)
            }
            if practice.atLimit { Text("Practice complete. Choose End & Score for your review.").font(.callout).padding() }
            else {
                VStack(spacing: 8) {
                    HStack(alignment: .bottom, spacing: 12) {
                        TextField("Your response…", text: $practice.draft, axis: .vertical).lineLimit(1...5).focused($composing)
                            .padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                            .disabled(practice.busy || practice.messages.isEmpty)
                        Button { Task { await practice.send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 36)) }
                            .accessibilityLabel("Send response").frame(minWidth: 44, minHeight: 44)
                            .disabled(practice.busy || practice.messages.isEmpty || practice.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || practice.draft.count > 1500)
                    }
                    HStack {
                        if practice.settings.mode == "coaching" { Button("Coach My Draft") { Task { await practice.coach() } }.disabled(practice.busy || practice.messages.isEmpty || practice.draft.isEmpty || practice.draft.count > 1500) }
                        Spacer()
                        Text("\(practice.draft.count) / 1500").foregroundStyle(practice.draft.count > 1500 ? .orange : .secondary)
                    }.font(.caption)
                }.padding().background(.bar)
            }
        }.background(Color(uiColor: .systemGroupedBackground))
    }
}
