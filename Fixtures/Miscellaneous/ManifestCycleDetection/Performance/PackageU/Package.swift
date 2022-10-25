// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageU",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageU",
			targets: ["PackageU"]
		),
	],
	dependencies: [
		.package(path: "../PackageA"), .package(path: "../PackageB"), .package(path: "../PackageC"), .package(path: "../PackageD"), .package(path: "../PackageE"), .package(path: "../PackageF"), .package(path: "../PackageG"), .package(path: "../PackageH"), .package(path: "../PackageI"), .package(path: "../PackageJ"), .package(path: "../PackageK"), .package(path: "../PackageL"), .package(path: "../PackageM"), .package(path: "../PackageN"), .package(path: "../PackageO"), .package(path: "../PackageP"), .package(path: "../PackageQ"), .package(path: "../PackageR"), .package(path: "../PackageS"), .package(path: "../PackageT")
	],
	targets: [
		.target(
			name: "PackageU",
			dependencies: [
				"PackageA", "PackageB", "PackageC", "PackageD", "PackageE", "PackageF", "PackageG", "PackageH", "PackageI", "PackageJ", "PackageK", "PackageL", "PackageM", "PackageN", "PackageO", "PackageP", "PackageQ", "PackageR", "PackageS", "PackageT"
			])
	]
)