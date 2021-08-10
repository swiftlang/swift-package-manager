// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "Resources",
    targets: [
        .target(
            name: "SwiftyResource",
            resources: [
                .copy("foo.txt"),
            ]
        ),

        .target(
            name: "SeaResource",
            resources: [
                .copy("foo.txt"),
            ]
        ),
    ]
)
