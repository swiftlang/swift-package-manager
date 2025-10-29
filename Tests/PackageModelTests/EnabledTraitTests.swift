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
import struct PackageModel.PackageIdentity
import class PackageModel.Manifest

@Suite(

)
struct EnabledTraitTests {

    // MARK: - EnabledTrait Tests
    @Test
    func enabledTrait_checkEquality() {
        let appleTraitSetByApplePie = EnabledTrait.init(name: "Apple", setBy: .package(.init(identity: "ApplePie")))
        let appleTraitSetByAppleJuice = EnabledTrait.init(name: "Apple", setBy: .trait("AppleJuice"))
        let appleCoreTrait = EnabledTrait.init(name: "AppleCore", setBy: .default)

        #expect(appleTraitSetByApplePie == appleTraitSetByAppleJuice)
        #expect(appleCoreTrait != appleTraitSetByApplePie)
        #expect(appleCoreTrait != appleTraitSetByAppleJuice)
    }

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

    @Test
    func enabledTrait_unifyDifferentTraits() {
        let bananaTrait = EnabledTrait(name: "Banana", setBy: .package(.init(identity: "Fruit")))
        let appleTrait = EnabledTrait(name: "Apple", setBy: .package(.init(identity: "Fruit")))

        let unifiedTrait = bananaTrait.unify(appleTrait)

        #expect(unifiedTrait == nil)
        #expect(bananaTrait.setters == appleTrait.setters)
    }

    @Test
    func enabledTrait_compareToStringLiteral() {
        let appleTrait = EnabledTrait(name: "Apple", setBy: .default)

        #expect("Apple" == appleTrait) // test when EnabledTrait rhs
        #expect(appleTrait == "Apple") // test when EnabledTrait lhs
    }

    @Test
    func enabledTrait_initializedByStringLiteral() {
        let appleTraitByString: EnabledTrait = "Apple"
        let appleTraitByInit = EnabledTrait(name: "Apple", setBy: .default)

        #expect(appleTraitByString == appleTraitByInit)
    }

    @Test
    func enabledTrait_assertIdIsName() {
        let appleTrait = EnabledTrait(name: "Apple", setBy: .default)

        #expect(appleTrait.id == appleTrait.name)
    }

    @Test
    func enabledTrait_CheckIfDefault() {
        let defaultTrait: EnabledTrait = "default"

        #expect(defaultTrait.isDefault)
    }

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

    @Test
    func enabledTraits_defaultSet() {
        let defaults: EnabledTraits = .defaults

        #expect(defaults == ["default"])
        #expect(defaults == [EnabledTrait(name: "default", setBy: .default)])
    }

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

    @Test
    func enabledTraits_unionWithNewTraits() {
        let enabledTraits: EnabledTraits = ["Banana"]
        let newTraits: EnabledTraits = ["Cookie", "Pancakes", "Milkshake"]

        let unifiedSetOfTraits = enabledTraits.union(newTraits)

        #expect(unifiedSetOfTraits.count == 4)
        #expect(unifiedSetOfTraits == ["Banana", "Cookie", "Pancakes", "Milkshake"])
    }

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
    }

    // MARK: - EnabledTraitsMap Tests
}


// MARK: - Test Helpers
extension EnabledTraits {
    // Helper method to unwrap elements that are removed from the set.
    package mutating func unwrapRemove(_ trait: Element) throws -> Element {
        let optionalTrait = self.remove(trait)
        let trait = try #require(optionalTrait)
        return trait
    }
}
