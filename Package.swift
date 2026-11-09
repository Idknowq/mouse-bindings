// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MouseBindings",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MouseBindings", targets: ["MouseBindings"])],
    targets: [
        .target(name: "MultitouchBridge", linkerSettings: [
            .linkedFramework("CoreFoundation"), .linkedFramework("IOKit")
        ]),
        .target(name: "GestureCore"),
        .executableTarget(name: "MouseBindings", dependencies: ["MultitouchBridge", "GestureCore"]),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"], resources: [.copy("Fixtures")])
    ]
)
