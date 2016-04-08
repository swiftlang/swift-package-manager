import PackageDescription

let package = Package(targets: [
    Target(name: "Module Name 2", dependencies: ["Module Name 1"])
])