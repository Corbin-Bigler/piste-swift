// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "piste-swift",
    platforms: [.macOS(.v13), .iOS(.v14)],
    products: [
        .library(
            name: "Piste",
            targets: ["Piste"]
        ),
        .executable(name: "protoc-gen-piste-swift", targets: ["protoc-gen-piste-swift"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.0.0"),
        .package(path: "../swift-logger")
    ],
    targets: [
        .target(
            name: "Piste",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Logger", package: "swift-logger")
            ]
        ),
        .executableTarget(
            name: "protoc-gen-piste-swift",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SwiftProtobufPluginLibrary", package: "swift-protobuf")
            ]
        )
    ]
)
