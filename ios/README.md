# ObjectionIQ for iPhone and iPad

This is a new, minimal iOS application for the existing ObjectionIQ website. It replaces the unknown wrapper used by the earlier TestFlight build. The iOS source, Xcode project, shared scheme, and permission policy now live in this repository.

It loads the existing HTTPS website directly rather than loading bundled HTML or asking an employee to enter a server address. Phone Training, Text Training, Objection Lab, login, and saved history continue to use the existing backend.

## Open and build

1. On a Mac with full Xcode installed, open `ios/ObjectionIQ.xcodeproj`.
2. Select the **ObjectionIQ** scheme and app target.
3. In **Signing & Capabilities**, select the owner's Apple Developer team.
4. Replace the placeholder bundle identifier `com.example.ObjectionIQ` with the **exact bundle identifier of the existing App Store Connect app** if this should update the current TestFlight app. Do not create a different app record accidentally.
5. Set the marketing version as appropriate for that app record and choose a build number higher than the latest uploaded build. The project values `0.3.0` and `1` are editable defaults, not confirmed App Store Connect values.
6. Build for an iPhone/iPad simulator first, then run on a physical device.
7. Complete the device checks below before archiving and uploading a replacement TestFlight build using Xcode Organizer.

This repository contains no Apple signing certificate, provisioning profile, account password, or signed IPA. It does not automatically upload to TestFlight.

Optional simulator build command from the repository root:

```sh
xcodebuild -project ios/ObjectionIQ.xcodeproj \
  -scheme ObjectionIQ -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The app uses iOS/iPadOS 16 or newer, SwiftUI, WebKit, and AVFoundation. There are no third-party native dependencies. `Core` is a local Swift package included by the Xcode project.

## Microphone behavior

- `Info.plist` contains an explicit microphone purpose string.
- A `WKUIDelegate` handles the website's media-capture request.
- Requests must be for **microphone only**, from the configured HTTPS origin, in the main frame. Camera, untrusted origins, and embedded-frame requests are denied.
- The app requests iOS microphone consent only when Phone Training requests capture after the user taps Start Call. It does not request microphone access on launch or for text/objection drills.
- It rechecks the current trusted origin after iOS answers. Capture is granted only if iOS consent is granted.
- The web view uses persistent website storage, the normal user agent, and the same HTTPS origin as the server. Existing HttpOnly session cookies stay with that website.
- There are no certificate-trust bypasses, arbitrary-load ATS exceptions, or camera permissions.
- Inline media playback is configured for the existing WebRTC remote audio. Audio session routing is left to WebKit; the app does not force a separate audio-session category.
- Native JavaScript alert and confirmation handlers support the web app's existing errors and unfinished-practice confirmation.

The accompanying web change checks microphone API/secure-context availability and gives specific recovery advice for denied, missing, and busy microphones before starting a server voice session.

## Server configuration

`ObjectionIQ/Info.plist` contains one `ObjectionIQServerURL` value, preconfigured to the current production HTTPS server. The technical hosting hostname still uses the legacy service slug; application display names and assets use ObjectionIQ. There is no employee server-entry screen.

If the owner moves to another domain, change this plist value to the complete HTTPS origin with no credentials, query string, or path. Navigation and microphone allowlisting are derived from that same value. Do not simply add arbitrary origins to fix a connection error.

Server-side API secrets remain on the backend and are never placed in the app. Installing this iOS app does not move the backend into the device or add offline training.

## Verification commands

```sh
npm ci
npm run check
npm test
swift run --package-path ios/Core PolicyChecks
```

`PolicyChecks` is a dependency-free command-line executable that validates origin normalization, unsafe configuration rejection, trusted navigation, default/custom HTTPS ports, and microphone-only main-frame capture eligibility. It uses synthetic URLs, no network requests, and no actual microphone.

## Device acceptance checks before TestFlight

1. Launch directly into the login page without entering a server address. Check a slow/cold server start, retry, and offline recovery.
2. Sign in with an employee account, relaunch, and confirm the intended session persists. Confirm sign-out clears employee-specific page state.
3. Start Phone Training. The first actual microphone request should show the system permission prompt. Allow it, speak, hear the customer, end the call, and inspect the score.
4. Deny the first permission request on a test device. Confirm a clear microphone message, then enable access using the native menu's **Microphone Settings** option, return, and retry.
5. Repeat calls, mute/unmute, try speaker/headset routes, and test foreground/background interruptions on both iPhone and iPad. Background calling is not implemented in this rebuild.
6. With microphone access denied, confirm Text Training and Objection Lab remain usable. Complete a drill, save it, and reopen the review after relaunch.
7. Test Spanish practice, coached/independent labels, progressive drills, and confirmation dialogs. Reload should warn that unfinished work will be lost.
8. Confirm outside links do not load as trusted microphone-enabled content. Compare Safari behavior if a device-specific capture error persists.

A server update alone cannot replace an already installed iOS binary's permission configuration. These iOS changes need a newly compiled, signed TestFlight build.

## Validation status in this handoff

The web syntax checks and 35 automated regression tests passed. Swift source syntax, project/plist structure, scheme references, and icon assets were checked. All 31 Swift permission-policy checks passed using the dependency-free command-line executable.

The authoring Mac has Command Line Tools, not full Xcode or an iOS SDK. The complete iOS target has **not** been type-checked, simulator-built, signed, uploaded, or tested with physical-device microphone access here. A successful policy check is not evidence that real microphone capture works. Compile the project with full Xcode and complete the device checklist before distributing it. Review app privacy/beta metadata against the existing backend's handling of login and audio data.

Apple references:

- WebKit media permission delegate: https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:requestmediacapturepermissionfor:initiatedbyframe:type:decisionhandler:)
- Microphone purpose string: https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription
- Uploading builds: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
