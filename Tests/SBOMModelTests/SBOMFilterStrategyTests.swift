//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@testable import SBOMModel
import Testing

@Suite(
    .tags(
        .Feature.SBOM
    )
)
struct SBOMFilterStrategyTests {
    
    // MARK: - Helper Methods
    
    private func createTestComponent(
        id: String,
        name: String,
        entity: SBOMComponent.Entity,
        scope: SBOMComponent.Scope = .runtime
    ) -> SBOMComponent {
        return SBOMComponent(
            category: .library,
            id: SBOMIdentifier(value: id),
            purl: PURL(scheme: "pkg", type: "swift", name: name),
            name: name,
            version: SBOMComponent.Version(revision: "1.0.0"),
            originator: SBOMOriginator(),
            scope: scope,
            entity: entity
        )
    }
    
    // MARK: - AllFilterStrategy Tests
    
    @Test("AllFilterStrategy includes all components")
    func allFilterIncludesAllComponents() {
        let strategy = AllFilterStrategy()
        let primaryPackage = createTestComponent(id: "root", name: "Root", entity: .package)
        
        let packageComponent = createTestComponent(id: "pkg1", name: "Package1", entity: .package)
        let productComponent = createTestComponent(id: "root:prod1", name: "Product1", entity: .product)
        
        #expect(strategy.shouldIncludeComponent(packageComponent, primaryComponent: primaryPackage))
        #expect(strategy.shouldIncludeComponent(productComponent, primaryComponent: primaryPackage))
        #expect(strategy.shouldIncludeComponent(primaryPackage, primaryComponent: primaryPackage))
    }
    
    @Test("AllFilterStrategy tracks all relationships except self-referential")
    func allFilterTracksAllRelationships() {
        let strategy = AllFilterStrategy()
        let primaryPackage = createTestComponent(id: "root", name: "Root", entity: .package)
        
        let parent = createTestComponent(id: "parent", name: "Parent", entity: .package)
        let child = createTestComponent(id: "child", name: "Child", entity: .package)
        let product = createTestComponent(id: "root:prod", name: "Product", entity: .product)
        let product2 = createTestComponent(id: "root:prod2", name: "Product2", entity: .product)
        
        // Should track package-to-package, package-to-product, and product-to-product
        #expect(strategy.shouldTrackRelationship(parent: parent, child: child, primaryComponent: primaryPackage))
        #expect(strategy.shouldTrackRelationship(parent: parent, child: product, primaryComponent: primaryPackage))
        #expect(strategy.shouldTrackRelationship(parent: parent, child: product2, primaryComponent: primaryPackage))

        // Should NOT track self-referential
        #expect(!strategy.shouldTrackRelationship(parent: product, child: product, primaryComponent: primaryPackage))
        #expect(!strategy.shouldTrackRelationship(parent: parent, child: parent, primaryComponent: primaryPackage))
    }
    
    // MARK: - ProductFilterStrategy Tests
    
    @Test("ProductFilterStrategy includes only products and root package when primary component is package")
    func productFilterIncludesOnlyProductsWhenPrimaryIsPackage() {
        let strategy = ProductFilterStrategy()
        let primaryPackage = createTestComponent(id: "root", name: "Root", entity: .package)
        
        let packageComponent = createTestComponent(id: "pkg1", name: "Package1", entity: .package)
        let productComponent = createTestComponent(id: "root:prod1", name: "Product1", entity: .product)
        let otherProduct = createTestComponent(id: "pkg1:prod2", name: "Product2", entity: .product)
        
        // Should include the primary package
        #expect(strategy.shouldIncludeComponent(primaryPackage, primaryComponent: primaryPackage))
        
        // Should include products
        #expect(strategy.shouldIncludeComponent(productComponent, primaryComponent: primaryPackage))
        #expect(strategy.shouldIncludeComponent(otherProduct, primaryComponent: primaryPackage))
        
        // Should NOT include other packages
        #expect(!strategy.shouldIncludeComponent(packageComponent, primaryComponent: primaryPackage))
    }
    
