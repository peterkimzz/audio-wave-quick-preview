// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "audio-wave-quick-preview-mac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AudioWaveQuickPreviewCore",
            targets: ["AudioWaveQuickPreviewCore"]
        ),
        .executable(
            name: "AudioWaveQuickPreviewMac",
            targets: ["AudioWaveQuickPreviewMac"]
        ),
    ],
    targets: [
        .target(
            name: "AudioWaveQuickPreviewCore"
        ),
        .executableTarget(
            name: "AudioWaveQuickPreviewMac",
            dependencies: ["AudioWaveQuickPreviewCore"]
        ),
        .testTarget(
            name: "AudioWaveQuickPreviewCoreTests",
            dependencies: ["AudioWaveQuickPreviewCore"]
        ),
    ]
)
