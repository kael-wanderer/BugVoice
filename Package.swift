// swift-tools-version: 6.0

import PackageDescription

// BugVoice has exactly one external dependency. WhisperKit is MIT and pinned
// to an exact version: a speech engine is not something to let a resolver
// upgrade on its own. Adding another dependency is a maintainer decision
// recorded in THIRD_PARTY_NOTICES.md.
let package = Package(
    name: "BugVoice",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "bugvoice-bench", targets: ["BugVoiceBench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "1.1.1"),
    ],
    targets: [
        // Every decision that can be tested without a window, microphone or
        // Accessibility. Foundation only.
        .target(
            name: "VoiceCore",
            path: "Sources/VoiceCore"
        ),
        // Swift 5 language mode: WhisperKit's types are not Sendable, and an
        // actor that owns one cannot hand it to WhisperKit's own async API
        // under Swift 6 region checking. Nothing outside this target sees a
        // WhisperKit type.
        .target(
            name: "WhisperEngine",
            dependencies: [
                "VoiceCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/WhisperEngine",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "BugVoiceBench",
            dependencies: ["VoiceCore", "WhisperEngine"],
            path: "Sources/BugVoiceBench"
        ),
        .testTarget(
            name: "VoiceCoreTests",
            dependencies: ["VoiceCore"],
            path: "Tests/VoiceCoreTests"
        ),
    ]
)
