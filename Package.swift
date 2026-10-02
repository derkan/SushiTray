// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SushiTray",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SushiTray", targets: ["SushiTray"]),
    ],
    targets: [
        .executableTarget(
            name: "SushiTray",
            path: "SushiTray",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "AppIcon.icns",
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
