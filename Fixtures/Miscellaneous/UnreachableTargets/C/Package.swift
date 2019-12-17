// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "C",
    products: [
		.executable(name: "cexec", targets: ["CTarget"])
    ],
    targets: [
        .target(name: "CTarget", dependencies: [])
    ])
