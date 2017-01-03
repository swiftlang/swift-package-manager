import PackageDescription

let package = Package(
    name: "PackageName",
    products: [
        .Library(name: "ProductName", type: .static, targets: ["PackageName"]),
    ]
)
