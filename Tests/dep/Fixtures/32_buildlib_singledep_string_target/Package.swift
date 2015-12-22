import PackageDescription

let package = Package(
    name: "32_buildlib_singledep_string_target",
    targets: [
        Target(
            name: "BarLib",
            dependencies: ["FooLib"]),
        Target(
            name: "FooLib")])