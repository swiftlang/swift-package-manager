// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageG",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageG",
			targets: ["PackageG"]
		),
	],
	dependencies: [
		.package(path: "../PackageA"), .package(path: "../PackageB"), .package(path: "../PackageC"), .package(path: "../PackageD"), .package(path: "../PackageE"), .package(path: "../PackageF")
	],
	targets: [
		.target(
			name: "PackageG",
			dependencies: [
				"PackageA", "PackageB", "PackageC", "PackageD", "PackageE", "PackageF"
			])
	]
)