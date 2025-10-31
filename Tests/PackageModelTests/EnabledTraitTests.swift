//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing
import struct PackageModel.EnabledTrait
import struct PackageModel.EnabledTraits
import struct PackageModel.EnabledTraitsMap
import struct PackageModel.PackageIdentity
import class PackageModel.Manifest

@Suite
struct EnabledTraitTests {

    // MARK: - EnabledTrait Tests

    /// Verifies that `EnabledTrait` equality is based solely on the trait name, not the setter.
    /// Two traits with the same name but different setters are equal, while traits with different names are not equal.
    @Test
    func enabledTrait_checkEquality() {
        let appleTraitSetByApplePie = EnabledTrait.init(name: "Apple", setBy: .package(.init(identity: "ApplePie")))
        let appleTraitSetByAppleJuice = EnabledTrait.init(name: "Apple", setBy: .trait("AppleJuice"))
        let appleCoreTrait = EnabledTrait.init(name: "AppleCore", setBy: .default)

        #expect(appleTraitSetByApplePie == appleTraitSetByAppleJuice)
        #expect(appleCoreTrait != appleTraitSetByApplePie)
        #expect(appleCoreTrait != appleTraitSetByAppleJuice)
    }

    /// Tests that unifying two `EnabledTrait` instances with the same name merges their setters
    /// into a single set containing both original setters.
    @Test
    func enabledTrait_unifyEqualTraits() throws {
        let bananaTraitSetByFruit = EnabledTrait(name: "Banana", setBy: .package(.init(identity: "Fruit")))
        let bananaTraitSetByBread = EnabledTrait(name: "Banana", setBy: .trait("Bread"))

        let unifiedBananaTrait = try #require(bananaTraitSetByBread.unify(bananaTraitSetByFruit))
        let setters: Set<EnabledTrait.Setter> = [
            EnabledTrait.Setter.package(.init(identity: "Fruit")),
            EnabledTrait.Setter.trait(.init("Bread"))
        ]

        #expect(unifiedBananaTrait.setters == setters)
    }

    /// Verifies that attempting to unify two traits with different names returns `nil`,
    /// as they cannot be unified.
    @Test
    func enabledTrait_unifyDifferentTraits() {
        let bananaTrait = EnabledTrait(name: "Banana", setBy: .package(.init(identity: "Fruit")))
        let appleTrait = EnabledTrait(name: "Apple", setBy: .package(.init(identity: "Fruit")))

        let unifiedTrait = bananaTrait.unify(appleTrait)

        #expect(unifiedTrait == nil)
        #expect(bananaTrait.setters == appleTrait.setters)
    }

    /// Tests that `EnabledTrait` can be compared to a string literal for equality in both
    /// directions (trait == string and string == trait).
    @Test
    func enabledTrait_compareToStringLiteral() {
        let appleTrait = EnabledTrait(name: "Apple", setBy: .default)

        #expect("Apple" == appleTrait) // test when EnabledTrait rhs
        #expect(appleTrait == "Apple") // test when EnabledTrait lhs
    }

    /// Tests that `EnabledTrait` can be compared to a `String` for equality in both
    /// directions (trait == string and string == trait).
    @Test
    func enabledTrait_compareToStringAsEnabledTraitConvertible() {
        let appleTrait = EnabledTrait(name: "Apple", setBy: .default)
        let stringTrait = "Apple"

        #expect(stringTrait.asEnabledTrait == appleTrait) // test when EnabledTrait rhs
        #expect(appleTrait == stringTrait.asEnabledTrait) // test when EnabledTrait lhs
    }

    /// Verifies that an `EnabledTrait` can be initialized using a string literal and is
    /// equivalent to initialization with `setBy: .default`.
    @Test
    func enabledTrait_initializedByStringLiteral() {
        let appleTraitByString: EnabledTrait = "Apple"
        let appleTraitByInit = EnabledTrait(name: "Apple", setBy: .default)

        #expect(appleTraitByString == appleTraitByInit)
    }

    /// Confirms that the `id` property of an `EnabledTrait` equals its `name` property.
    @Test
    func enabledTrait_assertIdIsName() {
        let appleTrait = EnabledTrait(name: "Apple", setBy: .default)

        #expect(appleTrait.id == appleTrait.name)
    }

