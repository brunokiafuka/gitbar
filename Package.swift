// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Gitbar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "gitbar", targets: ["Gitbar"])
    ],
    targets: [
        .executableTarget(
            name: "Gitbar",
            path: "Sources/Gitbar"
        )
    ]
)
