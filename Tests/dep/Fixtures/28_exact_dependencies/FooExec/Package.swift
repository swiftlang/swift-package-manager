import PackageDescription

let package = Package(
    name: "FooExec",
    dependencies: [
		.Package(url: "../FooLib1", majorVersion: 1),
		.Package(url: "../FooLib2", majorVersion: 1),
	])
