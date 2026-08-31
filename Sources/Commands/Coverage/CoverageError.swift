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

package enum CoverageError: Error, Equatable {
    case noTestBinariesSupplied(format: CoverageFormat)
    case llvmCovFailed(format: CoverageFormat, output: String)
}

extension CoverageError: CustomStringConvertible {
    package var description: String {
        switch self {
        case .noTestBinariesSupplied(let format):
            return "Cannot generate \(format.rawValue.uppercased()) coverage report: no test binaries were supplied."
        case .llvmCovFailed(let format, let output):
            return "Unable to generate \(format.rawValue.uppercased()) coverage report:\n\(output)"
        }
    }
}
