// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MediaSortHelper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MediaSortHelper", targets: ["MediaSortHelper"])
    ],
    targets: [
        .executableTarget(
            name: "MediaSortHelper",
            resources: [
                .process("Assets.xcassets")
            ],
            linkerSettings: [
                // Embed Info.plist so the executable has a bundle identifier and usage strings.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist"
                ])
            ]
        )
    ]
)
