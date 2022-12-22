// swift-tools-version:5.8
import PackageDescription

// This package acts as a regression test for the FoundationlessPackages to
// assert that Swift targets with resources are not affected by using
// `@_implementationOnly import Foundation` in the generated resource accessor.
let package = Package(
    name: "UtilsWithFoundationPkg",
    targets: [
        .target(
            name: "UtilsWithFoundationPkg",
            resources: [
                .copy("foo.txt"),
            ]
        )
    ]
)
