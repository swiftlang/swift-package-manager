//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing

import enum Commands.CoverageError
import enum Commands.CoverageFormat
import _InternalTestSupport

@Suite(
    .tags(
        .TestSize.small,
        .Feature.CodeCoverage,
    ),
)
struct CoverageErrorTests {

    @Test(arguments: CoverageFormat.allCases)
    func noTestBinariesSuppliedDescription(format: CoverageFormat) {
        let error = CoverageError.noTestBinariesSupplied(format: format)
        let expected = "Cannot generate \(format.rawValue.uppercased()) coverage report: no test binaries were supplied."
        #expect(String(describing: error) == expected)
    }

    @Test(arguments: CoverageFormat.allCases)
    func llvmCovFailedDescription(format: CoverageFormat) {
        let output = "some tool output"
        let error = CoverageError.llvmCovFailed(format: format, output: output)
        let expected = "Unable to generate \(format.rawValue.uppercased()) coverage report:\nsome tool output"
        #expect(String(describing: error) == expected)
    }

    @Test
    func noTestBinariesSuppliedIsEquatable() {
        #expect(
            CoverageError.noTestBinariesSupplied(format: .html)
                == CoverageError.noTestBinariesSupplied(format: .html),
        )
        #expect(
            CoverageError.noTestBinariesSupplied(format: .html)
                != CoverageError.noTestBinariesSupplied(format: .json),
        )
    }

    @Test
    func llvmCovFailedIsEquatable() {
        #expect(
            CoverageError.llvmCovFailed(format: .html, output: "x")
                == CoverageError.llvmCovFailed(format: .html, output: "x"),
        )
        #expect(
            CoverageError.llvmCovFailed(format: .html, output: "x")
                != CoverageError.llvmCovFailed(format: .html, output: "y"),
        )
        #expect(
            CoverageError.llvmCovFailed(format: .html, output: "x")
                != CoverageError.llvmCovFailed(format: .json, output: "x"),
        )
    }
}
