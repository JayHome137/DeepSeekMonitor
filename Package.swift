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
        )
    ]
)
