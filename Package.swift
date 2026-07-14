// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YuanGUI",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "YuanGUI", targets: ["YuanGUI"])
    ],
    targets: [
        .executableTarget(
            name: "YuanGUI",
            path: "Sources/YuanGUI",
            resources: [.copy("Resources/Sprites")]
        ),
        .testTarget(
            name: "YuanGUITests",
            dependencies: ["YuanGUI"],
            path: "Tests/YuanGUITests"
        )
    ],
    swiftLanguageModes: [.v5]
)
