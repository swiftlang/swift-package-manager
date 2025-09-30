// swift-tools-version:6.3.0
import PackageDescription


let testTargets: [Target] = [.testTarget(
    name: "ServerTemplateTests",
    dependencies: [
        "ServerTemplate",
    ]
)]


let package = Package(
    name: "SimpleTemplateExample",
    products:
            .template(name: "PartsService") +
            .template(name: "Template1") +
            .template(name: "Template2") +
            .template(name: "ServerTemplate"),
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "main"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.4.2"),
        .package(url: "https://github.com/stencilproject/Stencil.git", from: "0.15.1"),
    ],
    targets: testTargets + .template(
        name: "PartsService",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "SystemPackage", package: "swift-system"),
        ],
        
        initialPackageType: .executable,
        description: "This template generates a simple parts management service using Hummingbird, and Fluent!"
        
    ) + .template(
        name: "Template1",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "SystemPackage", package: "swift-system"),
        ],
        
        initialPackageType: .executable,
        templatePermissions: [
            .allowNetworkConnections(scope: .none, reason: "Need network access to help generate a template")
        ],
        description: "This is a simple template that uses Swift string interpolation."
        
    ) + .template(
        name: "Template2",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "SystemPackage", package: "swift-system"),
            .product(name: "Stencil", package: "Stencil")
            
        ],
        resources: [
            .process("StencilTemplates")
        ],
        initialPackageType: .executable,
        description: "This is a template that uses Stencil templating."
        
    ) + .template(
        name: "ServerTemplate",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "SystemPackage", package: "swift-system"),
        ],
        initialPackageType: .executable,
        description: "A set of starter Swift Server projects."
    )
)