    /// Tests the `isDefault` property to verify that a trait named "default" is correctly
    /// identified as a default trait.
    @Test
    func enabledTrait_CheckIfDefault() {
        let defaultTrait: EnabledTrait = "default"

        #expect(defaultTrait.isDefault)
    }

    /// Verifies that `EnabledTrait` instances can be sorted alphabetically by name and
    /// compared using comparison operators (`<`, `>`).
    @Test
    func enabledTrait_SortAndCompare() {
        let appleTrait: EnabledTrait = "Apple"
        let bananaTrait: EnabledTrait = "Banana"
        let orangeTrait: EnabledTrait = "Orange"

        let traits = [orangeTrait, appleTrait, bananaTrait]
        let sortedTraits = traits.sorted()

        #expect(sortedTraits == [appleTrait, bananaTrait, orangeTrait])
        #expect(sortedTraits != traits)
        #expect(appleTrait < bananaTrait)
        #expect(orangeTrait > bananaTrait)
    }

    /// Tests the `parentPackages` property to ensure it correctly filters and returns only
    /// package-based setters, excluding trait and trait configuration setters.
    @Test
    func enabledTrait_getParentPackageSetters() throws {
        let traitSetByPackages = EnabledTrait(
            name: "Coffee",
            setBy: [
                .package(.init(identity: "Cafe")),
                .package(.init(identity:"Home")),
                .package(.init(identity: "Breakfast")),
                .trait("NotAPackage"),
                .traitConfiguration
            ])

        let parentPackagesFromTrait = traitSetByPackages.parentPackages
        let parentPackages = Set<Manifest.PackageIdentifier>([
            .init(identity: "Cafe"),
            .init(identity: "Home"),
            .init(identity: "Breakfast")
        ])

        #expect(Set(parentPackagesFromTrait) == parentPackages)
    }

    // MARK: - EnabledTraits Tests

    /// Verifies that `EnabledTraits` can be initialized from an array literal of strings,
    /// comparing it against another set of traits initialized by a list of `EnabledTrait`
    /// containing traits of the same names.
    @Test
    func enabledTraits_initWithStrings() {
        let enabledTraits: EnabledTraits = ["One", "Two", "Three"]
        let toTestAgainst = EnabledTraits([
            EnabledTrait(name: "One", setBy: .default),
            EnabledTrait(name: "Two", setBy: .default),
            EnabledTrait(name: "Three", setBy: .default)
        ])

        #expect(enabledTraits == toTestAgainst)
    }

    /// Tests the `.defaults` static property returns an `EnabledTraits` set containing
    /// only the "default" trait.
    @Test
    func enabledTraits_defaultSet() {
        let defaults: EnabledTraits = .defaults

        #expect(defaults == ["default"])
        #expect(defaults == [EnabledTrait(name: "default", setBy: .default)])
    }

    /// Verifies the `contains` method works with both string literals and `EnabledTrait` instances,
    /// and correctly identifies traits that are and aren't in the set.
    @Test
    func enabledTraits_containsTrait() {
        let enabledTraits: EnabledTraits = ["Apple", "Banana"]

        // Test against a string literal
        #expect(enabledTraits.contains("Apple"))

        // Test against an explicitly initialized EnabledTrait
        #expect(enabledTraits.contains(EnabledTrait(name: "Apple", setBy: .default)))

        // Test against string literal that is not in the set
        #expect(!enabledTraits.contains("Orange"))

        // Test against initialized EnabledTrait that is not in the set
        #expect(!enabledTraits.contains(EnabledTrait(name: "Pineapple", setBy: .trait("Apple"))))
    }

