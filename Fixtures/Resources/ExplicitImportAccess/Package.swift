// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ExplicitImportAccess",
    targets: [
        .executableTarget(
            name: "ExplicitImportAccess",
            resources: [
                .copy("resource.txt"),
            ]
        ),
    ]
)
