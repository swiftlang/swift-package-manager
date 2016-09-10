/*
This source file is part of the Swift.org open source project

Copyright 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class KeyedPairTests: XCTestCase {
    func testBasics() {
        class Airport {
            // The name of the airport.
            let name: String
            // The destination airports for outgoing flights.
            var destinations: [Airport] = []

            init(name: String) {
                self.name = name
            }
        }

        func whereCanIGo(from airport: Airport) -> [Airport] {
            let closure = transitiveClosure([KeyedPair(airport, key: airport.name)]) {
                return $0.item.destinations.map{ KeyedPair($0, key: $0.name) }
            }
            return closure.map{ $0.item }
        }

        let sf = Airport(name: "San Francisco")
        let beijing = Airport(name: "北京市")
        let newDelhi = Airport(name: "नई दिल्ली")
        let moscow = Airport(name: "Москва")
        sf.destinations = [newDelhi]
        newDelhi.destinations = [beijing, moscow]

        XCTAssertEqual(whereCanIGo(from: sf).map{ $0.name }.sorted(), ["Москва", "नई दिल्ली", "北京市"])
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
