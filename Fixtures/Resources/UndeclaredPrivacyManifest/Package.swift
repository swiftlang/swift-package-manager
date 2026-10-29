// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "UndeclaredPrivacyManifest",
    products: [
        .library(name: "Utils", targets: ["Utils"]),
    ],
    targets: [
        // PrivacyInfo.xcprivacy is deliberately not declared as a resource here, so whether it is
        // copied is decided by the automatic file rules for the destination being built for.
        .target(name: "Utils"),
    ]
)
