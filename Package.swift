// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YuanGUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "YuanGUI", targets: ["YuanGUI"]),
        .library(name: "YuanGUIFinderCore", targets: ["YuanGUIFinderCore"])
    ],
    targets: [
        .target(
            name: "YuanGUIFinderCore",
            path: "Sources/YuanGUIFinderCore"
        ),
        .executableTarget(
            name: "YuanGUI",
            path: "Sources/YuanGUI",
            resources: [
                .copy("Resources/Sprites"),
                .copy("Resources/YuanGUI.Translate.shortcut"),
                .copy("Resources/AppIcon.png"),
                .copy("Resources/AppIcon.icns"),
                .process("Resources/Localization")
            ]
        ),
        .testTarget(
            name: "YuanGUITests",
            dependencies: ["YuanGUI", "YuanGUIFinderCore"],
            path: "Tests/YuanGUITests",
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "YuanGUIBenchmarks",
            dependencies: ["YuanGUI"],
            path: "Tests/YuanGUIBenchmarks"
        )
    ],
    swiftLanguageModes: [.v5]
)
