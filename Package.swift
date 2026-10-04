// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v13)],
    targets: [
        // Sampling, history and formatting — no UI, covered by tests.
        .target(
            name: "PulseCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        // The menu bar app.
        .executableTarget(
            name: "Pulse",
            dependencies: ["PulseCore"],
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore"]),
    ]
)
