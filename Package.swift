// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "TwitchPrompter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TwitchPrompter", targets: ["TwitchPrompter"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.42.0"),
        .package(url: "https://github.com/vapor/websocket-kit.git", from: "2.7.0")
    ],
    targets: [
        .executableTarget(
            name: "TwitchPrompter",
            dependencies: [
                .product(name: "WebSocketKit", package: "websocket-kit")
            ],
            path: "Sources/TwitchPrompter"
        )
    ]
)