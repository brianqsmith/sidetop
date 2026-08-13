// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sidetop",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Sidetop", targets: ["Sidetop"])
    ],
    targets: [
        .executableTarget(
            name: "Sidetop",
            path: "Sources/Sidetop"
        ),
        .testTarget(
            name: "SidetopTests",
            dependencies: ["Sidetop"],
            path: "Tests/SidetopTests"
        )
    ]
)
