// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "biometric_vault",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "biometric-vault", targets: ["biometric_vault"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "biometric_vault",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