    /// Tests inserting a trait that already exists (unifying setters), removing it, and verifying
    /// the removed trait has the merged setters. Also tests inserting a new trait via string literal.
    @Test
    func enabledTraits_insertAndRemoveExistingTrait() throws {
        var enabledTraits: EnabledTraits = ["Apple", "Banana", "Orange"]

        let newTrait = EnabledTrait(name: "Apple", setBy: [.package(.init(identity: "Fruit")), .trait("FavouriteFruit")])

        // Assert amount of elements before adding trait
        #expect(enabledTraits.count == 3)

        // Insert trait; this should update the existing "Apple" trait by unifying its setters
        enabledTraits.insert(newTrait)
        #expect(enabledTraits.count == 3)
        #expect(enabledTraits == ["Apple", "Banana", "Orange"])


        // Assure that Apple trait is removed and returned
        let appleTrait = enabledTraits.remove("Apple")
        let unwrappedAppleTrait = try #require(appleTrait)
        #expect(enabledTraits.count == 2)
        #expect(!enabledTraits.contains("Apple"))

        // Assure that Apple trait now has updated setters
        #expect(unwrappedAppleTrait.setters == [.package(.init(identity: "Fruit")), .trait("FavouriteFruit")])

        // Insert trait via string literal
        enabledTraits.insert("MyStringTrait")
        #expect(enabledTraits.count == 3)
        #expect(enabledTraits.contains("MyStringTrait"))
    }

    /// Verifies that removing a non-existent trait returns `nil`, and inserting a new trait
    /// adds it to the set.
    @Test
    func enabledTraits_insertAndRemoveNonExistingTrait() throws {
        var enabledTraits: EnabledTraits = ["Banana"]

        let newTrait = EnabledTrait(name: "Apple", setBy: [.package(.init(identity: "Fruit")), .trait("FavouriteFruit")])


        // Try to remove Apple trait before inserting:
        #expect(enabledTraits.remove("Apple") == nil)
        #expect(enabledTraits.count == 1)

        // Insert trait
        enabledTraits.insert(newTrait)
        #expect(enabledTraits.count == 2)
        #expect(enabledTraits.contains("Apple"))
    }

