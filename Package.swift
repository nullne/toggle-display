// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DisplayToggle",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "CPrivateAPIs",
            path: "Sources/CPrivateAPIs",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "DisplayToggle",
            dependencies: ["CPrivateAPIs"],
            path: "Sources/DisplayToggle",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "DisplayToggleTests",
            dependencies: ["DisplayToggle"],
            path: "Tests/DisplayToggleTests"
        ),
    ]
)
