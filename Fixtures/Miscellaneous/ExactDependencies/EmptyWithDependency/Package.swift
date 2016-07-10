import PackageDescription

let package = Package(
    name: "EmptyWithDependency",
    dependencies: [
		.Package(url: "../FooLib2", majorVersion: 1),
	])
