// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageJ",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageJ",
			targets: ["PackageJ"]
		),
	],
	dependencies: [
		.package(path: "../PackageA"), .package(path: "../PackageB"), .package(path: "../PackageC"), .package(path: "../PackageD"), .package(path: "../PackageE"), .package(path: "../PackageF"), .package(path: "../PackageG"), .package(path: "../PackageH"), .package(path: "../PackageI")
	],
	targets: [
		.target(
			name: "PackageJ",
			dependencies: [
				"PackageA", "PackageB", "PackageC", "PackageD", "PackageE", "PackageF", "PackageG", "PackageH", "PackageI"
			])
	]
)