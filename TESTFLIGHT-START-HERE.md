# Build the native ObjectionIQ app

Use branch **codex/native-ios-rebuild**, then open **ios/ObjectionIQ.xcodeproj**.

This branch now contains native SwiftUI screens and native WebRTC calls, replacing the previous website wrapper. Use the latest commit, not the old ZIP or a downloaded earlier revision.

1. Read `ios/README.md`.
2. Verify the GitHub **Native iOS build** check passes for the current commit.
3. Set the existing Apple Developer team, App Store Connect bundle ID, and an unused higher build number.
4. Build and test on physical iPhone/iPad, including microphone, audio routing, sign-in, practice, scoring, and history.
5. Archive, validate, and upload to the existing TestFlight app record.

The source is not a signed IPA. Full simulator compilation is an automated gate; actual audio/device acceptance and TestFlight signing/upload still belong to the builder.
