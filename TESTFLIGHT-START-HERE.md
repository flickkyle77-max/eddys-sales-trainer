# ObjectionIQ — rebuilt iPhone/iPad source

Open **ios/ObjectionIQ.xcodeproj** in full Xcode. The complete rebuild instructions are in **ios/README.md**.

This package now includes an actual iOS project alongside the web application and Node server. The app is preconfigured to open the current secure training server and includes explicit web-view microphone handling. It preserves the existing Phone, Text, and Objection training features.

The developer must select the owner's Apple signing team, use the existing App Store Connect bundle identifier, set an unused build number, compile the iOS app, and test a real call on an iPhone/iPad before uploading the new TestFlight build. The included bundle identifier is a placeholder. No signed build is included, and the previous TestFlight app will not update merely because these source files are in GitHub.

Validation available here: all web syntax checks, 35 automated web/service tests, Swift source syntax checks, Xcode/plist structural checks, and 31 passing checks in the dependency-free Swift permission-policy checker. Full Xcode/iOS SDK compilation and device microphone verification remain outstanding.

No secrets, employee records, installed dependencies, or Apple signing credentials are included. Use `.env.example` only when setting up a separate backend; existing hosted configuration does not need to be replaced for this iOS rebuild.
