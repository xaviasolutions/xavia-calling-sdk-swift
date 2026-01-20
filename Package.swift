// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "XaviaCallingSDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "XaviaCallingSDK",
            targets: ["XaviaCallingSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/webrtc-sdk/Specs.git", .exact("124.0.0")),
        .package(url: "https://github.com/daltoniam/Starscream.git", .exact("4.0.8"))
    ],
    targets: [
        .target(
            name: "XaviaCallingSDK",
            dependencies: [
                .product(name: "WebRTC", package: "Specs"),
                "Starscream"
            ],
            path: "Sources/XaviaCallingSDK"),
        .testTarget(
            name: "XaviaCallingSDKTests",
            dependencies: ["XaviaCallingSDK"]),
    ]
)