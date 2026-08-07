// swift-tools-version:999.0
import PackageDescription

let package = Package(
    name: "third-party",
    products: [
        .library(
            name: "NewThirdParty",
            targets: ["NewThirdParty"],
        ),
        .library(
            name: "OldThirdParty",
            targets: ["OldThirdParty"],
            deprecated: .unsupported(
                message: "OldThirdParty is unsupported by the third party.",
                replacement: .renamed(to: "NewThirdParty"),
            ),
        ),
    ],
    targets: [
        .target(name: "NewThirdParty"),
        .target(name: "OldThirdParty"),
    ]
)
