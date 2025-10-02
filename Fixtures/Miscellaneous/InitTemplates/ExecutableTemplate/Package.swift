<<<<<<< HEAD
// swift-tools-version:999.0.0
=======
// swift-tools-version:6.3.0
>>>>>>> inbetween
import PackageDescription


let package = Package(
    name: "SimpleTemplateExample",
    products:
            .template(name: "ExecutableTemplate"),
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.4.2"),
    ],
    targets: .template(
        name: "ExecutableTemplate",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "SystemPackage", package: "swift-system"),
        ],
        
        initialPackageType: .executable,
        description: "This is a simple template that uses Swift string interpolation."
    )
)
