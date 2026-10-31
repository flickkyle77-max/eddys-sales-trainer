# ObjectionIQ — native iPhone and iPad application

Open `ObjectionIQ.xcodeproj` in full Xcode. This version uses native SwiftUI screens and native WebRTC microphone/playback. It does not load the website into a WKWebView.

## What is connected

- Native sign-in uses the existing HTTPS `/api/login` and `/api/me` routes. Device-only Keychain storage holds the existing access/refresh cookies, never the password or provider API key. Native sessions are separate from Safari sign-in.
- Train, Progress, and Account tabs use native navigation, controls, sheets, Dynamic Type, light/dark appearance, and keyboard handling.
- Phone Training uses the pinned `stasel/WebRTC` 154.0.0 Swift package. Its checksum-verified XCFramework carries microphone audio directly to OpenAI over WebRTC; authenticated SDP setup stays on the existing `/api/session` server route. The long-lived OpenAI key stays on Render.
- Objection Lab and Text Training use the existing authenticated REST routes. Objection tokens remain server-authored; coaching, scoring, sealed save-only retries, and history keep the web contracts.
- A native review screen includes rubric dimensions, evidence, coaching, hidden-concern debrief, and conversation where available. History combines the latest 30 phone and 30 text/objection sessions. Chart averages describe these recent records, not lifetime activity.
- Phone audio and transcripts stay in memory; existing server phone history saves scores but not the full transcript. Unfinished practice is cleared on dismissal or sign-out.

## Build and publish

1. Check out `codex/native-ios-rebuild`. Open `ios/ObjectionIQ.xcodeproj`, scheme **ObjectionIQ**.
2. Let Xcode resolve the exact WebRTC dependency. No CocoaPods or manually copied frameworks are required. The package is a community distribution of upstream WebRTC; attribution and dependency notes are in `THIRD-PARTY-NOTICES.md`.
3. Set the existing App Store Connect bundle identifier and Apple Developer team in Signing & Capabilities. The source placeholder `com.example.ObjectionIQ` must be replaced with the existing app's identifier. Set an unused build number higher than the current uploaded build. Version in source is 0.4.0.
4. Confirm `ObjectionIQServerURL` in `ObjectionIQ/Info.plist` points to your current HTTPS server. The technical hosting address is intentionally preserved. Use the current main server version with the supported-voice fix.
5. Build for an iOS Simulator, then build and run on a physical iPhone and iPad. The local authoring Mac has Command Line Tools only; the GitHub **Native iOS build** check provides the full SDK compilation gate.
6. Perform the device acceptance checks below, Archive for **Any iOS Device**, Validate, and Distribute → App Store Connect → Upload. Release through the existing TestFlight app record.

Unsigned compile command:

```sh
xcodebuild -project ios/ObjectionIQ.xcodeproj -scheme ObjectionIQ \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
swift run --package-path ios/Core PolicyChecks
```

## Required device acceptance checks

Use a test employee account and fictional conversations. Actual calls and AI replies use your API account.

- Sign in with the same account used on the web; compare saved history. Relaunch and verify Keychain restore. Sign out and confirm the next employee sees none of the prior account's data.
- Allow microphone on first call. Exchange several sentences in English and Spanish. Verify the customer is audible, speech is transcribed once, mute works, and the selected speaker/system audio route behaves correctly. Test built-in audio, wired headphones if supported, and Bluetooth on physical hardware.
- Deny microphone permission; confirm recovery guidance and Settings recovery. Test a failed connection and a failed score request; the transcript should stay available and scoring can be retried.
- End & Score and verify the result appears in the web and native history. Speech recognition can omit or misrecognize words; check evidence against what was actually said.
- Background or lock the device during a call; capture stops and an interrupted-call explanation appears on return. The available transcript can still be scored. There is intentionally no background microphone entitlement or CallKit incoming-call behavior.
- Complete independent and coached Objection Lab practice, including progressive/Spanish settings. Check coaching, failed-reply draft retention, retry scoring, and the sealed save-only retry when database saving fails.
- Complete Text Training. Check keyboard/composer behavior and unsent-draft warnings. Legacy phone/text save warnings reflect the existing backend: there is no save-only retry endpoint for those modes.
- Verify large text, VoiceOver labels, iPhone compact screens, iPad portrait/landscape, light/dark mode, and reduced motion. No physical-device acceptance or signed TestFlight upload is implied by a successful simulator build.

## Server and database

No Supabase migration, new provider key, new server, or production deployment is needed for this native UI. Keep all existing secrets on Render. Do not embed `.env`, OpenAI keys, Supabase service-role keys, signing certificates, or employee credentials into the app or repository.
