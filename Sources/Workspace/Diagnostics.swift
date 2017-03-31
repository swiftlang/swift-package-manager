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
import PackageGraph

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

public enum ResolverDiagnostics {

    public struct Unsatisfiable: DiagnosticData {
        public static let id = DiagnosticID(
            type: Unsatisfiable.self,
            name: "org.swift.diags.resolver.unsatisfiable",
            description: {
                $0 <<< "The dependency graph is unresolvable."
                $0 <<< .substitution({
                    let `self` = $0 as! Unsatisfiable

                    // If we don't have any additional data, return empty string.
                    if self.dependencies.isEmpty && self.pins.isEmpty {
                        return ""
                    }
                    var diag = "Found these conflicting requirements:"
                    let indent = "    "

                    if !self.dependencies.isEmpty {
                        diag += "\n\nDependencies: \n"
                        diag += self.dependencies.map({ indent + Unsatisfiable.toString($0) }).joined(separator: "\n")
                    }

                    if !self.pins.isEmpty {
                        diag += "\n\nPins: \n"
                        diag += self.pins.map({ indent + Unsatisfiable.toString($0) }).joined(separator: "\n")
                    }
                    return diag
                }, preference: .default)
            }
        )

        static func toString(_ constraint: RepositoryPackageConstraint) -> String {
            let stream = BufferedOutputByteStream()
            stream <<< constraint.identifier.url <<< " @ "

            switch constraint.requirement {
            case .versionSet(let set):
                stream <<< set.description
            case .revision(let revision):
                stream <<< revision
            case .unversioned(let constraints):
                stream <<< "unversioned ("
                stream <<< constraints.map({ $0.description }).joined(separator: ", ")
                stream <<< ")"
            }

            return stream.bytes.asString!
        }

        /// The conflicting dependencies.
        public let dependencies: [RepositoryPackageConstraint]

        /// The conflicting pins.
        public let pins: [RepositoryPackageConstraint]

        public init( dependencies: [RepositoryPackageConstraint], pins: [RepositoryPackageConstraint]) {
            self.dependencies = dependencies
            self.pins = pins
        }
    }
}
