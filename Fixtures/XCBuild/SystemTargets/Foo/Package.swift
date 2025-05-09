// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "Foo",
    targets: [
        .target(name: "foo", dependencies: ["SystemLib"]),
        .systemLibrary(name: "SystemLib", pkgConfig: "libsys"),
    ]
)
