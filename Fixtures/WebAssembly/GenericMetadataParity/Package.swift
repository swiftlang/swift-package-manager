// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GenericMetadataParity",
    targets: [
        .target(name: "MetadataLib"),
        .executableTarget(name: "MetadataConsumer", dependencies: ["MetadataLib"]),
    ]
)
