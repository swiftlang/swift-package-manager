import PackageDescription

let package = Package(
    name: "ExtraArgsTarget",
    otherCompilerOptions: ["-D","GOT_EXTRA_ARG"],
    targets: [Target(name: "ExtraArgsTarget")]
)
