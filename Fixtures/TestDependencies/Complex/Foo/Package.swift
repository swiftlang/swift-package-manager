import PackageDescription

let package = Package(
    name: "Foo",
    testDependencies: [
        .Package(url: "../TestingFooLib", majorVersion: 1)
    ]
)
