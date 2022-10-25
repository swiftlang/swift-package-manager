// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageM",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageM",
			targets: ["PackageM"]
		),
	],
	dependencies: [
		.package(path: "../PackageA"), .package(path: "../PackageB"), .package(path: "../PackageC"), .package(path: "../PackageD"), .package(path: "../PackageE"), .package(path: "../PackageF"), .package(path: "../PackageG"), .package(path: "../PackageH"), .package(path: "../PackageI"), .package(path: "../PackageJ"), .package(path: "../PackageK"), .package(path: "../PackageL")
	],
	targets: [
		.target(
			name: "PackageM",
			dependencies: [
				"PackageA", "PackageB", "PackageC", "PackageD", "PackageE", "PackageF", "PackageG", "PackageH", "PackageI", "PackageJ", "PackageK", "PackageL"
			])
	]
)