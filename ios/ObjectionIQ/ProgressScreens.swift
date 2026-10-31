import SwiftUI
import Charts
import ObjectionIQCore

struct TrainingHome: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your next great conversation starts here.").font(.title2.bold())
                    Text("Choose a skill. Practice it. Put it to work.").foregroundStyle(.secondary)
                }.padding(.top, 12)
                ForEach([TrainingKind.phone, .objection, .text]) { kind in
                    NavigationLink { TrainingSetup(kind: kind) } label: {
                        HStack(spacing: 18) {
                            Image(systemName: kind.icon).font(.title2).foregroundStyle(kind.color)
                                .frame(width: 56, height: 56).background(kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(kind.title).font(.headline).foregroundStyle(.primary)
                                Text(kind.subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    }.buttonStyle(.plain)
                }
                HStack { Text("Recent activity").font(.title3.bold()); Spacer(); if session.historyLoading { ProgressView() } }
                if let error = session.historyError { ErrorBanner(message: error) }
                if session.history.isEmpty {
                    Text("Complete your first session to see your feedback here.").foregroundStyle(.secondary).padding(.vertical)
                } else {
                    ForEach(session.history.prefix(3)) { item in
                        NavigationLink { SavedReviewScreen(item: item) } label: { HistoryRow(item: item) }.buttonStyle(.plain)
                    }
                }
            }.padding(20).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("ObjectionIQ").refreshable { await session.loadHistory() }
    }
}

