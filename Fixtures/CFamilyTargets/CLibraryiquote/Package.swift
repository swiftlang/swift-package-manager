import PackageDescription

let package = Package(
    name: "CLibraryiquote",
    targets: [
		Target(name: "Bar", dependencies: ["Foo"]),
		Target(name: "Baz", dependencies: ["Foo", "Bar"])]
)
