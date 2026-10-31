import SwiftUI
import ObjectionIQCore

@main
@MainActor
struct ObjectionIQApp: App {
    private let server: ServerOrigin? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "ObjectionIQServerURL") as? String else { return nil }
        return try? ServerOrigin(value)
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if let server {
                    TrainingView(server: server)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                        Text("ObjectionIQ needs a valid server address in this build.")
                        Text("Please contact your administrator for an updated app.")
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(28)
                }
            }
        }
    }
}
