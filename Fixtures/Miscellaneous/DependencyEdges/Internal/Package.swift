// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "ExtraCommandLineFlags",
    targets: [
        .target(name: "Bar", path: "Bar"),
        .target(name: "Foo", dependencies: ["Bar"], path: "Foo"),
    ]
)
