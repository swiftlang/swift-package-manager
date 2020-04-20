/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import XCTest

import TSCBasic
import TSCUtility

class Animal: PolymorphicCodableProtocol {
    static var implementations: [PolymorphicCodableProtocol.Type] = [
        Dog.self,
        Cat.self,
    ]

    let age: Int

    init(age: Int) {
        self.age = age
    }
}

struct Animals: Codable {
    @PolymorphicCodable
    var animal1: Animal

    @PolymorphicCodable
    var animal2: Animal

    @PolymorphicCodableArray
    var animals: [Animal]
}

final class PolymorphicCodableTests: XCTestCase {

    func testBasic() throws {
        let dog = Dog(age: 5, dogCandy: "bone")
        let cat = Cat(age: 3, catToy: "wool")

        let animals = Animals(animal1: dog, animal2: cat, animals: [dog, cat])
        let encoded = try JSONEncoder().encode(animals)
        let decoded = try JSONDecoder().decode(Animals.self, from: encoded)

        let animal1 = try XCTUnwrap(decoded.animal1 as? Dog)
        XCTAssertEqual(animal1.age, 5)
        XCTAssertEqual(animal1.dogCandy, "bone")

        let animal2 = try XCTUnwrap(decoded.animal2 as? Cat)
        XCTAssertEqual(animal2.age, 3)
        XCTAssertEqual(animal2.catToy, "wool")

        XCTAssertEqual(decoded.animals.count, 2)
        XCTAssertEqual(decoded.animals.map{ $0.age }, [5, 3])
        XCTAssertEqual(decoded.animals.map{ String(reflecting: $0) }, ["TSCUtilityTests.Dog", "TSCUtilityTests.Cat"])
    }
}

// MARK:- Subclasses

class Dog: Animal {
    let dogCandy: String

    init(age: Int, dogCandy: String) {
        self.dogCandy = dogCandy
        super.init(age: age)
    }

    enum CodingKeys: CodingKey {
        case dogCandy
    }

    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dogCandy, forKey: .dogCandy)
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dogCandy = try container.decode(String.self, forKey: .dogCandy)
        try super.init(from: decoder)
    }
}

class Cat: Animal {
    let catToy: String

    init(age: Int, catToy: String) {
        self.catToy = catToy
        super.init(age: age)
    }

    enum CodingKeys: CodingKey {
        case catToy
    }

    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(catToy, forKey: .catToy)
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.catToy = try container.decode(String.self, forKey: .catToy)
        try super.init(from: decoder)
    }
}
