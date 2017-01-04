import PackageDescription

let package = Package(
    name: "packageName",
    products: [
        .Library(name: "ProductName", type: .dynamic, targets: ["packageName"]),
    ]
)
