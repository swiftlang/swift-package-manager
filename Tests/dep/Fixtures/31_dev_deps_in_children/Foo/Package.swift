import PackageDescription

let package = Package(
    name: "Foo",
    devDependencies: [
        .Package(url: "../PrivateFooLib", majorVersion: 1)
    ]
)
