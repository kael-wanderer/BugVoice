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
        .executable(name: "BugVoice", targets: ["BugVoice"]),
        .executable(name: "bugvoice-bench", targets: ["BugVoiceBench"]),
        .executable(name: "bugvoice-mcp", targets: ["BugVoiceMCP"]),
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
                .product(name: "SpeakerKit", package: "WhisperKit"),
            ],
            path: "Sources/WhisperEngine",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // macOS integrations: event tap, Accessibility, pasteboard, audio,
        // Keychain. A library so its non-UI parts can be unit-tested.
        .target(
            name: "BugVoiceMac",
            dependencies: ["VoiceCore"],
            path: "Sources/BugVoiceMac"
        ),
        // The menu-bar app: SwiftUI and AppKit glue only. Bundled and signed
        // by Scripts/build-app.sh.
        .executableTarget(
            name: "BugVoice",
            dependencies: ["VoiceCore", "WhisperEngine", "BugVoiceMac"],
            path: "Sources/BugVoice"
        ),
        // The local MCP socket shared by the app and the bugvoice-mcp bridge.
        // Foundation and Darwin only, so the bridge starts fast.
        .target(
            name: "MCPKit",
            dependencies: ["VoiceCore"],
            path: "Sources/MCPKit"
        ),
        // The stdio MCP server agents start; copied into Contents/MacOS by
        // Scripts/build-app.sh.
        .executableTarget(
            name: "BugVoiceMCP",
            dependencies: ["MCPKit", "VoiceCore"],
            path: "Sources/BugVoiceMCP"
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
        .testTarget(
            name: "MCPKitTests",
            dependencies: ["MCPKit", "VoiceCore"],
            path: "Tests/MCPKitTests"
        ),
        .testTarget(
            name: "BugVoiceMacTests",
            dependencies: ["BugVoiceMac"],
            path: "Tests/BugVoiceMacTests"
        ),
    ]
)
