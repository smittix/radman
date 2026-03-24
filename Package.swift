// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HorizonRFMac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "HorizonRFMac",
            targets: ["HorizonRFMac"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "HorizonRFMac",
            path: "Sources/HorizonRFMac"
        ),
        .testTarget(
            name: "HorizonRFMacTests",
            dependencies: ["HorizonRFMac"],
            path: "Tests/HorizonRFMacTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