    @Test("ProductFilterStrategy includes only products when primary is product")
    func productFilterIncludesOnlyProductsWhenPrimaryIsProduct() {
        let strategy = ProductFilterStrategy()
        let primaryProduct = createTestComponent(id: "root:main", name: "Main", entity: .product)
        
        let packageComponent = createTestComponent(id: "pkg1", name: "Package1", entity: .package)
        let productComponent = createTestComponent(id: "root:prod1", name: "Product1", entity: .product)
        let otherProduct = createTestComponent(id: "pkg1:prod2", name: "Product2", entity: .product)
        
        // Should include products
        #expect(strategy.shouldIncludeComponent(primaryProduct, primaryComponent: primaryProduct))
        #expect(strategy.shouldIncludeComponent(productComponent, primaryComponent: primaryProduct))
        #expect(strategy.shouldIncludeComponent(otherProduct, primaryComponent: primaryProduct))
        
        // Should NOT include packages
        #expect(!strategy.shouldIncludeComponent(packageComponent, primaryComponent: primaryProduct))
    }
    
    @Test("ProductFilterStrategy tracks product-to-product relationships")
    func productFilterTracksProductToProductRelationships() {
        let strategy = ProductFilterStrategy()
        let primaryProduct = createTestComponent(id: "root:main", name: "Main", entity: .product)
        
        let product1 = createTestComponent(id: "root:prod1", name: "Product1", entity: .product)
        let product2 = createTestComponent(id: "pkg1:prod2", name: "Product2", entity: .product)
        
        // Should track product-to-product
        #expect(strategy.shouldTrackRelationship(parent: product1, child: product2, primaryComponent: primaryProduct))
        #expect(strategy.shouldTrackRelationship(parent: primaryProduct, child: product1, primaryComponent: primaryProduct))
    }
    
    @Test("ProductFilterStrategy tracks root-package-to-product when primary is package")
    func productFilterTracksRootPackageToProductWhenPrimaryIsPackage() {
        let strategy = ProductFilterStrategy()
        let primaryPackage = createTestComponent(id: "root", name: "Root", entity: .package)
        
        let product = createTestComponent(id: "root:prod", name: "Product", entity: .product)
        let otherPackage = createTestComponent(id: "pkg1", name: "Package1", entity: .package)
        
        // Should track root-package-to-product
        #expect(strategy.shouldTrackRelationship(parent: primaryPackage, child: product, primaryComponent: primaryPackage))
        
        // Should NOT track other package-to-product
        #expect(!strategy.shouldTrackRelationship(parent: otherPackage, child: product, primaryComponent: primaryPackage))
    }
    
    @Test("ProductFilterStrategy does not track package-to-package relationships")
    func productFilterDoesNotTrackPackageToPackageRelationships() {
        let strategy = ProductFilterStrategy()
        let primaryPackage = createTestComponent(id: "root", name: "Root", entity: .package)
        
        let package1 = createTestComponent(id: "pkg1", name: "Package1", entity: .package)
        let package2 = createTestComponent(id: "pkg2", name: "Package2", entity: .package)
        
        // Should NOT track package-to-package
        #expect(!strategy.shouldTrackRelationship(parent: package1, child: package2, primaryComponent: primaryPackage))
        #expect(!strategy.shouldTrackRelationship(parent: primaryPackage, child: package1, primaryComponent: primaryPackage))
    }
    
    @Test("ProductFilterStrategy prevents self-referential relationships")
    func productFilterPreventsSelfReferentialRelationships() {
        let strategy = ProductFilterStrategy()
        let primaryProduct = createTestComponent(id: "root:main", name: "Main", entity: .product)
        
        let product = createTestComponent(id: "root:prod", name: "Product", entity: .product)
        
        // Should NOT track self-referential
        #expect(!strategy.shouldTrackRelationship(parent: product, child: product, primaryComponent: primaryProduct))
        #expect(!strategy.shouldTrackRelationship(parent: primaryProduct, child: primaryProduct, primaryComponent: primaryProduct))
    }
    
    // MARK: - PackageFilterStrategy Tests
    
