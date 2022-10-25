// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageC",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageC",
			targets: ["PackageC"]
		),
	],
	dependencies: [
		.package(path: "../PackageA"), .package(path: "../PackageB")
	],
	targets: [
		.target(
			name: "PackageC",
			dependencies: [
				"PackageA", "PackageB"
			])
	]
)