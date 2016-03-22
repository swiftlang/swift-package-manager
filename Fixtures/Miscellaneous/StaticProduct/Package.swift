import PackageDescription

let package = Package(name: "Foo")

let archive = Product(name: "Bar", type: .Library(.Static), modules: "Foo")

products.append(archive)
