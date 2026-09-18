// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "PublicLibraryTargets",
    targets: [
        .libraryTarget(name: "One", dependencies: ["Foo"], visibility: .public),
        .libraryTarget(name: "Two", dependencies: ["Bar", "Baz"], visibility: .public),
        .libraryTarget(name: "Quux", type: .static, visibility: .public),
        .target(name: "Foo"),
        .target(name: "Bar", dependencies: ["Baz"]),
        .target(name: "Baz"),
        .target(name: "Qux"),
        .executableTarget(name: "Exec", dependencies: ["Qux"])
    ]
)
