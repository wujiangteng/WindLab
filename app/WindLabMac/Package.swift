// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "WindLabMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WindLabMac", targets: ["WindLabMac"])
    ],
    targets: [
        .executableTarget(
            name: "WindLabMac",
            resources: [
                .copy("Python/parse_windog.py")
            ]
        )
    ]
)
