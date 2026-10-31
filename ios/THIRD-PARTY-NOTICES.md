# Third-party dependency

The native audio transport uses WebRTC, distributed as a Swift package by https://github.com/stasel/WebRTC at the exact version 154.0.0.

This is a community-packaged build of upstream WebRTC, not an OpenAI or Apple SDK. Swift Package Manager verifies the binary download using the checksum in the pinned package manifest. Preserve the license and notices bundled with the XCFramework when distributing the application. Upstream source and licensing: https://webrtc.googlesource.com/src/+/refs/heads/main/LICENSE and https://webrtc.googlesource.com/src/+/refs/heads/main/PATENTS.

No part of the web UI is embedded or displayed by this native target. The backend API remains shared with the web application.
