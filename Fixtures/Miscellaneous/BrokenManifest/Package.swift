// swift-tools-version:5.9
import PackageDescription

let foo: Int = "this is not an int"

let package = Package(
    name: "BrokenManifest",
    targets: [
        .target(name: "MyLib"),
    ]
)
