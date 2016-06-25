import PackageDescription

let package = Package(dependencies: [
     .Package(url: "../Module", majorVersion: 1),
     .Package(url: "../ModuleMap", majorVersion: 1),
])
