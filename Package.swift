// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AOXFoundationKit",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "AOXFoundationKit", targets: ["AOXFoundationKit"]),
    ],
    targets: [
        .target(
            name: "AOXFoundationKit",
            path: "Sources/AOXFoundationKit"
        ),
    ]
)
