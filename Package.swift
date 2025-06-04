// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "piste-swift",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(
            name: "Piste",
            targets: ["Piste"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/valpackett/SwiftCBOR.git", branch: "master"),
        .package(url: "https://github.com/Corbin-Bigler/swift-logger.git", from: "0.2.2"),
    ],
    targets: [
        .target(
            name: "Piste",
            dependencies: [
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
                .product(name: "Logger", package: "swift-logger")
            ]
        ),
        .testTarget(
            name: "PisteTests",
            dependencies: ["Piste"]
        ),
    ]
)
