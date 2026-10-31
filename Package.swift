// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MeetingScribe",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "MeetingScribe",
            targets: ["MeetingScribe"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MeetingScribe",
            dependencies: [],
            path: "MeetingScribe",
            resources: [
                .process("Resources/Templates")
            ]
        )
    ]
)
