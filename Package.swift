// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BildShow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BildShow", targets: ["BildShow"])],
    targets: [
        .target(name: "BildShowCore"),
        .executableTarget(name: "BildShow", dependencies: ["BildShowCore"], resources: [.copy("Resources")]),
        .testTarget(name: "BildShowCoreTests", dependencies: ["BildShowCore"])
    ]
)
