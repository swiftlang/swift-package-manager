import PackageDescription

let package = Package(
    name: "32_exclude_directory_with_targets",
    targets: [Target(name: "FooLib")],
    exclude: ["FooLib"]
)
