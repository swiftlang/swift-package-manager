import PackageDescription

let package = Package(
    name: "PackageName"
)

products.append(Product(name: "ProductName", type: .Library(.Static), modules: ["PackageName"]))
