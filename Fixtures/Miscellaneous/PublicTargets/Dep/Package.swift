// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "Dep",
    targets: [
        .target(name: "PublicLibCore"),
        .libraryTarget(
            name: "PublicLib",
            type: .dynamic,
            dependencies: ["PublicLibCore"],
            visibility: .public
        ),
        .target(name: "PublicPlain", visibility: .public),
        .target(name: "PackageOnly"),
    ]
)
