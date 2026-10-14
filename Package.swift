// swift-tools-version: 6.0

import PackageDescription

// BugVoice has exactly one external dependency, WhisperKit, added in Task 8.
// Adding another is a maintainer decision recorded in THIRD_PARTY_NOTICES.md.
let package = Package(
    name: "BugVoice",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        // Every decision that can be tested without a window, microphone or
        // Accessibility. Foundation only.
        .target(
            name: "VoiceCore",
            path: "Sources/VoiceCore"
        ),
        .testTarget(
            name: "VoiceCoreTests",
            dependencies: ["VoiceCore"],
            path: "Tests/VoiceCoreTests"
        ),
    ]
)
