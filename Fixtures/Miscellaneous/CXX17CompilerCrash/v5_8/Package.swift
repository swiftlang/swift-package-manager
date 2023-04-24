// swift-tools-version:5.8.0

import PackageDescription

let package = Package(
    name: "CXX17WithFModules",
    targets: [
        .target(
            name: "lodepng",
            path: "lodepng",
            sources: ["lodepng.cpp"],
            publicHeadersPath: "include"),
        .target(name: "CXX17WithFModules", dependencies: ["lodepng"], path: "./", sources: ["src/user_objects.cc"], publicHeadersPath: "include"),
    ],
    cxxLanguageStandard: .cxx17
)
