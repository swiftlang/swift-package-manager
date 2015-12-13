import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .Package(url: "../Foo", majorVersion: 1)
    ],
    privateDependencies: [
        .Package(url: "../PrivateLib", majorVersion: 1)
    ]
)
