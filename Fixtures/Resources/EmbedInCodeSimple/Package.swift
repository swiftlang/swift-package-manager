// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EmbedInCodeSimple",
    targets: [
        .executableTarget(name: "EmbedInCodeSimple", resources: [.embedInCode("best.txt")]),
    ]
)
