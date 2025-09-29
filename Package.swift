// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Piste",
    platforms: [.macOS(.v13), .iOS(.v12)],
    products: [
        .library(
            name: "Piste",
            targets: ["Piste"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Corbin-Bigler/logger-swift.git", from: "0.0.0")
    ],
    targets: [
        .target(
            name: "Piste",
            dependencies: [
                .product(name: "Logger", package: "logger-swift")
            ]
        ),
        .testTarget(
            name: "PisteTests",
            dependencies: ["Piste"]
        ),
    ]
)
