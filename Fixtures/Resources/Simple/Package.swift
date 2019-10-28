// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "Resources",
    targets: [
        .target(
            name: "SwiftyResource",
            __resources: [
                .copy("foo.txt"),
            ]
        ),

        .target(
            name: "SeaResource",
            __resources: [
                .copy("foo.txt"),
            ]
        ),
    ]
)
