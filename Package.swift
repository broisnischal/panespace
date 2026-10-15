// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "zspace",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "zspace", targets: ["zspace"]),
        .executable(name: "caps", targets: ["caps"]),
    ],
    targets: [
        // Pure window-management logic: tree, layout, config, commands. No AppKit, fully unit-tested.
        .target(name: "ZSpaceCore"),
        // Shared by both apps: Caps Lock remap (hidutil) and the zspace IPC socket.
        .target(name: "MacKit"),
        // macOS glue: Accessibility API, event tap, IPC, menu bar.
        .executableTarget(
            name: "zspace",
            dependencies: ["ZSpaceCore", "MacKit"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(name: "ZSpaceCoreTests", dependencies: ["ZSpaceCore"]),
        // Caps: Caps Lock as a programmable key, per app. Config parsing/resolution is pure and tested.
        .target(name: "CapsCore", dependencies: ["ZSpaceCore"]),
        .executableTarget(
            name: "caps",
            dependencies: ["CapsCore", "MacKit"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ApplicationServices")]
        ),
        .testTarget(name: "CapsCoreTests", dependencies: ["CapsCore"]),
    ]
)