    @Test("PackageFilterStrategy includes only packages when primary is package")
    func packageFilterIncludesOnlyPackagesWhenPrimaryIsPackage() {
        let strategy = PackageFilterStrategy()
        let primaryPackage = createTestComponent(id: "root", name: "Root", entity: .package)
        
        let packageComponent = createTestComponent(id: "pkg1", name: "Package1", entity: .package)
        let productComponent = createTestComponent(id: "root:prod1", name: "Product1", entity: .product)
        
        // Should include packages
        #expect(strategy.shouldIncludeComponent(primaryPackage, primaryComponent: primaryPackage))
        #expect(strategy.shouldIncludeComponent(packageComponent, primaryComponent: primaryPackage))
        
        // Should NOT include products
        #expect(!strategy.shouldIncludeComponent(productComponent, primaryComponent: primaryPackage))
    }
    
    @Test("PackageFilterStrategy includes packages and primary product when primary is product")
    func packageFilterIncludesPackagesAndPrimaryProductWhenPrimaryIsProduct() {
        let strategy = PackageFilterStrategy()
        let primaryProduct = createTestComponent(id: "root:main", name: "Main", entity: .product)
        
        let packageComponent = createTestComponent(id: "pkg1", name: "Package1", entity: .package)
        let otherProduct = createTestComponent(id: "root:prod1", name: "Product1", entity: .product)
        
        // Should include the primary product
        #expect(strategy.shouldIncludeComponent(primaryProduct, primaryComponent: primaryProduct))
        
        // Should include packages
        #expect(strategy.shouldIncludeComponent(packageComponent, primaryComponent: primaryProduct))
        
        // Should NOT include other products
        #expect(!strategy.shouldIncludeComponent(otherProduct, primaryComponent: primaryProduct))
    }
    
    @Test("PackageFilterStrategy tracks package-to-package relationships")
    func packageFilterTracksPackageToPackageRelationships() {
        let strategy = PackageFilterStrategy()
        let primaryPackage = createTestComponent(id: "root", name: "Root", entity: .package)
        
        let package1 = createTestComponent(id: "pkg1", name: "Package1", entity: .package)
        let package2 = createTestComponent(id: "pkg2", name: "Package2", entity: .package)
        
        // Should track package-to-package
        #expect(strategy.shouldTrackRelationship(parent: package1, child: package2, primaryComponent: primaryPackage))
        #expect(strategy.shouldTrackRelationship(parent: primaryPackage, child: package1, primaryComponent: primaryPackage))
    }
    
    @Test("PackageFilterStrategy tracks package-to-primary-product when primary is product")
    func packageFilterTracksPackageToPrimaryProductWhenPrimaryIsProduct() {
        let strategy = PackageFilterStrategy()
        let primaryProduct = createTestComponent(id: "root:main", name: "Main", entity: .product)
        
        let package = createTestComponent(id: "pkg1", name: "Package1", entity: .package)
        let otherProduct = createTestComponent(id: "root:other", name: "Other", entity: .product)
        
        // Should track package-to-primary-product
        #expect(strategy.shouldTrackRelationship(parent: package, child: primaryProduct, primaryComponent: primaryProduct))
        
        // Should NOT track package-to-other-product
        #expect(!strategy.shouldTrackRelationship(parent: package, child: otherProduct, primaryComponent: primaryProduct))
    }
    
    @Test("PackageFilterStrategy does not track product-to-product relationships")
    func packageFilterDoesNotTrackProductToProductRelationships() {
        let strategy = PackageFilterStrategy()
        let primaryProduct = createTestComponent(id: "root:main", name: "Main", entity: .product)
        
        let product1 = createTestComponent(id: "root:prod1", name: "Product1", entity: .product)
        let product2 = createTestComponent(id: "pkg1:prod2", name: "Product2", entity: .product)
        
        // Should NOT track product-to-product
        #expect(!strategy.shouldTrackRelationship(parent: product1, child: product2, primaryComponent: primaryProduct))
        #expect(!strategy.shouldTrackRelationship(parent: primaryProduct, child: product1, primaryComponent: primaryProduct))
    }
    
