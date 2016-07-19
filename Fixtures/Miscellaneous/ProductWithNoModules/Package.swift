import PackageDescription

let package = Package(name: "Foo")

let archive = Product(name: "Bar", type: .Library(.Dynamic), modules: [])

products.append(archive)
