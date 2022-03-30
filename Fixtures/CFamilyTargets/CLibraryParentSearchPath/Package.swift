// swift-tools-version: 5.5

import PackageDescription

let package = Package(
    name: "CLibraryParentSearchPath",
    products: [
        .library(
            name: "HeaderInclude",
            targets: ["HeaderInclude"]),
    ],
    targets: [
        .target(
            name: "CHeaderInclude",
            cSettings: [
                /*
                 This package tests path normalization; incorrect path normalization on certain OSes (especially Windows) can lead to relative paths like these not being correctly passed to the C compiler.
                 */
                .headerSearchPath("../Constants")
            ]
        ),
        .target(
            name: "HeaderInclude",
            dependencies: [
                "CHeaderInclude"
            ]
        )
    ]
)
