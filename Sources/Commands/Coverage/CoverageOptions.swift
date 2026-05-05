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

import ArgumentParser
import struct Basics.Diagnostic

package enum CoverageFormat: String, ExpressibleByArgument, CaseIterable {
    case json
    case html

    package var defaultValueDescription: String {
        switch self {
            case .json: "Produce a JSON coverage report by executing 'llvm-cov export'."
            case .html: "Produce an HTML report by executing 'llvm-cov show'."
        }
    }
}

extension CoverageFormat: Comparable {
    package static func < (lhs: CoverageFormat, rhs: CoverageFormat) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

extension CoverageFormat: Encodable {}

package enum CoveragePrintPathMode: String, ExpressibleByArgument, CaseIterable {
    case json
    case text

    package var defaultValueDescription: String {
        switch self {
            case .json: "Display the output in JSON format."
            case .text: "Display the output as plain text."
        }
    }

}


public struct CoverageOptions: ParsableArguments {
    public init() {}

    /// If the path of the exported code coverage JSON should be printed.
    @Option(
        name: [
            .customLong("show-coverage-path"),
        ],
        defaultAsFlag: CoveragePrintPathMode.text,
        help: ArgumentHelp(
            "Print the path of the exported code coverage files.",
            valueName: "mode",
        )
    )
    var _printPathMode: CoveragePrintPathMode?

    /// If the path of the exported code coverage JSON should be printed.
    @Flag(
        name: [
            .customLong("show-codecov-path"),
            .customLong("show-code-coverage-path"),
        ],
        help: ArgumentHelp(
            "Print the path of the exported code coverage files. (deprecated. use `--show-coverage-path [<mode>]` instead)",
        )
    )
    var _printPathModeDeprecated: Bool = false

    var printPathMode: CoveragePrintPathMode? {
        guard self._printPathMode != nil else {
            return self._printPathModeDeprecated ? .text : nil
        }
        return self._printPathMode
    }

    /// Whether to enable code coverage.
    @Flag(
        name: [
            .customLong("enable-coverage"),
        ],
        help: "Enable code coverage.",
    )
    var _isEnabled: Bool = false

    @Flag(
        name: [
            .customLong("code-coverage"),
        ],
        inversion: .prefixedEnableDisable,
        help: "Determines whether testing measures code coverage.. (deprecated. use '--enable-coverage' instead)",
    )
    var _isEnabledDeprecated: Bool?

    var isEnabled: Bool {
        return self._isEnabled || (self._isEnabledDeprecated ?? false)
    }


    @Option(
        name: [
            .customLong("coverage-format"),
        ],
        help: ArgumentHelp(
            "Format of the code coverage output. Can be specified multiple times.",
            valueName: "format",
        )
    )
    var formats: [CoverageFormat] = [.json]

    /// Coverage arguments with optional format specification.
    @Option(
        name: [
            .customLong("Xcov", withSingleDash: true),
        ],
        parsing: .unconditionalSingleValue,
        help: ArgumentHelp(
            [
                "Pass flag, with optional format specification, through to the underlying coverage report",
                "tool. Syntax: '[<coverage-format>=]<value>'. Can be specified multiple times.",
            ].joined(separator: " "),
        )
    )
    var _xcovArguments: [XcovArgument] = []

    package var xcovArguments: XcovArgumentCollection {
        return XcovArgumentCollection(_xcovArguments)
    }
}

extension Basics.Diagnostic {
    package static var deprecatedShowCodeCoveragePath: Self {
        .warning(
            "The '--show-code-coverage-path' and '--show-codecov-path' options are deprecated.  Use '--show-coverage-path' instead."
        )
    }

    package static var deprecatedEnableDisableCoverage: Self {
        .warning(
            "The '--enable-code-coverage' and '--disable-code-coverage' options have been deprecated.  Use '--enable-coverage' instead."
        )

    }
}
