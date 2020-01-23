// swift-tools-version:999.0
import PackageDescription

let package = Package(
    name: "Localized",
    defaultLocalization: "es",
    targets: [
        .target(name: "exe", resources: [
            .process("Resources"),
        ]),
    ]
)
