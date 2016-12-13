import PackageDescription

let package = Package(
    name: "PackageWithInvalidXcodeNameModules",
    targets: [
        Target(name: "Headers", dependencies: ["Modules"])]
)
