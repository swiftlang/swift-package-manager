// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageB",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageB",
			targets: ["PackageB"]
		),
	],
	dependencies: [
		.package(path: "../PackageA")
	],
	targets: [
		.target(
			name: "PackageB",
			dependencies: [
				"PackageA"
			])
	]
)