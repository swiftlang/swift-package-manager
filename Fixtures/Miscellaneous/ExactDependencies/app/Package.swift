import PackageDescription

let package = Package(
    name: "28_exact_dependencies",
    dependencies: [
		.Package(url: "../FooExec", majorVersion: 1),
	])
