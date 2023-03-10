// swift-tools-version: 999.0

import PackageDescription

let package = Package(
    name: "EmbedInCodeSimple",
    targets: [
        .executableTarget(name: "EmbedInCodeSimple", resources: [.embedInCode("best.txt")]),
    ]
)
