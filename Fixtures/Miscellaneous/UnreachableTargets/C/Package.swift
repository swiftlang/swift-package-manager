// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "C",
    products: [
		.executable(name: "cexec", targets: ["CTarget"])
    ],
    targets: [
        .target(name: "CTarget", dependencies: [])
    ])
