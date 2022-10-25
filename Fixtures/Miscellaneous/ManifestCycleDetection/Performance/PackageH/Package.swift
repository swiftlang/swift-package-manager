// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageH",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageH",
			targets: ["PackageH"]
		),
	],
	dependencies: [
		.package(path: "../PackageA"), .package(path: "../PackageB"), .package(path: "../PackageC"), .package(path: "../PackageD"), .package(path: "../PackageE"), .package(path: "../PackageF"), .package(path: "../PackageG")
	],
	targets: [
		.target(
			name: "PackageH",
			dependencies: [
				"PackageA", "PackageB", "PackageC", "PackageD", "PackageE", "PackageF", "PackageG"
			])
	]
)