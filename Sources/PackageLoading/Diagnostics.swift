/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import SPMUtility
import PackageModel

extension Diagnostic.Message {
    static func targetHasNoSources(targetPath: String, target: String) -> Diagnostic.Message {
        .warning("Source files for target \(target) should be located under \(targetPath)")
    }

    static func manifestLoading(output: String, diagnosticFile: AbsolutePath?) -> Diagnostic.Message {
        .warning(ManifestLoadingDiagnostic(output: output, diagnosticFile: diagnosticFile))
    }

    static func targetNameHasIncorrectCase(target: String) -> Diagnostic.Message {
        .warning("the target name \(target) has different case on the filesystem and the Package.swift manifest file")
    }

    static func unsupportedCTestTarget(package: String, target: String) -> Diagnostic.Message {
        .warning("ignoring target '\(target)' in package '\(package)'; C language in tests is not yet supported")
    }

    static func duplicateProduct(product: Product) -> Diagnostic.Message {
        let typeString: String
        switch product.type {
        case .library(.automatic):
            typeString = ""
        case .executable, .test,
             .library(.dynamic), .library(.static):
            typeString = " (\(product.type))"
        }

        return .warning("ignoring duplicate product '\(product.name)'\(typeString)")
    }

    static func duplicateTargetDependency(dependency: String, target: String) -> Diagnostic.Message {
        .warning("invalid duplicate target dependency declaration '\(dependency)' in target '\(target)'")
    }

    static var systemPackageDeprecation: Diagnostic.Message {
        .warning("system packages are deprecated; use system library targets instead")
    }

    static func systemPackageDeclaresTargets(targets: [String]) -> Diagnostic.Message {
        .warning("ignoring declared target(s) '\(targets.joined(separator: ", "))' in the system package")
    }

    static func systemPackageProductValidation(product: String) -> Diagnostic.Message {
        .error("system library product \(product) shouldn't have a type and contain only one target")
    }

    static func invalidExecutableProductDecl(_ product: String) -> Diagnostic.Message {
        .error("executable product '\(product)' should have exactly one executable target")
    }

    static var noLibraryTargetsForREPL: Diagnostic.Message {
        .error("unable to synthesize a REPL product as there are no library targets in the package")
    }

    static func brokenSymlink(_ path: AbsolutePath) -> Diagnostic.Message {
        .warning("ignoring broken symlink \(path)")
    }
}

public struct ManifestLoadingDiagnostic: DiagnosticData {
    public let output: String
    public let diagnosticFile: AbsolutePath?

    public var description: String { output }
}
