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
    targets: [
        .executableTarget(
            name: "BeadsStatusBar",
            path: "Sources/BeadsStatusBar"
        )
    ]
)
