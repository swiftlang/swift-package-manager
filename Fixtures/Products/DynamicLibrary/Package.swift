import PackageDescription

let package = Package(name: "packageName")

products.append(Product(name: "productName", type: .Library(.Dynamic), modules: ["packageName"]))
