// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SlidrFree",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SlidrFreeCore", targets: ["SlidrFreeCore"]),
        .executable(name: "SlidrFreeApp", targets: ["SlidrFreeApp"])
    ],
    targets: [
        .target(name: "SlidrFreeCore"),
        .executableTarget(
            name: "SlidrFreeApp",
            dependencies: ["SlidrFreeCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(name: "SlidrFreeCoreTests", dependencies: ["SlidrFreeCore"])
    ]
)
