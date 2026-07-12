// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SlidrFree",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SlidrFreeCore", targets: ["SlidrFreeCore"]),
        .executable(name: "SlidrFreeApp", targets: ["SlidrFreeApp"]),
        .executable(name: "SlidrFreeCoreChecks", targets: ["SlidrFreeCoreChecks"])
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
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(name: "SlidrFreeCoreChecks", dependencies: ["SlidrFreeCore"]),
        .testTarget(name: "SlidrFreeCoreTests", dependencies: ["SlidrFreeCore"]),
        .testTarget(name: "SlidrFreeAppTests", dependencies: ["SlidrFreeApp"])
    ]
)
