import SwiftUI
import AVFoundation
import ObjectionIQCore

@MainActor
struct CallScreen: View {
    @StateObject private var call: NativeCall
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingClose = false
    @State private var finishing = false
    @State private var showTranscript = false
    init(api: NativeAPI, settings: PracticeSettings) { _call = StateObject(wrappedValue: NativeCall(api: api, settings: settings)) }
    var body: some View {
        NavigationStack {
            Group {
                if let review = call.review { ReviewScreen(review: review, kind: .phone, conversation: call.transcript.turns.map { ConversationMessage(role: $0.speaker, text: $0.text) }) }
                else { liveCall }
            }.navigationTitle(call.review == nil ? "Practice Call" : "Call Review").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(call.review == nil ? "Close" : "Done") {
                    if call.review == nil { confirmingClose = true } else { dismiss() }
                }.disabled(finishing || call.stage == .scoring) } }
                .confirmationDialog("Leave this call?", isPresented: $confirmingClose, titleVisibility: .visible) {
                    Button("End Without Scoring", role: .destructive) { call.stop(); dismiss() }
                } message: { Text("The unfinished call and transcript will be cleared.") }
                .sheet(isPresented: $showTranscript) { transcriptSheet }
                .interactiveDismissDisabled()
                .task { await call.start() }
                .onDisappear { call.stop() }
                .onChange(of: scenePhase) { phase in
                    if phase == .background, call.isLive { call.stop(reason: "The call ended when ObjectionIQ moved to the background. You can score the available transcript.") }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
                    if let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                       AVAudioSession.InterruptionType(rawValue: raw) == .began, call.isLive {
                        call.stop(reason: "Another audio session interrupted this call. You can score the available transcript.")
                    }
                }
        }
    }
    private var liveCall: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 100)).foregroundStyle(.teal).accessibilityHidden(true).padding(.top, 22)
                VStack(spacing: 8) {
                    Text(scenarioTitle(call.settings.scenario)).font(.title.bold()).multilineTextAlignment(.center)
                    Text("\(call.settings.difficulty.capitalized) · \(call.settings.language == "es" ? "Español" : "English")").foregroundStyle(.secondary)
                    Text(call.status).font(.callout).foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = Int(max(0, (call.endedAt ?? context.date).timeIntervalSince(call.connectedAt ?? context.date)))
                        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).font(.system(.largeTitle, design: .monospaced))
                    }
                }
                if call.stage == .connecting || call.stage == .scoring || finishing { ProgressView(call.stage == .scoring ? "Preparing your review…" : finishing ? "Finishing captions…" : "Connecting…") }
                if let error = call.error { ErrorBanner(message: error) }
                HStack(spacing: 32) {
                    callControl(call.muted ? "Unmute" : "Mute", icon: call.muted ? "mic.slash.fill" : "mic.fill", selected: call.muted) { call.setMuted(!call.muted) }
                    callControl(call.speaker ? "Speaker on" : "System audio", icon: call.speaker ? "speaker.wave.3.fill" : "ear", selected: call.speaker) { call.toggleSpeaker() }
                    callControl("Transcript", icon: "text.bubble", selected: false) { showTranscript = true }
                }.disabled(call.stage != .connected || finishing)
                if call.stage == .connected || call.stage == .ended {
                    Button { finish() } label: {
                        Label(call.stage == .ended ? "Score Conversation" : "End & Score", systemImage: "phone.down.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(.borderedProminent).tint(call.stage == .ended ? .teal : .red)
                        .disabled(finishing || (call.stage == .ended && !call.transcript.canScore))
                }
                if call.stage == .ended {
                    Button("View Available Transcript") { showTranscript = true }
                    Button("Back to Training") { dismiss() }
                }
                Text("Fictional customer · Live practice").font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(Color(uiColor: .systemGroupedBackground))
    }
    private func finish() {
        guard !finishing else { return }; finishing = true
        Task { await call.endAndScore(); finishing = false }
    }
    private func callControl(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.title2).frame(width: 60, height: 60)
                    .background(selected ? Color.teal.opacity(0.18) : Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                Text(title).font(.caption).multilineTextAlignment(.center)
            }
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
    private var transcriptSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    Text("Live captions may contain recognition errors. Only completed turns appear here.").font(.footnote).foregroundStyle(.secondary)
                    if call.transcript.turns.isEmpty { Text("Your conversation will appear here as you speak.").foregroundStyle(.secondary).padding() }
                    ForEach(call.transcript.turns) { MessageBubble(role: $0.speaker, text: $0.text) }
                }.padding().frame(maxWidth: 800).frame(maxWidth: .infinity)
            }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Live Transcript").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showTranscript = false } } }
        }
    }
}
