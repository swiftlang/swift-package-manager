/*
This source file is part of the Swift.org open source project

Copyright 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class OptionParserTests: XCTestCase {
    func testNoArguments() throws {
        let (mode, flags): (Mode?, [Flag]) = try parseOptions(arguments: [])

        XCTAssertNil(mode)
        XCTAssertEqual(flags.count, 0)
    }

    func testModeA() throws {
        let (mode, flags): (Mode?, [Flag]) = try parseOptions(arguments: ["--A"])

        XCTAssertEqual(mode, .A)
        XCTAssertEqual(flags.count, 0)
    }

    func testModeB() throws {
        let (mode, flags): (Mode?, [Flag]) = try parseOptions(arguments: ["--B"])

        XCTAssertEqual(mode, .B)
        XCTAssertEqual(flags.count, 0)
    }

    func testModeAFlagD() throws {
        let (mode, flags): (Mode?, [Flag]) = try parseOptions(arguments: ["--A", "--D"])

        XCTAssertEqual(mode, .A)
        XCTAssertEqual(flags, [Flag.D])
    }

    func testModeAFlagDE() throws {
        let (mode, flags): (Mode?, [Flag]) = try parseOptions(arguments: ["--A", "--D", "--E"])

        XCTAssertEqual(mode, .A)
        XCTAssertEqual(flags, [Flag.D, Flag.E])
    }

    func testMultiModes() {
        do {
            let _: (Mode?, [Flag]) = try parseOptions(arguments: ["--A", "--B"])
            XCTFail()
        } catch OptionParserError.MultipleModesSpecified(let args) {
            XCTAssertEqual(args, ["A", "B"])
        } catch {
            XCTFail()
        }
    }

    func testAssociatedValue() throws {
        let (_, flags): (Mode?, [Flag]) = try parseOptions(arguments: ["--F", "foo", "--G", "123"])

        XCTAssertEqual(flags, [.F("foo"), .G(123)])
    }

    func testThrowsIfNoAssociatedValue() {
        do {
            let _: (Mode?, [Flag]) = try parseOptions(arguments: ["--F"])
            XCTFail()
        } catch OptionParserError.ExpectedAssociatedValue {
            // güd
        } catch {
            XCTFail("\(error)")
        }
    }

    func testThrowsIfAssociatedValueWithWrongFlag() {
        do {
            let _: (Mode?, [Flag]) = try parseOptions(arguments: ["--E=foo", "--G=123"])
            XCTFail()
        } catch OptionParserError.UnexpectedAssociatedValue {
            // güd
        } catch {
            XCTFail("\(error)")
        }
    }

    func testThrowsIfAssociatedValueWithWrongMode() {
        do {
            let _: (Mode?, [Flag]) = try parseOptions(arguments: ["--A=foo", "--G=123"])
            XCTFail()
        } catch OptionParserError.UnexpectedAssociatedValue {
            // güd
        } catch {
            XCTFail("\(error)")
        }
    }

    func testAssignedAssociatedValue() throws {
        let (mode, flags): (Mode?, [Flag]) = try parseOptions(arguments: ["--F=foo", "--G=123"])

        XCTAssertNil(mode)
        XCTAssertEqual(flags, [.F("foo"), .G(123)])
    }

    func testCanUnderstandMultipleShortFlags() throws {
        let (mode, flags): (Mode?, [Flag]) = try parseOptions(arguments: ["-HJI"])

        XCTAssertNil(mode)
        XCTAssertEqual(flags, [.H, .J, .I])
    }

    func testCanUnderstandMultipleShortFlagsWithAFinalAssociatedValue() throws {
        let (mode, flags): (Mode?, [Flag]) = try parseOptions(arguments: ["-HJIKHJI"])

        XCTAssertNil(mode)
        XCTAssertEqual(flags, [.H, .J, .I, .K("HJI")])
    }
}

extension OptionParserTests {
    static var allTests : [(String, (OptionParserTests) -> () throws -> Void)] {
        return [
            ("testNoArguments", testNoArguments),
            ("testModeA", testModeA),
            ("testModeB", testModeB),
            ("testModeAFlagD", testModeAFlagD),
            ("testModeAFlagDE", testModeAFlagDE),
            ("testMultiModes", testMultiModes),
            ("testAssociatedValue", testAssociatedValue),
            ("testThrowsIfNoAssociatedValue", testThrowsIfNoAssociatedValue),
            ("testThrowsIfAssociatedValueWithWrongFlag", testThrowsIfAssociatedValueWithWrongFlag),
            ("testThrowsIfAssociatedValueWithWrongMode", testThrowsIfAssociatedValueWithWrongMode),
            ("testAssignedAssociatedValue", testAssignedAssociatedValue),
            ("testCanUnderstandMultipleShortFlags", testCanUnderstandMultipleShortFlags),
            ("testCanUnderstandMultipleShortFlagsWithAFinalAssociatedValue", testCanUnderstandMultipleShortFlagsWithAFinalAssociatedValue),
        ]
    }
}

//MARK: Mode/Flag

enum Mode: String, Argument {
    case A, B, C

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "--A":
            self = .A
        case "--B":
            self = .B
        case "--C":
            self = .C
        default:
            return nil
        }
    }
}

enum Flag: Argument, Equatable {
    case D, E, F(String), G(Int), H, I, J, K(String)

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "--D":
            self = .D
        case "--E":
            self = .E
        case "--F":
            guard let str = pop() else { throw OptionParserError.ExpectedAssociatedValue("") }
            self = .F(str)
        case "--G":
            guard let str = pop(), int = Int(str) else { throw OptionParserError.ExpectedAssociatedValue("") }
            self = .G(int)
        case "-H":
            self = .H
        case "-I":
            self = .I
        case "-J":
            self = .J
        case "-K":
            guard let str = pop() else { throw OptionParserError.ExpectedAssociatedValue("") }
            self = .K(str)
        default:
            return nil
        }
    }
}

func ==(lhs: Flag, rhs: Flag) -> Bool {
    switch (lhs, rhs) {
    case (.D, .D), (.E, .E):
        return true
    case (.F(let a), .F(let b)) where a == b:
        return true
    case (.G(let a), .G(let b)) where a == b:
        return true
    case (.H, .H), (.I, .I), (.J, .J):
        return true
    case (.K(let a), .K(let b)) where a == b:
        return true
    default:
        return false
    }
}
