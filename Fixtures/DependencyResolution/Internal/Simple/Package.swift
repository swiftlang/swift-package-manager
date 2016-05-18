import PackageDescription

let package = Package(targets: [
    Target(name: "Foo", dependencies: [.Target(name: "Bar")])
])
 
