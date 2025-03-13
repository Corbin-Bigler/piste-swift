// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "piste",
    platforms: [.macOS(.v15), .iOS(.v13)],
    products: [
        .library(
            name: "Piste",
            targets: ["Piste"]
        ),
    ],
    dependencies: [
        .package(path: "../hardpack"),
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from: "2.81.0")),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "Piste",
            dependencies: [
                .product(name: "Hardpack", package: "hardpack"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIO", package: "swift-nio")
            ]
        ),
    ]
)
