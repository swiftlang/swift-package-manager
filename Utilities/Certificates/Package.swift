// swift-tools-version: 999.0

import PackageDescription

let package = Package(
    name: "Certificates",
    targets: [
        .target(name: "Certificates",
                path: ".",
                exclude: ["README.md", "generate.sh"],
                resources: [
                    .embedInCode("Intermediates"),
                    .embedInCode("Roots"),
                ]),
    ]
)