    @Test("PackageFilterStrategy prevents self-referential relationships")
    func packageFilterPreventsSelfReferentialRelationships() {
        let strategy = PackageFilterStrategy()
        let primaryPackage = createTestComponent(id: "root", name: "Root", entity: .package)
        
        let package = createTestComponent(id: "pkg1", name: "Package1", entity: .package)
        
        // Should NOT track self-referential
        #expect(!strategy.shouldTrackRelationship(parent: package, child: package, primaryComponent: primaryPackage))
        #expect(!strategy.shouldTrackRelationship(parent: primaryPackage, child: primaryPackage, primaryComponent: primaryPackage))
    }
    
    // MARK: - Filter Extension Tests
    
    @Test("Filter.all creates AllFilterStrategy")
    func filterAllCreatesAllFilterStrategy() {
        let strategy = Filter.all.createStrategy()
        #expect(strategy is AllFilterStrategy)
    }
    
    @Test("Filter.product creates ProductFilterStrategy")
    func filterProductCreatesProductFilterStrategy() {
        let strategy = Filter.product.createStrategy()
        #expect(strategy is ProductFilterStrategy)
    }
    
    @Test("Filter.package creates PackageFilterStrategy")
    func filterPackageCreatesPackageFilterStrategy() {
        let strategy = Filter.package.createStrategy()
        #expect(strategy is PackageFilterStrategy)
    }
    
    // MARK: - Cross-Strategy Comparison Tests
    
    @Test("Different strategies have different component inclusion behavior")
    func differentStrategiesHaveDifferentComponentInclusion() {
        let allStrategy = AllFilterStrategy()
        let productStrategy = ProductFilterStrategy()
        let packageStrategy = PackageFilterStrategy()
        
        let primaryPackage = createTestComponent(id: "root", name: "Root", entity: .package)
        let packageComponent = createTestComponent(id: "pkg1", name: "Package1", entity: .package)
        let productComponent = createTestComponent(id: "root:prod", name: "Product", entity: .product)
        
        // All strategy includes everything
        #expect(allStrategy.shouldIncludeComponent(packageComponent, primaryComponent: primaryPackage))
        #expect(allStrategy.shouldIncludeComponent(productComponent, primaryComponent: primaryPackage))
        
        // Product strategy excludes non-primary packages
        #expect(!productStrategy.shouldIncludeComponent(packageComponent, primaryComponent: primaryPackage))
        #expect(productStrategy.shouldIncludeComponent(productComponent, primaryComponent: primaryPackage))
        
        // Package strategy excludes products
        #expect(packageStrategy.shouldIncludeComponent(packageComponent, primaryComponent: primaryPackage))
        #expect(!packageStrategy.shouldIncludeComponent(productComponent, primaryComponent: primaryPackage))
    }
    
    @Test("Different strategies have different relationship tracking behavior")
    func differentStrategiesHaveDifferentRelationshipTracking() {
        let allStrategy = AllFilterStrategy()
        let productStrategy = ProductFilterStrategy()
        let packageStrategy = PackageFilterStrategy()
        
        let primaryPackage = createTestComponent(id: "root", name: "Root", entity: .package)
        let package1 = createTestComponent(id: "pkg1", name: "Package1", entity: .package)
        let package2 = createTestComponent(id: "pkg2", name: "Package2", entity: .package)
        let product1 = createTestComponent(id: "root:prod1", name: "Product1", entity: .product)
        let product2 = createTestComponent(id: "pkg1:prod2", name: "Product2", entity: .product)
        
        // Package-to-package relationships
        #expect(allStrategy.shouldTrackRelationship(parent: package1, child: package2, primaryComponent: primaryPackage))
        #expect(!productStrategy.shouldTrackRelationship(parent: package1, child: package2, primaryComponent: primaryPackage))
        #expect(packageStrategy.shouldTrackRelationship(parent: package1, child: package2, primaryComponent: primaryPackage))
        
        // Product-to-product relationships
        #expect(allStrategy.shouldTrackRelationship(parent: product1, child: product2, primaryComponent: primaryPackage))
        #expect(productStrategy.shouldTrackRelationship(parent: product1, child: product2, primaryComponent: primaryPackage))
        #expect(!packageStrategy.shouldTrackRelationship(parent: product1, child: product2, primaryComponent: primaryPackage))
    }
}