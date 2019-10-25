// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "Resources",
    targets: [
        .target(
            name: "Resources",
            __resources: [
                .copy("foo.txt"),
            ]
        ),
    ]
)
