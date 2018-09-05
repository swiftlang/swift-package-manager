// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "SimpleExample",
    products: [
        // Export the codegen extension.
        .packageExtension(name: "CodeGenExtension"),
    ],
    dependencies: [
        // Dependency on SwiftLint that contains the package extension that provides
        // the SwiftLintBuildRule.
    ],
    targets: [
        // A custom codegen tool that generates a Swift function that prints the
        // contents of the input files.
        .target(name: "codegen-tool"),

        // The package extension that integrates the codegen tool with SwiftPM.
        .packageExtension(
            name: "CodeGenExtension",
            dependencies: ["codegen-tool"]
        ),

        // An example executable target.
        .target(
            name: "example",
            sources: [
                "main.swift",
                .build("*.codegen", withBuildRule: "MyCodeGenRule"),
                .build("main.swift", withBuildRule: "SwiftLintBuildRule"),
            ]
        ),
    ]
)
