//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import Foundation
import PackageModel
import SourceControl

public import SwiftDiagnostics
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

import struct TSCBasic.ByteString

import struct TSCUtility.Version

public typealias SyntaxDiagnostic = SwiftDiagnostics.Diagnostic

/// Manifest loader that operates by using SwiftSyntax to parse the manifest
/// file directly rather than executing it.
///
/// This manifest loader takes a conservative approach of rejecting anything
/// in the manifest file that it doesn't understand, recording a set of
/// "limitations" along the way. The presence of limitations after parsing
/// means that SwiftPM will have to execute the manifest, but is not
/// necessarily an error.
///
/// This manifest loader can also produce errors that would prevent
/// manifest execution from succeeding, for example syntax errors in the
/// manifest. The client can choose to report these errors directly rather
/// than continue to manifest parsing.
public final class ParsingManifestLoader: ManifestLoaderProtocol {
    let pruneDependencies: Bool

    public init(pruneDependencies: Bool = false) {
        self.pruneDependencies = pruneDependencies
    }

    public func resetCache(observabilityScope: Basics.ObservabilityScope) async {
        // No caching, so there is nothing to do.
    }
    
    public func purgeCache(observabilityScope: Basics.ObservabilityScope) async {
        // No caching, so there is nothing to do.
    }
    
    /// Load the manifest for the package at `path`.
    ///
    /// - Parameters:
    ///   - manifestPath: The root path of the package.
    ///   - manifestToolsVersion: The version of the tools the manifest supports.
    ///   - packageIdentity: the identity of the package
    ///   - packageKind: The kind of package the manifest is from.
    ///   - packageLocation: The location the package the manifest was loaded from.
    ///   - packageVersion: Optional. The version and revision of the package.
    ///   - identityResolver: A helper to resolve identities based on configuration
    ///   - dependencyMapper: A helper to map dependencies.
    ///   - fileSystem: File system to load from.
    ///   - observabilityScope: Observability scope to emit diagnostics.
    ///   - callbackQueue: The dispatch queue to perform completion handler on.
    ///   - completion: The completion handler .
    public func load(
        manifestPath: AbsolutePath,
        manifestToolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        packageVersion: (version: Version?, revision: String?)?,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue
    ) async throws -> Manifest {
        let manifestContents: ByteString
        do {
            manifestContents = try fileSystem.readFileContents(manifestPath)
        } catch {
            throw ManifestParserError.inaccessibleManifest(path: manifestPath, reason: String(describing: error))
        }

        return try parse(
            manifestPath: manifestPath,
            manifestContents: manifestContents,
            manifestToolsVersion: manifestToolsVersion,
            packageIdentity: packageIdentity,
            packageKind: packageKind,
            packageLocation: packageLocation,
            packageVersion: packageVersion,
            identityResolver: identityResolver,
            dependencyMapper: dependencyMapper,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
            delegateQueue: delegateQueue
        )
    }

    /// Parse a package manifest, without compiling and executing it.
    public func parse(
        manifestPath: AbsolutePath,
        manifestContents: ByteString,
        manifestToolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        packageVersion: (version: Version?, revision: String?)?,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue
    ) throws(ManifestParserError) -> Manifest {
        try manifestContents.contents.withUnsafeBufferPointer { manifestBytes throws(ManifestParserError) in
            try parse(
                manifestPath: manifestPath,
                manifestContents: manifestBytes,
                manifestToolsVersion: manifestToolsVersion,
                packageIdentity: packageIdentity,
                packageKind: packageKind,
                packageLocation: packageLocation,
                packageVersion: packageVersion,
                identityResolver: identityResolver,
                dependencyMapper: dependencyMapper,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope,
                delegateQueue: delegateQueue
            )
        }
    }

    private func parse(
        manifestPath: AbsolutePath,
        manifestContents: UnsafeBufferPointer<UInt8>,
        manifestToolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        packageVersion: (version: Version?, revision: String?)?,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue
    ) throws(ManifestParserError) -> Manifest {
        // Parse the source file.
        let sourceFile: SourceFileSyntax = Parser.parse(source: manifestContents)

        // Check for syntax errors that would prevent us from going further.
        // FIXME: Figure out how we want to handle #ifs here. We could filter
        // out untaken #if branches like the compiler does.
        let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: sourceFile)
        if !diagnostics.isEmpty {
            throw .syntaxErrors(diagnostics)
        }

        // Walk the source file to parse
        let visitor = ManifestParseVisitor(viewMode: .fixedUp)
        visitor.walk(sourceFile)

        // If we hit any of the limitations of the manifest parser, bail out
        // now.
        if !visitor.limitations.isEmpty {
            throw .limitations(visitor.limitations)
        }

        /// We need to found a package name to continue.
        guard let packageName = visitor.packageName else {
            throw .missingPackageName
        }

        return Manifest(
            displayName: packageName,
            packageIdentity: packageIdentity,
            path: manifestPath,
            packageKind: packageKind,
            packageLocation: packageLocation,
            defaultLocalization: visitor.defaultLocalization,
            platforms: visitor.platforms,
            version: packageVersion?.version,
            revision: packageVersion?.revision,
            toolsVersion: manifestToolsVersion,
            pkgConfig: visitor.pkgConfig,
            providers: visitor.providers,
            cLanguageStandard: visitor.cLanguageStandard,
            cxxLanguageStandard: visitor.cxxLanguageStandard,
            swiftLanguageVersions: visitor.swiftLanguageVersions,
            dependencies: visitor.dependencies,
            products: visitor.products,
            targets: visitor.targets,
            traits: visitor.traits,
            pruneDependencies: self.pruneDependencies
        )
    }
}

class ManifestParseVisitor: SyntaxAnyVisitor {
    /// Limitations encountered while processing the manifest.
    var limitations: [ManifestParseLimitation] = []

