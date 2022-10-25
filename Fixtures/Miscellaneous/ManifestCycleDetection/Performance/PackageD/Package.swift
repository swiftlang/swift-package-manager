// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageD",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageD",
			targets: ["PackageD"]
		),
	],
	dependencies: [
		.package(path: "../PackageA"), .package(path: "../PackageB"), .package(path: "../PackageC")
	],
	targets: [
		.target(
			name: "PackageD",
			dependencies: [
				"PackageA", "PackageB", "PackageC"
			])
	]
)