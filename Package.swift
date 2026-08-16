// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeepSeekMonitor",
    defaultLocalization: "zh",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DeepSeekMonitor", targets: ["DeepSeekMonitor"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.5")
    ],
    targets: [
        .executableTarget(
            name: "DeepSeekMonitor",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/DeepSeekMonitor",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("WidgetKit"),
                .linkedFramework("WebKit")
            ]
        ),
        .executableTarget(
            name: "WidgetSupport",
            dependencies: [],
            path: "Sources/WidgetSupport",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("WidgetKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Foundation")
            ]
        ),
        .testTarget(
            name: "DeepSeekMonitorTests",
            dependencies: ["DeepSeekMonitor"],
            path: "Tests/DeepSeekMonitorTests"
        )
    ]
)
