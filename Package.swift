// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WebRTCService",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "WebRTCService",
            targets: ["WebRTCService"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/socketio/socket.io-client-swift", from: "16.1.0"),
        .package(url: "https://github.com/WebRTCHS/ios-webrtc", from: "1.1.65000")
    ],
    targets: [
        .target(
            name: "WebRTCService",
            dependencies: [
                .product(name: "SocketIO", package: "socket.io-client-swift"),
                .product(name: "WebRTC", package: "ios-webrtc")
            ],
            path: "Sources",
            resources: [
                .process("PrivacyInfo.xcprivacy") // For App Store privacy requirements
            ]
        )
    ]
)