    /// Package name
    var packageName: String?

    /// The default localization for resources.
    var defaultLocalization: String?

    /// Platforms.
    var platforms: [PlatformDescription] = []

    /// Targets
    var targets: [TargetDescription] = []

    var pkgConfig: String?

    /// Swift language versions.
    var swiftLanguageVersions: [SwiftLanguageVersion]?

    /// Package dependencies.
    ///
    var dependencies: [PackageDependency] = []

    /// System package providers.
    var providers: [SystemPackageProviderDescription]?

    /// Products.
    var products: [ProductDescription] = []

    /// Traits.
    var traits: Set<TraitDescription> = []

    /// C++ language standard.
    var cxxLanguageStandard: String?

    /// C language standard.
    var cLanguageStandard: String?

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        // Any node not specifically handled is considered a limitation.
        limitations.append(.unexpectedSyntax(node))

        return .skipChildren
    }

    override func visit(_ node: TokenSyntax) -> SyntaxVisitorContinueKind {
        if node.tokenKind == .endOfFile {
            return .skipChildren
        }

        return visitAny(Syntax(node))
    }
    /// Process global variable declarations to find the "package" declaration.
    override func visit(_ varNode: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Dig out the name and initializer.
        guard let (_, initializer) = varNode.asSingleInitializedVariable() else {
            limitations.append(.unsupportedVariableForm(varNode))
            return .skipChildren
        }

        // Check whether we know this call or not.
        guard let (knownCall, arguments) = initializer.asKnownCall() else {
            limitations.append(
                .unsupportedExpression(
                    initializer,
                    expected: "top-level variable initializer"
                )
            )
            return .skipChildren
        }

        // Handle any top-level known calls here.
        switch knownCall {
        case .package:
            handlePackageDeclaration(initializer: initializer, arguments: arguments)
        }

        return .skipChildren
    }


    /// Check whether import declarations match known modules. Otherwise, we
    /// can't reason about what the manifest is doing.
    override func visit(_ importNode: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        // Match import declaration with a single path component.
        guard importNode.attributes.isEmpty, importNode.modifiers.isEmpty,
              let pathComponent = importNode.path.first,
              importNode.path.count == 1,
              let moduleName = pathComponent.name.identifier
        else {
            limitations.append(.unsupportedImportForm(importNode))
            return .skipChildren
        }

        // Check for module names we understand.
        switch moduleName.name {
        case "PackageDescription", "Foundation", "CompilerPluginSupport":
            // Okay
            break

        default:
            // Module name we don't know anything about.
            limitations.append(
                .unknownImportModule(importNode, moduleName: moduleName.name)
            )
        }

        return .skipChildren
    }

    // Nodes we trivially step into.
    override func visit(_: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        .visitChildren
    }

    override func visit(_: CodeBlockItemListSyntax) -> SyntaxVisitorContinueKind {
        .visitChildren
    }

    override func visit(_: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
        .visitChildren
    }
}

/// MARK: Declaration handling
extension ManifestParseVisitor {
    func handlePackageDeclaration(
        initializer: ExprSyntax,
        arguments: LabeledExprListSyntax
    ) {
        for argument in arguments {
            if argument.label?.text == "name" {
                guard let name = argument.expression.asStringLiteralValue() else {
                    limitations.append(
                        .unsupportedExpression(
                            argument.expression,
                            expected: "string literal"
                        )
                    )

                    continue
                }

                // Record the package name.
                self.packageName = name
                continue
            }

            // Unhandled argument.
            limitations.append(.unsupportedArgument(argument, callee: "Package"))
        }
    }
}

/// MARK: Parsing helpers
extension VariableDeclSyntax {
    /// Match the form 'let x = y', and return the identifier for 'x' and the
    /// expression for 'y'.
    func asSingleInitializedVariable() -> (Identifier, ExprSyntax)? {
        // No attributes, no modifiers, and a single "let" binding with an
        // identifier and an initializer.
        guard attributes.isEmpty, modifiers.isEmpty,
              bindingSpecifier.tokenKind == .keyword(.let),
              let binding = bindings.first, bindings.count == 1,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?
                .identifier.identifier,
              let initializer = binding.initializer else {
            return nil
        }

        return (identifier, initializer.value)
    }
}

/// Describes the kinds of calls that we recognize.
fileprivate enum KnownCallType {
    /// Package(...) initializer
    case package

    /// Match the name in a direct call such as "Package(...)".
    init?(directCallTo name: String) {
        switch name {
        case "Package": self = .package
        default: return nil
        }
    }
}

extension ExprSyntax {
    /// Try to treat the given expression as a known call, extracting out the
    /// arguments to the call.
    fileprivate func asKnownCall() -> (KnownCallType, LabeledExprListSyntax)? {
        guard let functionCall = self.as(FunctionCallExprSyntax.self) else {
            return nil
        }

        // Look for known calls.
        let knownCallType: KnownCallType
        let callee = functionCall.calledExpression
        if let calleeRef = callee.as(DeclReferenceExprSyntax.self),
           let identifier = calleeRef.baseName.identifier,
           calleeRef.argumentNames == nil,
           let knownCall = KnownCallType(directCallTo: identifier.name)
        {
            knownCallType = knownCall
        } else {
            return nil
        }

        return (knownCallType, functionCall.arguments)
    }

    /// Extract the string literal value from the expression, if it is one.
    fileprivate func asStringLiteralValue() -> String? {
        guard let stringLiteral = self.as(StringLiteralExprSyntax.self),
              stringLiteral.segments.count == 1,
              let segment = stringLiteral.segments.first,
              case .stringSegment(let segmentContents) = segment else {
            return nil
        }

        return segmentContents.content.text
    }
}