    /// Tests the `map` method to transform each trait in the set by adding a new setter to each.
    @Test
    func enabledTraits_flatMapAgainstSetOfTraits() {
        let enabledTraits: EnabledTraits = ["Apple", "Coffee", "Cookie"]
        let transformedTraits = enabledTraits.map({ oldTrait in
            var newTrait = oldTrait
            newTrait.setters.insert(.package(.init(identity: "Breakfast")))
            return newTrait
        })

        #expect(
            transformedTraits == EnabledTraits([
                EnabledTrait(name: "Apple", setBy: .package(.init(identity: "Breakfast"))),
                EnabledTrait(name: "Coffee", setBy: .package(.init(identity: "Breakfast"))),
                EnabledTrait(name: "Cookie", setBy: .package(.init(identity: "Breakfast")))
            ])
        )
    }

    /// Verifies that unioning two sets with no overlapping traits combines them into a single larger set
    /// containing the traits of both sets.
    @Test
    func enabledTraits_unionWithNewTraits() {
        let enabledTraits: EnabledTraits = ["Banana"]
        let newTraits: EnabledTraits = ["Cookie", "Pancakes", "Milkshake"]

        let unifiedSetOfTraits = enabledTraits.union(newTraits)

        #expect(unifiedSetOfTraits.count == 4)
        #expect(unifiedSetOfTraits == ["Banana", "Cookie", "Pancakes", "Milkshake"])
    }

    /// Tests unioning sets with overlapping traits, verifying that duplicate traits have their
    /// setters merged correctly.
    @Test
    func enabledTraits_unionWithExistingTraits() throws {
        let enabledTraits: EnabledTraits = [
            EnabledTrait(name: "Banana", setBy: .default),
            EnabledTrait(name: "Apple", setBy: .package(.init(identity: "MyFruits")))
        ]
        let newTraits: EnabledTraits = [
            EnabledTrait(name: "Banana", setBy: [.package(.init(identity: "OtherFruits")), .trait("Bread")]),
            EnabledTrait(name: "Apple", setBy: .default),
            "Milkshake"
        ]

        var unifiedSetOfTraits = enabledTraits.union(newTraits)

        #expect(unifiedSetOfTraits.count == 3)
        #expect(unifiedSetOfTraits == ["Banana", "Apple", "Milkshake"])

        // Check each of the setters for each enabled trait, and assure
        // that they can be succesfully removed from the set.
        let bananaTrait = try unifiedSetOfTraits.unwrapRemove("Banana")

        #expect(unifiedSetOfTraits.count == 2)
        #expect(
            bananaTrait.setters == Set([
                .package(.init(identity: "OtherFruits")),
                .trait("Bread"),
                .default
            ])
        )

        let appleTrait = try unifiedSetOfTraits.unwrapRemove(EnabledTrait(name: "Apple", setBy: .default))
        #expect(unifiedSetOfTraits.count == 1)
        #expect(
            appleTrait.setters == Set([
                .package(.init(identity: "MyFruits")),
                .default
            ])
        )

        let milkshakeTrait = try unifiedSetOfTraits.unwrapRemove("Milkshake")
        #expect(unifiedSetOfTraits.isEmpty)
        #expect(milkshakeTrait.setters.isEmpty)
    }

    /// Verifies that initializing `EnabledTraits` with duplicate trait names in the array
    /// results in a single trait (set behavior).
    @Test
    func enabledTraits_testInitWithArrayOfSameString() throws {
        var traits: EnabledTraits = [
            "Banana",
            EnabledTrait(name: "Banana", setBy: .default),
            "Chocolate"
        ]

        #expect(traits.count == 2)
        #expect(traits.contains("Banana"))
        #expect(traits.contains("Chocolate"))

        let bananaTrait = try traits.unwrapRemove("Banana")
        #expect(traits.count == 1)
        #expect(traits.contains("Chocolate"))
        #expect(!traits.contains(bananaTrait))
    }

    /// Tests that intersecting with an empty set returns an empty set.
    @Test
    func enabledTraits_testIntersectionWithEmptySet() {
        let enabledTraits: EnabledTraits = ["Apple", "Banana", "Cheese"]
        let emptyTraits = EnabledTraits()

        let intersection = enabledTraits.intersection(emptyTraits)
        #expect(intersection.isEmpty)
    }

    /// Verifies that intersecting with an identical set returns the same set.
    @Test
    func enabledTraits_testIntersectionWithIdenticalSet() {
        let enabledTraits: EnabledTraits = ["Apple", "Banana", "Cheese"]
        let otherEnabledTraits: EnabledTraits = ["Apple", "Banana", "Cheese"]
        #expect(enabledTraits == otherEnabledTraits)

        let intersection = enabledTraits.intersection(otherEnabledTraits)
        #expect(intersection == enabledTraits)
        #expect(intersection == otherEnabledTraits)
    }

    /// Tests intersection of two sets with partial overlap, verifying only common traits are returned.
    @Test
    func enabledTraits_testIntersectionWithDifferentSets() throws {
        let enabledTraits: EnabledTraits = ["Apple", "Banana", "Orange"]
        var otherEnabledTraits: EnabledTraits = ["Banana", "Chocolate"]
        #expect(enabledTraits != otherEnabledTraits)
        
        let intersection = enabledTraits.intersection(otherEnabledTraits)
        #expect(intersection.count == 1)
        #expect(intersection.contains("Banana"))

        let bananaTrait = try otherEnabledTraits.unwrapRemove("Banana")
        #expect(!otherEnabledTraits.contains(bananaTrait))

        let newIntersection = enabledTraits.intersection(otherEnabledTraits)
        #expect(newIntersection.isEmpty)
    }

    /// Verifies intersection behavior with single-element sets containing the same trait.
    @Test
    func enabledTraits_testIntersectionWithOneElementSets() throws {
        let enabledTraits: EnabledTraits = ["Apple"]
        let otherEnabledTraits: EnabledTraits = [EnabledTrait(name: "Apple", setBy: .package(.init(identity: "MyFruits")))]
        #expect(enabledTraits == otherEnabledTraits)

        let intersection = enabledTraits.intersection(otherEnabledTraits)
        #expect(intersection.count == 1)
        #expect(intersection == enabledTraits)
        #expect(intersection == otherEnabledTraits)
    }

    // MARK: - EnabledTraitsMap Tests

    /// Tests basic initialization of an empty `EnabledTraitsMap` and verifies default trait behavior.
    @Test
    func enabledTraitsMap_initEmpty() {
        let map = EnabledTraitsMap()
        let packageId = PackageIdentity(stringLiteral: "MyPackage")

        // Accessing a non-existent package should return ["default"]
        #expect(map[packageId] == ["default"])
    }

    /// Verifies that `EnabledTraitsMap` can be initialized using dictionary literal syntax.
    @Test
    func enabledTraitsMap_initWithDictionaryLiteral() {
        let packageA = PackageIdentity(stringLiteral: "PackageA")
        let packageB = PackageIdentity(stringLiteral: "PackageB")

        let map: EnabledTraitsMap = [
            packageA: ["Apple", "Banana"],
            packageB: ["Coffee"]
        ]

        #expect(map[packageA] == ["Apple", "Banana"])
        #expect(map[packageB] == ["Coffee"])
    }

    /// Tests that `EnabledTraitsMap` can be initialized from a dictionary.
    @Test
    func enabledTraitsMap_initWithDictionary() {
        let packageA = PackageIdentity(stringLiteral: "PackageA")
        let packageB = PackageIdentity(stringLiteral: "PackageB")

        let dictionary: [PackageIdentity: EnabledTraits] = [
            packageA: ["Apple", "Banana"],
            packageB: ["Coffee"]
        ]

        let map = EnabledTraitsMap(dictionary)

        #expect(map[packageA] == ["Apple", "Banana"])
        #expect(map[packageB] == ["Coffee"])
    }

    /// Verifies that setting traits via subscript adds them to the map.
    @Test
    func enabledTraitsMap_setTraitsViaSubscript() {
        var map = EnabledTraitsMap()
        let packageId = PackageIdentity(stringLiteral: "MyPackage")

        map[packageId] = ["Apple", "Banana"]

        #expect(map[packageId] == ["Apple", "Banana"])
    }

    /// Tests that setting "default" traits explicitly does not store them in the map,
    /// since the map returns "default" by default for packages without explicitly
    /// set traits.
    @Test
    func enabledTraitsMap_setDefaultTraitsDoesNotStore() {
        var map = EnabledTraitsMap()
        let packageId = PackageIdentity(stringLiteral: "MyPackage")

        // Setting ["default"] should be omitted from storage
        map[packageId] = ["default"]

        // The package should still return ["default"] when accessed
        #expect(map[packageId] == ["default"])

        // But there should be no explicit entry in storage
        #expect(map[explicitlyEnabledTraitsFor: packageId] == nil)
    }

    /// Verifies that setting traits multiple times on the same package unifies them
    /// (forms union) rather than replacing them.
    @Test
    func enabledTraitsMap_multipleSetsCombineTraits() {
        var map = EnabledTraitsMap()
        let packageId = PackageIdentity(stringLiteral: "MyPackage")

        map[packageId] = ["Apple", "Banana"]
        map[packageId] = ["Coffee", "Chocolate"]

        // Should contain all four traits
        #expect(map[packageId].contains("Apple"))
        #expect(map[packageId].contains("Banana"))
        #expect(map[packageId].contains("Coffee"))
        #expect(map[packageId].contains("Chocolate"))
        #expect(map[packageId].count == 4)
    }

    /// Tests that setting overlapping traits unifies the setters correctly.
    @Test
    func enabledTraitsMap_overlappingTraitsUnifySetters() throws {
        var map = EnabledTraitsMap()
        let packageId = PackageIdentity(stringLiteral: "MyPackage")
        let parentPackage1 = PackageIdentity(stringLiteral: "Parent1")
        let parentPackage2 = PackageIdentity(stringLiteral: "Parent2")

        map[packageId] = EnabledTraits([
            EnabledTrait(name: "Apple", setBy: .package(.init(identity: parentPackage1)))
        ])

        map[packageId] = EnabledTraits([
            EnabledTrait(name: "Apple", setBy: .package(.init(identity: parentPackage2)))
        ])

        var traits = map[packageId]
        let appleTrait = try traits.unwrapRemove("Apple")

        // The Apple trait should have both setters
        #expect(appleTrait.setters.count == 2)
        #expect(appleTrait.setters.contains(.package(.init(identity: parentPackage1))))
        #expect(appleTrait.setters.contains(.package(.init(identity: parentPackage2))))
    }

    /// Verifies the `explicitlyEnabledTraitsFor` subscript returns `nil` for packages
    /// without explicitly set traits.
    @Test
    func enabledTraitsMap_explicitlyEnabledTraitsReturnsNilForDefault() {
        let map = EnabledTraitsMap()
        let packageId = PackageIdentity(stringLiteral: "MyPackage")

        // No traits have been set, so explicit traits should be nil
        #expect(map[explicitlyEnabledTraitsFor: packageId] == nil)

        // But regular subscript should return ["default"]
        #expect(map[packageId] == ["default"])
    }

    /// Tests that `explicitlyEnabledTraitsFor` returns the actual traits when they are set.
    @Test
    func enabledTraitsMap_explicitlyEnabledTraitsReturnsSetTraits() {
        var map = EnabledTraitsMap()
        let packageId = PackageIdentity(stringLiteral: "MyPackage")

        map[packageId] = ["Apple", "Banana"]

        let explicitTraits = map[explicitlyEnabledTraitsFor: packageId]

        #expect(explicitTraits != nil)
        #expect(explicitTraits == ["Apple", "Banana"])
    }

    /// Verifies that `dictionaryLiteral` property returns the underlying storage as a dictionary.
    @Test
    func enabledTraitsMap_dictionaryLiteralReturnsStorage() {
        var map = EnabledTraitsMap()
        let packageA = PackageIdentity(stringLiteral: "PackageA")
        let packageB = PackageIdentity(stringLiteral: "PackageB")

        map[packageA] = ["Apple", "Banana"]
        map[packageB] = ["Coffee"]

        let dictionary = map.dictionaryLiteral

        #expect(dictionary.count == 2)
        #expect(dictionary[packageA] == ["Apple", "Banana"])
        #expect(dictionary[packageB] == ["Coffee"])
    }

    /// Tests that after setting default traits explicitly, they are omitted from `dictionaryLiteral`.
    @Test
    func enabledTraitsMap_dictionaryLiteralOmitsDefaultTraits() {
        var map = EnabledTraitsMap()
        let packageA = PackageIdentity(stringLiteral: "PackageA")
        let packageB = PackageIdentity(stringLiteral: "PackageB")

        map[packageA] = ["Apple", "Banana"]
        map[packageB] = ["default"]  // Should not be stored

        let dictionary = map.dictionaryLiteral

        // Only PackageA should be in the dictionary
        #expect(dictionary.count == 1)
        #expect(dictionary[packageA] == ["Apple", "Banana"])
        #expect(dictionary[packageB] == nil)
    }

    /// Verifies behavior when mixing default and non-default traits in a single set operation.
    @Test
    func enabledTraitsMap_setMixedDefaultAndNonDefaultTraits() {
        var map = EnabledTraitsMap()
        let packageId = PackageIdentity(stringLiteral: "MyPackage")

        // Set traits including "default"
        map[packageId] = ["Apple", "default", "Banana"]

        // The traits should be stored since there are non-default traits
        #expect(map[packageId].contains("Apple"))
        #expect(map[packageId].contains("Banana"))
        #expect(map[packageId].contains("default"))

        // Should have explicit entry
        #expect(map[explicitlyEnabledTraitsFor: packageId] != nil)
    }

    /// Tests that multiple packages can be stored independently in the map.
    @Test
    func enabledTraitsMap_multiplePackagesIndependent() {
        var map = EnabledTraitsMap()
        let packageA = PackageIdentity(stringLiteral: "PackageA")
        let packageB = PackageIdentity(stringLiteral: "PackageB")
        let packageC = PackageIdentity(stringLiteral: "PackageC")

        map[packageA] = ["Apple"]
        map[packageB] = ["Banana"]
        // PackageC not set, should default

        #expect(map[packageA] == ["Apple"])
        #expect(map[packageB] == ["Banana"])
        #expect(map[packageC] == ["default"])

        #expect(map[explicitlyEnabledTraitsFor: packageA] != nil)
        #expect(map[explicitlyEnabledTraitsFor: packageB] != nil)
        #expect(map[explicitlyEnabledTraitsFor: packageC] == nil)
    }
}


// MARK: - Test Helpers
extension EnabledTraits {
    /// Helper method that removes a trait from the set and unwraps the returned optional.
    /// This method asserts that the trait exists in the set before removal, making tests
    /// more concise by combining removal and nil-checking in a single operation.
    package mutating func unwrapRemove(_ trait: Element) throws -> Element {
        let optionalTrait = self.remove(trait)
        let trait = try #require(optionalTrait)
        return trait
    }
}
