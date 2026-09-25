// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CaptionGrab",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "CaptionGrabCore", targets: ["CaptionGrabCore"]),
        .executable(name: "CaptionGrab", targets: ["CaptionGrab"]),
        .executable(name: "CaptionGrabNativeHost", targets: ["CaptionGrabNativeHost"])
    ],
    targets: [
        .target(name: "CaptionGrabCore"),
        .executableTarget(name: "CaptionGrab", dependencies: ["CaptionGrabCore"]),
        .executableTarget(name: "CaptionGrabNativeHost", dependencies: ["CaptionGrabCore"]),
        .testTarget(name: "CaptionGrabCoreTests", dependencies: ["CaptionGrabCore"])
    ]
)
