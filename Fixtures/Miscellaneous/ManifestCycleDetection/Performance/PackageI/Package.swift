// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageI",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageI",
			targets: ["PackageI"]
		),
	],
	dependencies: [
		.package(path: "../PackageA"), .package(path: "../PackageB"), .package(path: "../PackageC"), .package(path: "../PackageD"), .package(path: "../PackageE"), .package(path: "../PackageF"), .package(path: "../PackageG"), .package(path: "../PackageH")
	],
	targets: [
		.target(
			name: "PackageI",
			dependencies: [
				"PackageA", "PackageB", "PackageC", "PackageD", "PackageE", "PackageF", "PackageG", "PackageH"
			])
	]
)