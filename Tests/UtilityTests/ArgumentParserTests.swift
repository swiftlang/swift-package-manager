/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Utility

enum SampleEnum: String {
    case Foo
    case Bar
}

extension SampleEnum: ArgumentKind {
    public init(parser: ArgumentParserProtocol) throws {
        let arg = try parser.next()
        guard let obj = SampleEnum(arg: arg) else {
            throw ArgumentParserError.unknown(option: arg)
        }
        self = obj
    }

    init?(arg: String) {
        self.init(rawValue: arg)
    }
}

class ArgumentParserTests: XCTestCase {

    func testBasics() throws {
        let parser = ArgumentParser()

        let package = parser.add(positional: "package", kind: String.self, usage: "The name of the package")
        let revision = parser.add(option: "--revision", kind: String.self, usage: "The revision")
        let branch = parser.add(option: "--branch", shortName:"-b", kind: String.self, usage: "The branch to checkout")
        let xld = parser.add(option: "-Xld", kind: Array<String>.self, usage: "The xld arguments")
        let verbosity = parser.add(option: "--verbose", kind: Int.self, usage: "The verbosity level")
        let noFly = parser.add(option: "--no-fly", kind: Bool.self, usage: "If should fly")
        let sampleEnum = parser.add(positional: "enum", kind: SampleEnum.self)

        let args = try parser.parse(["Foo", "-b", "bugfix", "--verbose", "2", "-Xld", "foo", "-Xld", "bar",  "--no-fly", "Bar"])

        XCTAssertEqual(args.get(package), "Foo")
        XCTAssert(args.get(revision) == nil)
        XCTAssertEqual(args.get(branch), "bugfix")
        XCTAssertEqual(args.get(xld) ?? [], ["foo", "bar"])
        XCTAssertEqual(args.get(verbosity), 2)
        XCTAssertEqual(args.get(noFly), true)
        XCTAssertEqual(args.get(sampleEnum), .Bar)
        XCTAssert(parser.usageText().contains("package          The name of the package"))
    }

    func testErrors() throws {
        let parser = ArgumentParser()
        _ = parser.add(positional: "package", kind: String.self, usage: "The name of the package")
        _ = parser.add(option: "--verbosity", kind: Int.self, usage: "The revision")

        do {
            _ = try parser.parse()
            XCTFail("unexpected success")
        } catch ArgumentParserError.expectedArguments(let args) {
            XCTAssertEqual(args, ["package"])
        }

        do {
            _ = try parser.parse(["foo", "bar"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.unexpectedArgument(let arg) {
            XCTAssertEqual(arg, "bar")
        }

        do {
            _ = try parser.parse(["foo", "--bar"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.unknown(let option) {
            XCTAssertEqual(option, "--bar")
        }

        do {
            _ = try parser.parse(["foo", "--verbosity"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.expectedValue(let option) {
            XCTAssertEqual(option, "--verbosity")
        }

        do {
            _ = try parser.parse(["foo", "--verbosity", "yes"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.typeMismatch(let error) {
            XCTAssertEqual(error, "yes is not convertible to Int")
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testErrors", testErrors),
    ]
}
