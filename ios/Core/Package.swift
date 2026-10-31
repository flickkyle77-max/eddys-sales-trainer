// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ObjectionIQCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ObjectionIQCore", targets: ["ObjectionIQCore"]),
        .executable(name: "PolicyChecks", targets: ["PolicyChecks"])
    ],
    targets: [
        .target(name: "ObjectionIQCore"),
        .executableTarget(name: "PolicyChecks", dependencies: ["ObjectionIQCore"], path: "Checks")
    ]
)
