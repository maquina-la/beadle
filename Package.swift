// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BeadsStatusBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BeadsStatusBar", targets: ["BeadsStatusBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/MarkdownUI.git", from: "2.4.1"),
        // CommandLineTools-only environments have no bundled Testing module;
        // pull swift-testing from source so `swift test` works everywhere.
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.12.0")
    ],
    targets: [
        .executableTarget(
            name: "BeadsStatusBar",
            dependencies: [
                .product(name: "MarkdownUI", package: "MarkdownUI")
            ],
            path: "Sources/BeadsStatusBar",
            swiftSettings: [
                // MarkdownUI 2.4.1's Theme builder closures are non-isolated but
                // call @MainActor SwiftUI modifiers, which doesn't satisfy Swift
                // 6 strict concurrency. Use Swift 5 mode for this target until
                // MarkdownUI publishes Swift 6-compatible releases.
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "BeadsStatusBarTests",
            dependencies: [
                "BeadsStatusBar",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/BeadsStatusBarTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
