import PackageDescription

let package = Package(
    name: "ExtraCommandLineFlags",
    targets: [
        Target(name: "SwiftExec", dependencies: ["CLib"])])
