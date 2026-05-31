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
    targets: [
        .executableTarget(
            name: "DeepSeekMonitor",
            path: "Sources/DeepSeekMonitor",
            exclude: [
                "WidgetSupport"
            ],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
