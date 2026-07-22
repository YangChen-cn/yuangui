// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YuanGUI",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "YuanGUI", targets: ["YuanGUI"])
    ],
    targets: [
        .executableTarget(
            name: "YuanGUI",
            path: "Sources/YuanGUI",
            resources: [
                .copy("Resources/Sprites"),
                .copy("Resources/YuanGUI.Translate.shortcut"),
                .copy("Resources/AppIcon.png"),
                .copy("Resources/AppIcon.icns")
            ]
        ),
        .testTarget(
            name: "YuanGUITests",
            dependencies: ["YuanGUI"],
            path: "Tests/YuanGUITests",
            resources: [.process("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v5]
)
