import PackageDescription

let package = Package(
    name: "HasEmptyDependency",
    dependencies: [
		.Package(url: "../EmptyWithDependency", majorVersion: 1),
	])
