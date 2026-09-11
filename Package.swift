// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PressToTalk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PressToTalk", targets: ["PressToTalk"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0")
    ],
    targets: [
        // Objective-C shim: AVFoundation raises NSExceptions that Swift cannot
        // catch, which turned recoverable audio failures into silent aborts.
        .target(
            name: "ObjCExceptionCatcher",
            path: "Sources/ObjCExceptionCatcher"
        ),
        .executableTarget(
            name: "PressToTalk",
            dependencies: [
                "ObjCExceptionCatcher",
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/PressToTalk",
            exclude: ["openai_whisper-small"],
            // Apple's on-device translation only exists from macOS 15; weak
            // linking keeps the app launching on macOS 14, where the feature
            // is gated off with #available.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "Translation"])
            ]
        )
    ]
)
