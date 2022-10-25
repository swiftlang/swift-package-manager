// swift-tools-version: 5.7

import PackageDescription

let package = Package(
	name: "PackageA",
	platforms: [.macOS(.v11)],
	products: [
		.library(
			name: "PackageA",
			targets: ["PackageA"]
		),
	],
	dependencies: [
		
	],
	targets: [
		.target(
			name: "PackageA",
			dependencies: [
				
			])
	]
)