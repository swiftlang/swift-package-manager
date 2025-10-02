<<<<<<< HEAD
// swift-tools-version:999.0.0
=======
// swift-tools-version: 6.3.0
>>>>>>> inbetween
import PackageDescription

let initialLibrary: [Target] = .template(
        name: "initialTypeLibrary",
        dependencies: [],
        initialPackageType: .library,
        description: ""
    )


let initialExecutable: [Target] = .template(
        name: "initialTypeExecutable",
        dependencies: [],
        initialPackageType: .executable,
        description: ""
    )


let initialTool: [Target] = .template(
        name: "initialTypeTool",
        dependencies: [],
        initialPackageType: .tool,
        description: ""
    )


let initialBuildToolPlugin: [Target] = .template(
        name: "initialTypeBuildToolPlugin",
        dependencies: [],
        initialPackageType: .buildToolPlugin,
        description: ""
    )


let initialCommandPlugin: [Target] = .template(
        name: "initialTypeCommandPlugin",
        dependencies: [],
        initialPackageType: .commandPlugin,
        description: ""
    )


let initialMacro: [Target] = .template(
        name: "initialTypeMacro",
        dependencies: [],
        initialPackageType: .`macro`,
        description: ""
    )



let initialEmpty: [Target] = .template(
        name: "initialTypeEmpty",
        dependencies: [],
        initialPackageType: .empty,
        description: ""
    )

var products: [Product] = .template(name: "initialTypeLibrary") 

products += .template(name: "initialTypeExecutable")
products += .template(name: "initialTypeTool")
products += .template(name: "initialTypeBuildToolPlugin")
products += .template(name: "initialTypeCommandPlugin")
products += .template(name: "initialTypeMacro")
products += .template(name: "initialTypeEmpty")

let package = Package(
    name: "InferPackageType",
    products: products,
    targets: initialLibrary + initialExecutable + initialTool + initialBuildToolPlugin + initialCommandPlugin + initialMacro + initialEmpty
)
