// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageE",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageE",
			targets: ["PackageE"]
		),
	],
	dependencies: [
		.package(path: "../PackageA"), .package(path: "../PackageB"), .package(path: "../PackageC"), .package(path: "../PackageD")
	],
	targets: [
		.target(
			name: "PackageE",
			dependencies: [
				"PackageA", "PackageB", "PackageC", "PackageD"
			])
	]
)