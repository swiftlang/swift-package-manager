// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "A",
    products: [
        .executable(name: "aexec", targets: ["ATarget"])
    ],
	dependencies: [
		.package(url: "../B", from: "1.0.0"),
		.package(url: "../C", from: "1.0.0")
	],
    targets: [
        .target(name: "ATarget", dependencies: [
			.product(name: "BLibrary")
		])
    ])
