// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CaptionGrab",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "CaptionGrabCore", targets: ["CaptionGrabCore"]),
        .executable(name: "CaptionGrab", targets: ["CaptionGrab"])
    ],
    targets: [
        .target(name: "CaptionGrabCore"),
        .executableTarget(name: "CaptionGrab", dependencies: ["CaptionGrabCore"]),
        .testTarget(name: "CaptionGrabCoreTests", dependencies: ["CaptionGrabCore"])
    ]
)
