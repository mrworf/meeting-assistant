// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MeetingAssistant",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MeetingAssistantCore", targets: ["MeetingAssistantCore"]),
        .executable(name: "MeetingAssistant", targets: ["MeetingAssistant"]),
    ],
    targets: [
        .target(name: "MeetingAssistantCore"),
        .executableTarget(
            name: "MeetingAssistant",
            dependencies: ["MeetingAssistantCore"]
        ),
        .testTarget(
            name: "MeetingAssistantCoreTests",
            dependencies: ["MeetingAssistantCore"]
        ),
    ]
)

