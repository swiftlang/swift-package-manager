// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrivacyManifest",
    targets: [
        .target(
            name: "PrivacyManifestOnly",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "PrivacyManifestAndData",
            resources: [.copy("PrivacyInfo.xcprivacy"), .copy("data.txt")]
        ),
    ]
)