struct ProgressScreen: View {
    @EnvironmentObject private var session: AppSession
    @State private var filter = "All"
    private var shown: [SavedSession] { session.history.filter { filter == "All" || $0.kind == filter } }
    var body: some View {
        List {
            Section {
                Picker("Training type", selection: $filter) { ForEach(["All", "Phone", "Objection Lab", "Text"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
                if !shown.isEmpty {
                    HStack {
                        VStack(alignment: .leading) { Text("\(shown.count)").font(.largeTitle.bold()); Text("Recent sessions").foregroundStyle(.secondary) }
                        Spacer()
                        VStack(alignment: .trailing) { Text("\(shown.map(\.total_score).reduce(0,+) / shown.count)").font(.largeTitle.bold()); Text("Average / 100").foregroundStyle(.secondary) }
                    }.padding(.vertical, 10).accessibilityElement(children: .combine)
                }
            } footer: { Text("Shows up to 30 phone and 30 text/objection sessions from your saved history.") }
            if shown.count > 1 {
                Section("Last 12 scores") {
                    Chart(Array(shown.prefix(12).reversed().enumerated()), id: \.offset) { index, item in
                        LineMark(x: .value("Session", index + 1), y: .value("Score", item.total_score)).foregroundStyle(.teal)
                        PointMark(x: .value("Session", index + 1), y: .value("Score", item.total_score)).foregroundStyle(.teal)
                    }.chartYScale(domain: 0...100).chartXAxisLabel("Oldest → newest").frame(height: 180).padding(.vertical, 8)
                }
            }
            if let error = session.historyError { Section { ErrorBanner(message: error) } }
            Section("Saved reviews") {
                if session.historyLoading { ProgressView("Refreshing…") }
                if shown.isEmpty { Text("No saved sessions for this training type yet.").foregroundStyle(.secondary) }
                ForEach(shown) { item in NavigationLink { SavedReviewScreen(item: item) } label: { HistoryRow(item: item) } }
            }
        }.navigationTitle("Your Progress").refreshable { await session.loadHistory() }
    }
}

struct HistoryRow: View {
    let item: SavedSession
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(scenarioTitle(item.scenario)).font(.headline)
                Text("\(item.kind) · \(item.language == "es" ? "Español" : "English")").font(.caption).foregroundStyle(.secondary)
                Text(item.created_at.prefix(10)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(item.total_score)").font(.title2.bold().monospacedDigit()).foregroundStyle(.teal)
                .accessibilityLabel("\(item.total_score) out of 100")
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}

struct SavedReviewScreen: View {
    let item: SavedSession
    var body: some View {
        ReviewScreen(review: item.review, kind: item.kind == "Phone" ? .phone : item.kind == "Text" ? .text : .objection,
                     conversation: item.conversation ?? [])
            .navigationTitle(scenarioTitle(item.scenario)).navigationBarTitleDisplayMode(.inline)
    }
}

struct AccountScreen: View {
    @EnvironmentObject private var session: AppSession
    @State private var confirming = false
    var body: some View {
        Form {
            Section("Signed in") { Label(session.email, systemImage: "person.crop.circle.fill").textSelection(.enabled) }
            Section("Training") {
                Label("Your web and app history stay together", systemImage: "arrow.triangle.2.circlepath")
                Text("Unfinished conversations stay in memory until you close them. Completed scores are saved to your account when the server confirms the save.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Audio") {
                Button("Microphone Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Text("Calls use the microphone only while training. Backgrounding the app ends the call; the available transcript can still be scored when you return.").font(.footnote).foregroundStyle(.secondary)
            }
            Section { Button("Sign Out", role: .destructive) { confirming = true } }
            Section { Text("ObjectionIQ \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").foregroundStyle(.secondary) }
        }.navigationTitle("Account").confirmationDialog("Sign out on this device?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { session.signOut() }
        }
    }
}

struct ReviewScreen: View {
    let review: TrainingReview
    let kind: TrainingKind
    var conversation: [ConversationMessage] = []
    private var maxima: [String: Int] {
        switch kind {
        case .phone: return ["opening":15,"rapport":15,"discovery":20,"objections":20,"appointment":20,"closing":10]
        case .text: return ["tone":20,"clarity":15,"rapport":15,"discovery":15,"objections":15,"appointment":20]
        case .objection: return ["acknowledge":15,"discover":25,"respond":25,"trust":15,"next_step":20]
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Color.teal.opacity(0.12), lineWidth: 14)
                        Circle().trim(from: 0, to: CGFloat(min(100, max(0, review.total ?? 0))) / 100)
                            .stroke(Color.teal, style: StrokeStyle(lineWidth: 14, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 0) { Text("\(review.total ?? 0)").font(.system(size: 54, weight: .bold, design: .rounded)); Text("out of 100").font(.caption).foregroundStyle(.secondary) }
                    }.frame(width: 164, height: 164).padding(12).accessibilityElement(children: .ignore).accessibilityLabel("Score: \(review.total ?? 0) out of 100")
                    Text("Practice Review").font(.title2.bold())
                    if let mode = review.mode { Text(mode == "coaching" ? "Coached practice" : "Independent practice").font(.subheadline).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity)
                if let warning = review.save_warning { ErrorBanner(message: warning) }
                feedback("Outcome", review.outcome)
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(review.dimensions, id: \.key) { dimension in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(dimension.key.replacingOccurrences(of: "_", with: " ").capitalized); Spacer(); Text("\(dimension.value) / \(maxima[dimension.key] ?? 100)").bold() }.font(.subheadline)
                            ProgressView(value: Double(dimension.value), total: Double(maxima[dimension.key] ?? 100)).tint(kind.color)
                            if let detail = review.feedback?[dimension.key] {
                                DisclosureGroup("Evidence & coaching") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if !detail.quote.isEmpty { Text("“\(detail.quote)”").italic() }
                                        Text(detail.evidence); Text(detail.advice).foregroundStyle(.secondary)
                                    }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                                }.font(.caption)
                            }
                        }
                    }
                }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                feedback("Keep doing", review.strength)
                feedback("Work on next", review.improvement)
                feedback("Try saying", review.example)
                feedback("The concern behind the objection", review.real_concern)
                feedback("Your next drill", review.next_drill)
                feedback("About this review", review.notes)
                if !conversation.isEmpty {
                    DisclosureGroup("Conversation") { ForEach(Array(conversation.enumerated()), id: \.offset) { _, message in MessageBubble(role: message.role, text: message.text) } }
                }
                Text("Scores reflect this practice conversation. Review the evidence with your manager and use the feedback to choose your next practice.").font(.footnote).foregroundStyle(.secondary)
            }.padding(22).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.background(Color(uiColor: .systemGroupedBackground)).textSelection(.enabled)
    }
    @ViewBuilder private func feedback(_ title: String, _ text: String?) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); Text(text).foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MessageBubble: View {
    let role: String
    let text: String
    private var isUser: Bool { role == "salesperson" || role == "Salesperson" }
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 6) {
                Text(isUser ? "YOU" : "CUSTOMER").font(.caption2.bold()).foregroundStyle(.secondary)
                Text(text).textSelection(.enabled)
            }.padding(16).background(isUser ? Color.teal.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            if !isUser { Spacer(minLength: 32) }
        }.accessibilityElement(children: .combine)
    }
}
