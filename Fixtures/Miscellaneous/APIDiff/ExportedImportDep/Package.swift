// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ExportedImportDep",
    products: [
        .library(name: "Lib", targets: ["Lib"]),
    ],
    targets: [
        .target(name: "Dep"),
        .target(name: "Lib", dependencies: ["Dep"]),
    ]
)
