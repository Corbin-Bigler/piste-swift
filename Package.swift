// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "piste-swift",
    platforms: [.macOS(.v13), .iOS(.v13)],
    products: [
        .library(
            name: "Piste",
            targets: ["Piste"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/valpackett/SwiftCBOR.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "Piste",
            dependencies: [
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
            ]
        ),
    ]
)
