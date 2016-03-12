import PackageDescription

let package = Package(
    name: "Bar",
    dependencies: [
        .Package(url: "../Foo", majorVersion: 1)
	]
)
