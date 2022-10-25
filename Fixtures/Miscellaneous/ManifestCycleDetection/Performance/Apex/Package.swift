// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "Apex",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "Apex",
			targets: ["Apex"]
		),
	],
	dependencies: [
		.package(path: "../PackageZ")
	],
	targets: [
		.target(
			name: "Apex",
			dependencies: [
				"PackageZ"
			])
	]
)