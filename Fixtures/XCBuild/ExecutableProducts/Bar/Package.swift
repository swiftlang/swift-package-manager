// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "Bar",
    products: [
        .executable(name: "bar", targets: ["bar"]),
        .executable(name: "cbar", targets: ["cbar"]),
        .library(name: "BarLib", targets: ["BarLib"]),
    ],
    targets: [
        .target(name: "bar", dependencies: ["BarLib"]),
        .target(name: "cbar"),
        .target(name: "BarLib"),
    ],
    swiftLanguageVersions: [.v4_2],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx14
)
