// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "AtMainSupport",
    products: [
        .executable(name: "ClangExecSingleFile", targets: ["ClangExecSingleFile"]),
        .executable(name: "SwiftExecSingleFile", targets: ["SwiftExecSingleFile"]),
        .executable(name: "SwiftExecMultiFile", targets: ["SwiftExecMultiFile"]),
    ],
    targets: [
        .executableTarget(name: "ClangExecSingleFile",
        linkerSettings: [
                .linkedLibrary("swiftCore", .when(platforms: [.windows])), // for swift_addNewDSOImage
            ]),
        .executableTarget(name: "SwiftExecSingleFile"),
        .executableTarget(name: "SwiftExecMultiFile"),
    ]
)
