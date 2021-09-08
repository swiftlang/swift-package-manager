// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "Bar",
    products: [
        .library(name: "BarLibProduct", type: .dynamic, targets: ["BarLib"]),
    ],
    targets: [
        .target(name: "BarLib"),
    ],
    swiftLanguageVersions: [.v4_2],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx14
)
