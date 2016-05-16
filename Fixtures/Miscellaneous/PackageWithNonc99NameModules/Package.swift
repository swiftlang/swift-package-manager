import PackageDescription

let package = Package(
    name: "PackageWithNonc99NameModules",
    targets: [
        Target(name: "A-B", dependencies: ["B-C"])]
)
