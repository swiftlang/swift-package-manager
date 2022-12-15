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

        .target(
            name: "ClangResource",
            resources: [
                .copy("foo.txt"),
            ]
        ),

        .testTarget(
            name: "ClangResourceTests",
            dependencies: ["ClangResource"]
        ),

        .target(
            name: "CPPResource",
            resources: [
                .copy("foo.txt"),
            ]
        ),

        .target(
            name: "MixedClangResource",
            resources: [
                .copy("foo.txt"),
            ]
        ),
    ]
)
