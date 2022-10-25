// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageK",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageK",
			targets: ["PackageK"]
		),
	],
	dependencies: [
		.package(path: "../PackageA"), .package(path: "../PackageB"), .package(path: "../PackageC"), .package(path: "../PackageD"), .package(path: "../PackageE"), .package(path: "../PackageF"), .package(path: "../PackageG"), .package(path: "../PackageH"), .package(path: "../PackageI"), .package(path: "../PackageJ")
	],
	targets: [
		.target(
			name: "PackageK",
			dependencies: [
				"PackageA", "PackageB", "PackageC", "PackageD", "PackageE", "PackageF", "PackageG", "PackageH", "PackageI", "PackageJ"
			])
	]
)