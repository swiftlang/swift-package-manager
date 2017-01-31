import PackageDescription

let package = Package(
    name: "packageName"
)

products.append(Product(name: "ProductName", type: .Library(.Dynamic), modules: ["packageName"]))
