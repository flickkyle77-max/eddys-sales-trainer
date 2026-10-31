import SwiftUI
import WebKit
import ObjectionIQCore

@MainActor
struct TrainingView: View {
    @StateObject private var browser: TrainingBrowser
    @State private var confirmReload = false

    init(server: ServerOrigin) {
        _browser = StateObject(wrappedValue: TrainingBrowser(server: server))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WebContent(browser: browser)
                if let failure = browser.failure {
                    VStack(spacing: 18) {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                        Text(failure.title).font(.title2.bold())
                        Text(failure.message).foregroundStyle(.secondary)
                        Button("Try Again", action: browser.reload).buttonStyle(.borderedProminent)
                        Button("Open in Safari", action: browser.openInSafari)
                    }
                    .multilineTextAlignment(.center)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 11/255, green: 16/255, blue: 24/255))
                }
            }
            .overlay(alignment: .top) {
                if browser.isLoading && browser.failure == nil {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Opening training…").font(.callout)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("ObjectionIQ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: browser.openAppSettings) { Label("Microphone Settings", systemImage: "mic") }
                        Button(action: browser.openInSafari) { Label("Open in Safari", systemImage: "safari") }
                        Button(action: { confirmReload = true }) { Label("Reload Training", systemImage: "arrow.clockwise") }
                    } label: {
                        Label("Training options", systemImage: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Reload training?", isPresented: $confirmReload, titleVisibility: .visible) {
                Button("Reload", role: .destructive, action: browser.reload)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Reloading ends any active call and clears unfinished practice on this page.")
            }
            .alert(item: $browser.dialog) { dialog in
                if dialog.requiresConfirmation {
                    return Alert(title: Text("ObjectionIQ"), message: Text(dialog.message),
                                 primaryButton: .default(Text("Continue"), action: { dialog.resolve(true) }),
                                 secondaryButton: .cancel({ dialog.resolve(false) }))
                }
                return Alert(title: Text("ObjectionIQ"), message: Text(dialog.message),
                             dismissButton: .default(Text("OK"), action: { dialog.resolve(true) }))
            }
            .onAppear(perform: browser.startIfNeeded)
        }
    }
}

@MainActor
private struct WebContent: UIViewRepresentable {
    @ObservedObject var browser: TrainingBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
