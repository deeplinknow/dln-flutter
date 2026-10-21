// swift-tools-version: 5.9
// Swift Package Manager manifest for Flutter's SPM integration: the iOS implementation of the
// deeplinknow plugin. Depends on the native DeepLinkNow SDK
// (https://github.com/deeplinknow/dln-ios, from 1.3.0; FLT-01, FLT-03).

import PackageDescription

let package = Package(
    name: "deeplinknow_ios",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        // Flutter links the plugin by its name with `_` replaced by `-`.
        .library(name: "deeplinknow-ios", targets: ["deeplinknow_ios"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/deeplinknow/dln-ios", .upToNextMinor(from: "1.3.0")),
    ],
    targets: [
        .target(
            name: "deeplinknow_ios",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "DeepLinkNow", package: "dln-ios"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
