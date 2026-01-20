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
        .package(url: "https://github.com/stasel/WebRTC.git", .upToNextMajor(from: "124.0.0")),
        .package(url: "https://github.com/daltoniam/Starscream.git", .exact("4.0.8"))
    ],
    targets: [
        .target(
            name: "XaviaCallingSDK",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC"),
                "Starscream"
            ],
            path: "Sources/XaviaCallingSDK",
            exclude: ["Info.plist"],
            resources: [
                .copy("PrivacyInfo.xcprivacy")
            ]),
        .testTarget(
            name: "XaviaCallingSDKTests",
            dependencies: ["XaviaCallingSDK"],
            path: "Tests/XaviaCallingSDKTests"),
    ],
    swiftLanguageVersions: [.v5]
)