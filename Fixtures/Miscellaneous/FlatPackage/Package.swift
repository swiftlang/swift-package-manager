// swift-tools-version: 5.5
import PackageDescription

let execSrcFiles = ["MyExec.swift"]
let testSrcFiles = ["MyTest.swift"]
let variousFiles = ["README.md"]

let package = Package(
    name: "FlatPackage",
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "MyExec",
            dependencies: [],
            path: ".",
            exclude: testSrcFiles + variousFiles,
            sources: execSrcFiles
        ),
        .testTarget(
            name: "MyTest",
            dependencies: ["MyExec"],
            path: ".",
            exclude: execSrcFiles + variousFiles,
            sources: testSrcFiles
        ),
    ]
)
