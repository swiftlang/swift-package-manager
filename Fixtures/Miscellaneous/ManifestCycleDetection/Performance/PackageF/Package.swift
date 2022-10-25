// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageF",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageF",
			targets: ["PackageF"]
		),
	],
	dependencies: [
		.package(path: "../PackageA"), .package(path: "../PackageB"), .package(path: "../PackageC"), .package(path: "../PackageD"), .package(path: "../PackageE")
	],
	targets: [
		.target(
			name: "PackageF",
			dependencies: [
				"PackageA", "PackageB", "PackageC", "PackageD", "PackageE"
			])
	]
)