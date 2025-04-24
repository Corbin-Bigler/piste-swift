// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "piste",
    platforms: [.macOS(.v14), .iOS(.v13)],
    products: [
        .library(
            name: "Piste",
            targets: ["Piste"]
        ),
    ],
    dependencies: [
        .package(path: "../swift-logger"),
        .package(url: "https://github.com/valpackett/SwiftCBOR.git", branch: "master"),
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from: "2.82.0")),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.20.0"),
    ],
    targets: [
        .target(
            name: "Piste",
            dependencies: [
                .product(name: "SwiftLogger", package: "swift-logger"),
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ]
        ),
    ]
)
