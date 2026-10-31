import SwiftUI
import ObjectionIQCore

struct TrainingSetup: View {
    let kind: TrainingKind
    @EnvironmentObject private var session: AppSession
    @State private var settings = PracticeSettings()
    @State private var catalog: ObjectionCatalog?
    @State private var error: String?
    @State private var presenting = false
    var body: some View {
        Form {
            Section { Label(kind.subtitle, systemImage: kind.icon).font(.headline).foregroundStyle(kind.color).padding(.vertical, 10) }
            Section("Your practice") {
                if kind == .objection {
                    if let catalog {
                        Picker("Objection", selection: $settings.topic) {
                            ForEach(catalog.topics.keys.sorted(), id: \.self) { key in Text(catalog.topics[key]?.label ?? key).tag(key) }
                            Text("Surprise me").tag("random")
                        }
                        if let goal = catalog.topics[settings.topic]?.goal { Text(goal).font(.callout).foregroundStyle(.secondary) }
                    } else if let error { ErrorBanner(message: error); Button("Retry") { Task { await loadCatalog() } } }
                    else { ProgressView("Loading objections…") }
                    Picker("Challenge", selection: $settings.challenge) { Text("Focused").tag("focused"); Text("Progressive").tag("progressive") }
                } else {
                    Picker("Scenario", selection: $settings.scenario) {
                        ForEach(scenarioOptions.filter { kind == .phone || !["cold", "service", "random"].contains($0.0) }, id: \.0) { Text($0.1).tag($0.0) }
                        if kind == .text { Text("Missed appointment").tag("noshow") }
                    }
                }
                Picker("Difficulty", selection: $settings.difficulty) { Text("Easy").tag("easy"); Text("Realistic").tag("realistic"); Text("Hard").tag("hard") }
                Picker("Customer language", selection: $settings.language) { Text("English").tag("en"); Text("Español").tag("es") }
                if kind != .phone { Picker("Support", selection: $settings.mode) { Text("Independent").tag("practice"); Text("Coached").tag("coaching") } }
            }
            Section {
                Button { presenting = true } label: {
                    Label(kind == .phone ? "Start Call" : "Start Practice", systemImage: kind.icon).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(.borderedProminent).listRowBackground(Color.clear).disabled(kind == .objection && catalog == nil)
            } footer: {
                Text(kind == .phone ? "Microphone access is requested when you start. Calls end when the app goes into the background." : "Practice uses fictional customers. Coaching and reviews are in English; the customer follows your language choice. Unfinished practice stays on this screen until you close it.")
            }
            Section { Text("Use fictional deal details. Keep real customer and financial information out of practice.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle(kind.title)
            .task { if kind == .objection { await loadCatalog() } }
            .fullScreenCover(isPresented: $presenting, onDismiss: { Task { await session.loadHistory() } }) {
                if kind == .phone { CallScreen(api: session.api, settings: settings) }
                else { PracticeScreen(api: session.api, settings: settings, kind: kind) }
            }
    }
    private func loadCatalog() async {
        error = nil
        do { catalog = try await session.api.request("/api/objections/catalog") }
        catch { self.error = error.localizedDescription }
    }
}
