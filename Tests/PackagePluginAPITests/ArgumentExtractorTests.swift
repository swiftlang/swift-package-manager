//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackagePlugin
import XCTest

class ArgumentExtractorAPITests: XCTestCase {

    func testBasics() throws {
        var extractor = ArgumentExtractor(["--verbose", "--target", "Target1", "Positional1", "--flag", "--verbose", "--target", "Target2", "Positional2"])
        XCTAssertEqual(extractor.extractOption(named: "target"), ["Target1", "Target2"])
        XCTAssertEqual(extractor.extractFlag(named: "flag"), 1)
        XCTAssertEqual(extractor.extractFlag(named: "verbose"), 2)
        XCTAssertEqual(extractor.extractFlag(named: "nothing"), 0)
        XCTAssertEqual(extractor.unextractedOptionsOrFlags, [])
        XCTAssertEqual(extractor.remainingArguments, ["Positional1", "Positional2"])
    }

    func testExtractOption() throws {
        var extractor = ArgumentExtractor(["--output", "Dir1", "--target=Target1", "Positional1", "--flag", "--target", "Target2", "Positional2", "--output=Dir2"])
        XCTAssertEqual(extractor.extractOption(named: "target"), ["Target1", "Target2"])
        XCTAssertEqual(extractor.extractOption(named: "output"), ["Dir1", "Dir2"])
        XCTAssertEqual(extractor.extractFlag(named: "flag"), 1)
        XCTAssertEqual(extractor.unextractedOptionsOrFlags, [])
        XCTAssertEqual(extractor.remainingArguments, ["Positional1", "Positional2"])
    }

    func testDashDashTerminal() throws {
        var extractor = ArgumentExtractor(["--verbose", "--", "--target", "Target1", "Positional", "--verbose"])
        XCTAssertEqual(extractor.extractOption(named: "target"), [])
        XCTAssertEqual(extractor.extractFlag(named: "verbose"), 1)
        XCTAssertEqual(extractor.unextractedOptionsOrFlags, [])
        XCTAssertEqual(extractor.remainingArguments, ["--target", "Target1", "Positional", "--verbose"])
    }

    func testEdgeCases() throws {
        var extractor1 = ArgumentExtractor([])
        XCTAssertEqual(extractor1.extractOption(named: "target"), [])
        XCTAssertEqual(extractor1.extractFlag(named: "verbose"), 0)
        XCTAssertEqual(extractor1.unextractedOptionsOrFlags, [])
        XCTAssertEqual(extractor1.remainingArguments, [])

        var extractor2 = ArgumentExtractor(["--"])
        XCTAssertEqual(extractor2.extractOption(named: "target"), [])
        XCTAssertEqual(extractor2.extractFlag(named: "verbose"), 0)
        XCTAssertEqual(extractor2.unextractedOptionsOrFlags, [])
        XCTAssertEqual(extractor2.remainingArguments, [])
    }
}
