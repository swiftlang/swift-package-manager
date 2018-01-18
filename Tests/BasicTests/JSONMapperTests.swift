/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Basic

fileprivate struct Bar: JSONMappable, JSONSerializable, Equatable {
    let str: String
    let bool: Bool

    init(json: JSON) throws {
        self.str = try json.get("str")
        self.bool = try json.get("bool")
    }

    func toJSON() -> JSON {
        return .dictionary([
            "str": .string(str),
            "bool": .bool(bool),
        ])
    }

    init(str: String, bool: Bool) {
        self.str = str
        self.bool = bool
    }

    public static func ==(lhs: Bar, rhs: Bar) -> Bool {
        return lhs.str == rhs.str && lhs.bool == rhs.bool
    }
}

fileprivate struct Foo: JSONMappable, JSONSerializable {
    let str: String
    let int: Int
    let optStr: String?
    let bar: Bar
    let barOp: Bar?
    let barArray: [Bar]
    let dict: [String: Double]

    init(json: JSON) throws {
        self.str = try json.get("str")
        self.int = try json.get("int")
        self.optStr = json.get("optStr")
        self.bar = try json.get("bar")
        self.barOp = json.get("barOp")
        self.barArray = try json.get("barArray")
        self.dict = try json.get("dict")
    }

    func toJSON() -> JSON {
        return .dictionary([
            "str": .string(str),
            "int": .int(int),
            "optStr": optStr.flatMap(JSON.string) ?? .null,
            "bar": bar.toJSON(),
            "barOp": barOp.flatMap{$0.toJSON()} ?? .null,
            "barArray": .array(barArray.map{$0.toJSON()}),
            "dict": .dictionary(Dictionary(items: dict.map{($0.0, .double($0.1))})),
        ])
    }

    init(str: String, int: Int, optStr: String?, bar: Bar, barArray: [Bar], dict: [String: Double]) {
        self.str = str
        self.int = int
        self.optStr = optStr
        self.bar = bar
        self.barOp = nil
        self.barArray = barArray
        self.dict = dict
    }
}

class JSONMapperTests: XCTestCase {

    func testBasics() throws {
        let bar = Bar(str: "bar", bool: false)
        let bar1 = Bar(str: "bar1", bool: true)
        let dict = ["a": 1.0, "b": 2.923]
        let foo = Foo(
            str: "foo", int: 1, optStr: "k", bar: bar, barArray: [bar, bar1], dict: dict)
        let foo1 = try Foo(json: foo.toJSON())
        XCTAssertEqual(foo.str, foo1.str)
        XCTAssertEqual(foo.int, foo1.int)
        XCTAssertEqual(foo.optStr, foo1.optStr)
        XCTAssertEqual(foo.bar, bar)
        XCTAssertNil(foo.barOp)
        XCTAssertEqual(foo.barArray, [bar, bar1])
        XCTAssertEqual(foo.dict, dict)
    }

    func testErrors() throws {
        let foo = JSON.dictionary(["foo": JSON.string("Hello")])
        do {
            let string: String = try foo.get("bar")
            XCTFail("unexpected string: \(string)")
        } catch JSON.MapError.missingKey(let key) {
            XCTAssertEqual(key, "bar")
        }

        do {
            let int: Int = try foo.get("foo")
            XCTFail("unexpected int: \(int)")
        } catch JSON.MapError.custom(let key, let msg) {
            XCTAssertNil(key)
            XCTAssertEqual(msg, "expected int, got \"Hello\"")
        }

        do {
            let bool: Bool = try foo.get("foo")
            XCTFail("unexpected bool: \(bool)")
        } catch JSON.MapError.custom(let key, let msg) {
            XCTAssertNil(key)
            XCTAssertEqual(msg, "expected bool, got \"Hello\"")
        }

        do {
            let foo = JSON.string("Hello")
            let string: String = try foo.get("bar")
            XCTFail("unexpected string: \(string)")
        } catch JSON.MapError.typeMismatch(let key, let expected, let json) {
            XCTAssertEqual(key, "bar")
            XCTAssert(expected == Dictionary<String, JSON>.self)
            XCTAssertEqual(json, .string("Hello"))
        }

        do {
            let string: [String] = try foo.get("foo")
            XCTFail("unexpected string: \(string)")
        } catch JSON.MapError.typeMismatch(let key, let expected, let json) {
            XCTAssertEqual(key, "foo")
            XCTAssert(expected == Array<JSON>.self)
            XCTAssertEqual(json, .string("Hello"))
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testErrors", testErrors),
    ]
}
