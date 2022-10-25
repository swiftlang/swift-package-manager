// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageY",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageY",
			targets: ["PackageY"]
		),
	],
	dependencies: [
		.package(path: "../PackageA"), .package(path: "../PackageB"), .package(path: "../PackageC"), .package(path: "../PackageD"), .package(path: "../PackageE"), .package(path: "../PackageF"), .package(path: "../PackageG"), .package(path: "../PackageH"), .package(path: "../PackageI"), .package(path: "../PackageJ"), .package(path: "../PackageK"), .package(path: "../PackageL"), .package(path: "../PackageM"), .package(path: "../PackageN"), .package(path: "../PackageO"), .package(path: "../PackageP"), .package(path: "../PackageQ"), .package(path: "../PackageR"), .package(path: "../PackageS"), .package(path: "../PackageT"), .package(path: "../PackageU"), .package(path: "../PackageV"), .package(path: "../PackageW"), .package(path: "../PackageX")
	],
	targets: [
		.target(
			name: "PackageY",
			dependencies: [
				"PackageA", "PackageB", "PackageC", "PackageD", "PackageE", "PackageF", "PackageG", "PackageH", "PackageI", "PackageJ", "PackageK", "PackageL", "PackageM", "PackageN", "PackageO", "PackageP", "PackageQ", "PackageR", "PackageS", "PackageT", "PackageU", "PackageV", "PackageW", "PackageX"
			])
	]
)