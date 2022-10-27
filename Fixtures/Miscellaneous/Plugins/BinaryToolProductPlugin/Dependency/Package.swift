// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "MyBinaryProduct",
    products: [
        .executable(
            name: "MyVendedSourceGenBuildTool",
            targets: ["MyVendedSourceGenBuildTool"]
        ),    
    ],
    targets: [
        .binaryTarget(
            name: "MyVendedSourceGenBuildTool",
            path: "Binaries/MyVendedSourceGenBuildTool.artifactbundle"
        ),
    ]
)
