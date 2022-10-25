// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageQ",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageQ",
			targets: ["PackageQ"]
		),
	],
	dependencies: [
		.package(path: "../PackageA"), .package(path: "../PackageB"), .package(path: "../PackageC"), .package(path: "../PackageD"), .package(path: "../PackageE"), .package(path: "../PackageF"), .package(path: "../PackageG"), .package(path: "../PackageH"), .package(path: "../PackageI"), .package(path: "../PackageJ"), .package(path: "../PackageK"), .package(path: "../PackageL"), .package(path: "../PackageM"), .package(path: "../PackageN"), .package(path: "../PackageO"), .package(path: "../PackageP")
	],
	targets: [
		.target(
			name: "PackageQ",
			dependencies: [
				"PackageA", "PackageB", "PackageC", "PackageD", "PackageE", "PackageF", "PackageG", "PackageH", "PackageI", "PackageJ", "PackageK", "PackageL", "PackageM", "PackageN", "PackageO", "PackageP"
			])
	]
)