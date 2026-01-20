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
        .package(url: "https://github.com/stasel/WebRTC.git", .exact("124.0.0"))
    ],
    targets: [
        .target(
            name: "XaviaCallingSDK",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
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