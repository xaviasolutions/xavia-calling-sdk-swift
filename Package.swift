// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "XaviaCallingSDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "XaviaCallingSDK",
            targets: ["XaviaCallingSDK"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/webrtc-sdk/WebRTC.git",
            .upToNextMajor(from: "1.0.0")
        ),
        .package(
            url: "https://github.com/socketio/socket.io-client-swift.git",
            .upToNextMajor(from: "16.0.0")
        )
    ],
    targets: [
        .target(
            name: "XaviaCallingSDK",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC"),
                .product(name: "SocketIO", package: "socket.io-client-swift")
            ],
            path: "Sources"
        )
    ]
)
