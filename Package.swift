// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MeetingScribe",
    platforms: [
        .iOS(.v17)
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
            name: "whisper_c",
            path: "whisper_c",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("."),
                .define("WHISPER_VERSION", to: "\"1.7.4\"")
            ],
            cxxSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("."),
                .define("WHISPER_VERSION", to: "\"1.7.4\"")
            ]
        ),
        .target(
            name: "MeetingScribe",
            dependencies: ["whisper_c"],
            path: "MeetingScribe",
            resources: [
                .process("Resources/Templates")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
