import PackageDescription

let package = Package(
    name: "ModuleMapGenerationCases",
    targets: [
		Target(name: "Baz", dependencies: ["FlatInclude", "UmbrellaHeader", "UmbellaModuleNameInclude", "UmbrellaHeaderFlat"])]
)
