/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import Utility

import PackageLoading

public struct ManifestParseDiagnostic: DiagnosticData {
    public static let id = DiagnosticID(
        type: ManifestParseDiagnostic.self,
        name: "org.swift.diags.manifest-parse",
        description: {
            $0 <<< { "manifest parse error(s):\n" + $0.errors.joined(separator: "\n") }
        }
    )

    public let errors: [String]
    public init(_ errors: [String]) {
        self.errors = errors
    }
}

extension ManifestParseError: DiagnosticDataConvertible {
    public var diagnosticData: DiagnosticData {
        switch self {
        case .emptyManifestFile:
            return ManifestParseDiagnostic(["manifest file is empty"])
        case .invalidEncoding:
            return ManifestParseDiagnostic(["manifest has invalid encoding"])
        case .invalidManifestFormat(let error):
            return ManifestParseDiagnostic([error])
        case .runtimeManifestErrors(let errors):
            return ManifestParseDiagnostic(errors)
        }
    }
}
