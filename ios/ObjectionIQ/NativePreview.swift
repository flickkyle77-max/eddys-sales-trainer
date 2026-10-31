#if DEBUG
import SwiftUI
import ObjectionIQCore

/// Offline screenshots use the real screen components and synthetic records only.
/// This entry point is removed from Release builds and never restores credentials or contacts a server.
@MainActor
struct NativePreview: View {
    let mode: String
    @StateObject private var session: AppSession
    init(mode: String) {
        self.mode = mode
        let session = AppSession(server: try! ServerOrigin("https://preview.invalid"))
        session.phase = .signedIn
        session.email = "practice@example.test"
        let fixture = """
        [{"created_at":"2026-10-31T12:00:00Z","scenario":"objection_price","difficulty":"realistic","language":"en","mode":"practice","total_score":78,"scores":{"acknowledge":12,"discover":20,"respond":19,"trust":12,"next_step":15,"_review":{"real_concern":"The customer needs a complete written comparison, including fees.","next_drill":"Practice comparing two complete offers."}},"outcome":"The customer agreed to review an itemized quote.","strength":"You asked what the customer was comparing.","improvement":"Confirm that both quotes include the same equipment and fees.","example":"What is included in the other offer? Let’s make sure we are comparing the same vehicle and total.","conversation":[{"role":"customer","text":"Your price is higher than I expected. Why would I pay that?"},{"role":"salesperson","text":"I understand. What are you comparing it with?"}]},
        {"created_at":"2026-10-30T12:00:00Z","scenario":"internet","difficulty":"realistic","language":"en","total_score":72,"opening":10,"rapport":11,"discovery":15,"objections":14,"appointment":14,"closing":8},
        {"created_at":"2026-10-29T12:00:00Z","scenario":"marketplace","difficulty":"easy","language":"es","mode":"coaching","total_score":68,"scores":{"tone":15,"clarity":10,"rapport":11,"discovery":10,"objections":10,"appointment":12}}]
        """
        session.history = (try? JSONDecoder().decode([SavedSession].self, from: Data(fixture.utf8))) ?? []
        _session = StateObject(wrappedValue: session)
    }
    var body: some View {
        Group {
            if mode == "review", let item = session.history.first { NavigationStack { SavedReviewScreen(item: item) } }
            else if mode == "setup" { NavigationStack { TrainingSetup(kind: .phone) } }
            else {
                TabView(selection: .constant(mode == "progress" ? 1 : 0)) {
                    NavigationStack { TrainingHome() }.tabItem { Label("Train", systemImage: "square.grid.2x2.fill") }.tag(0)
                    NavigationStack { ProgressScreen() }.tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag(1)
                    NavigationStack { AccountScreen() }.tabItem { Label("Account", systemImage: "person.crop.circle") }.tag(2)
                }
            }
        }.environmentObject(session).tint(.teal)
    }
}
#endif
