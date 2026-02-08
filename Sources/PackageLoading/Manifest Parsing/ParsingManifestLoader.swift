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

            if argument.label?.text == "swiftLanguageVersions" {
                // Try new-style syntax first (e.g., [.v3, .v4, .version("5")])
                if let versions = argument.expression.asSwiftLanguageVersionArray() {
                    self.swiftLanguageVersions = versions
                    continue
                }

                // Fall back to old-style integer array syntax (e.g., [3, 4])
                guard let intVersions = argument.expression.asIntegerArray() else {
                    limitations.append(
                        .unsupportedExpression(
                            argument.expression,
                            expected: "array of Swift language versions"
                        )
                    )
                    continue
                }

                // Convert integers to SwiftLanguageVersion with validation
                // Note: Even if the array is empty, we set it to an empty array (not nil)
                // to distinguish from the case where swiftLanguageVersions wasn't specified
                var validatedVersions: [SwiftLanguageVersion] = []
                var hasValidationError = false
                for (index, version) in intVersions.enumerated() {
                    let versionString = "\(version)"
                    guard let swiftVersion = SwiftLanguageVersion(string: versionString) else {
                        hasValidationError = true
                        // Get the actual syntax element for better error reporting
                        if let arrayExpr = argument.expression.as(ArrayExprSyntax.self),
                           index < arrayExpr.elements.count {
                            let element = arrayExpr.elements[arrayExpr.elements.index(arrayExpr.elements.startIndex, offsetBy: index)]
                            limitations.append(.invalidSwiftLanguageVersion(element.expression, value: versionString))
                        } else {
                            limitations.append(.invalidSwiftLanguageVersion(argument.expression, value: versionString))
                        }
                        continue
                    }
                    validatedVersions.append(swiftVersion)
                }

                // Only set if we successfully validated all versions
                if !hasValidationError {
                    self.swiftLanguageVersions = validatedVersions
                }
                continue
            }
            
            if argument.label?.text == "pkgConfig" {
                self.pkgConfig = argument.expression.asStringLiteralValue()
                continue
            }
            
            if argument.label?.text == "providers" {
                guard let providersArray = argument.expression.as(ArrayExprSyntax.self) else {
                    limitations.append(
                        .unsupportedExpression(
                            argument.expression,
                            expected: "array of providers"
                        )
                    )
                    continue
                }
                
                var parsedProviders: [SystemPackageProviderDescription] = []
                for providerElement in providersArray.elements {
                    if let provider = parseSystemPackageProvider(providerElement.expression) {
                        parsedProviders.append(provider)
                    }
                }
                self.providers = parsedProviders.isEmpty ? nil : parsedProviders
                continue
            }
            
            if argument.label?.text == "products" {
                guard let productsArray = argument.expression.as(ArrayExprSyntax.self) else {
                    limitations.append(
                        .unsupportedExpression(
                            argument.expression,
                            expected: "array of products"
                        )
                    )
                    continue
                }
                
                for productElement in productsArray.elements {
                    if let product = parseProduct(productElement.expression) {
                        self.products.append(product)
                    }
                }
                continue
            }
            
            if argument.label?.text == "cLanguageStandard" {
                if let standard = parseCLanguageStandard(argument.expression) {
                    self.cLanguageStandard = standard
                }
                continue
            }
            
            if argument.label?.text == "cxxLanguageStandard" {
                if let standard = parseCxxLanguageStandard(argument.expression) {
                    self.cxxLanguageStandard = standard
                }
                continue
            }
            
            if argument.label?.text == "targets" {
                guard let targetsArray = argument.expression.as(ArrayExprSyntax.self) else {
                    limitations.append(
                        .unsupportedExpression(
                            argument.expression,
                            expected: "array of targets"
                        )
                    )
                    continue
                }
                
                // Parse each target in the array
                for targetElement in targetsArray.elements {
                    if let target = parseTarget(targetElement.expression) {
                        self.targets.append(target)
                    }
                }
                continue
            }

            // Unhandled argument.
            limitations.append(.unsupportedArgument(argument, callee: "Package"))
        }
    }
    
    /// Parse a target declaration like .target(name: "foo", dependencies: [...])
    private func parseTarget(_ expr: ExprSyntax) -> TargetDescription? {
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil, // Leading dot syntax
              let methodName = memberAccess.declName.baseName.identifier?.name else {
            limitations.append(.unsupportedExpression(expr, expected: "target declaration"))
            return nil
        }
        
        // Determine target type from method name
        let targetType: TargetDescription.TargetKind
        switch methodName {
        case "target":
            targetType = .regular
        case "testTarget":
            targetType = .test
        case "executableTarget":
            targetType = .executable
        case "systemLibrary":
            targetType = .system
        case "binaryTarget":
            targetType = .binary
        case "plugin":
            targetType = .plugin
        case "macro":
            targetType = .macro
        default:
            limitations.append(.unsupportedExpression(expr, expected: "known target type"))
            return nil
        }
        
        // Parse target arguments
        var name: String?
        var dependencies: [TargetDescription.Dependency] = []
        var path: String? = nil
        var exclude: [String] = []
        var sources: [String]? = nil
        var publicHeadersPath: String? = nil
        
        for argument in functionCall.arguments {
            let label = argument.label?.text
            
            if label == "name" {
                name = argument.expression.asStringLiteralValue()
            } else if label == "dependencies" {
                if let depsArray = argument.expression.as(ArrayExprSyntax.self) {
                    for depElement in depsArray.elements {
                        if let dep = parseTargetDependency(depElement.expression) {
                            dependencies.append(dep)
                        }
                    }
                }
            } else if label == "path" {
                path = argument.expression.asStringLiteralValue()
            } else if label == "exclude" {
                if let excludeArray = argument.expression.as(ArrayExprSyntax.self) {
                    for element in excludeArray.elements {
                        if let pathString = element.expression.asStringLiteralValue() {
                            exclude.append(pathString)
                        }
                    }
                }
            } else if label == "sources" {
                if let sourcesArray = argument.expression.as(ArrayExprSyntax.self) {
                    var sourcesParsed: [String] = []
                    for element in sourcesArray.elements {
                        if let sourceString = element.expression.asStringLiteralValue() {
                            sourcesParsed.append(sourceString)
                        }
                    }
                    sources = sourcesParsed
                }
            } else if label == "publicHeadersPath" {
                publicHeadersPath = argument.expression.asStringLiteralValue()
            } else {
                // Unknown/unsupported argument - not a limitation, just skip it
                continue
            }
        }
        
        guard let targetName = name else {
            limitations.append(.unsupportedExpression(expr, expected: "target with name"))
            return nil
        }
        
        do {
            return try TargetDescription(
                name: targetName,
                dependencies: dependencies,
                path: path,
                url: nil,
                exclude: exclude,
                sources: sources,
                resources: [],
                publicHeadersPath: publicHeadersPath,
                type: targetType
            )
        } catch {
            // If TargetDescription initialization fails (e.g., invalid property combinations),
            // treat it as a limitation
            limitations.append(.unsupportedExpression(expr, expected: "valid target configuration"))
            return nil
        }
    }
    
    /// Parse a target dependency like "dep1", .target(name: "dep2"), or .product(name: "dep3", package: "Pkg")
    private func parseTargetDependency(_ expr: ExprSyntax) -> TargetDescription.Dependency? {
        // Case 1: String literal dependency (e.g., "dep1")
        if let depName = expr.asStringLiteralValue() {
            return .byName(name: depName, condition: nil)
        }
        
        // Case 2: .target(name: ...) or .product(name: ..., package: ...)
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil, // Leading dot syntax
              let methodName = memberAccess.declName.baseName.identifier?.name else {
            limitations.append(.unsupportedExpression(expr, expected: "target dependency"))
            return nil
        }
        
        if methodName == "target" {
            // Parse .target(name: "...")
            for argument in functionCall.arguments {
                if argument.label?.text == "name" {
                    if let name = argument.expression.asStringLiteralValue() {
                        return .target(name: name, condition: nil)
                    }
                }
            }
            limitations.append(.unsupportedExpression(expr, expected: ".target with name"))
            return nil
        } else if methodName == "product" {
            // Parse .product(name: "...", package: "...")
            var name: String?
            var package: String?
            
            for argument in functionCall.arguments {
                let label = argument.label?.text
                if label == "name" {
                    name = argument.expression.asStringLiteralValue()
                } else if label == "package" {
                    package = argument.expression.asStringLiteralValue()
                }
            }
            
            if let productName = name {
                return .product(name: productName, package: package, moduleAliases: nil, condition: nil)
            }
            limitations.append(.unsupportedExpression(expr, expected: ".product with name"))
            return nil
        } else {
            limitations.append(.unsupportedExpression(expr, expected: ".target or .product dependency"))
            return nil
        }
    }
    
    /// Parse a system package provider like .brew(["openssl"]) or .apt(["openssl", "libssl-dev"])
    private func parseSystemPackageProvider(_ expr: ExprSyntax) -> SystemPackageProviderDescription? {
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil, // Leading dot syntax
              let methodName = memberAccess.declName.baseName.identifier?.name else {
            limitations.append(.unsupportedExpression(expr, expected: "system package provider"))
            return nil
        }
        
        // Parse the array argument
        guard let firstArg = functionCall.arguments.first,
              firstArg.label == nil,
              let arrayExpr = firstArg.expression.as(ArrayExprSyntax.self) else {
            limitations.append(.unsupportedExpression(expr, expected: "provider with package names array"))
            return nil
        }
        
        var packages: [String] = []
        for element in arrayExpr.elements {
            if let packageName = element.expression.asStringLiteralValue() {
                packages.append(packageName)
            }
        }
        
        switch methodName {
        case "brew":
            return .brew(packages)
        case "apt":
            return .apt(packages)
        case "yum":
            return .yum(packages)
        case "nuget":
            return .nuget(packages)
        default:
            limitations.append(.unsupportedExpression(expr, expected: "known provider type"))
            return nil
        }
    }
    
    /// Parse a product declaration like .executable(name: "tool", targets: ["tool"])
    private func parseProduct(_ expr: ExprSyntax) -> ProductDescription? {
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil, // Leading dot syntax
              let methodName = memberAccess.declName.baseName.identifier?.name else {
            limitations.append(.unsupportedExpression(expr, expected: "product declaration"))
            return nil
        }
        
        // Parse product arguments
        var name: String?
        var targets: [String] = []
        var productType: ProductType?
        
        for argument in functionCall.arguments {
            let label = argument.label?.text
            
            if label == "name" {
                name = argument.expression.asStringLiteralValue()
            } else if label == "targets" {
                if let targetsArray = argument.expression.as(ArrayExprSyntax.self) {
                    for targetElement in targetsArray.elements {
                        if let targetName = targetElement.expression.asStringLiteralValue() {
                            targets.append(targetName)
                        }
                    }
                }
            } else if label == "type" {
                // Parse library type like .dynamic or .static
                if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                   memberAccess.base == nil,
                   let typeName = memberAccess.declName.baseName.identifier?.name {
                    switch typeName {
                    case "dynamic":
                        productType = .library(.dynamic)
                    case "static":
                        productType = .library(.static)
                    default:
                        break
                    }
                }
            }
        }
        
        guard let productName = name else {
            limitations.append(.unsupportedExpression(expr, expected: "product with name"))
            return nil
        }
        
        // Determine product type from method name if not explicitly set
        let finalProductType: ProductType
        switch methodName {
        case "executable":
            finalProductType = .executable
        case "library":
            finalProductType = productType ?? .library(.automatic)
        case "plugin":
            finalProductType = .plugin
        default:
            limitations.append(.unsupportedExpression(expr, expected: "known product type"))
            return nil
        }
        
        do {
            return try ProductDescription(
                name: productName,
                type: finalProductType,
                targets: targets
            )
        } catch {
            limitations.append(.unsupportedExpression(expr, expected: "valid product configuration"))
            return nil
        }
    }
    
    /// Parse C language standard like .iso9899_199409
    private func parseCLanguageStandard(_ expr: ExprSyntax) -> String? {
        guard let memberAccess = expr.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil, // Leading dot syntax
              let standardName = memberAccess.declName.baseName.identifier?.name else {
            limitations.append(.unsupportedExpression(expr, expected: "C language standard"))
            return nil
        }
        
        // Map standard names to their string representations
        switch standardName {
        case "c89": return "c89"
        case "c90": return "c90"
        case "iso9899_1990": return "iso9899:1990"
        case "iso9899_199409": return "iso9899:199409"
        case "gnu89": return "gnu89"
        case "gnu90": return "gnu90"
        case "c99": return "c99"
        case "iso9899_1999": return "iso9899:1999"
        case "gnu99": return "gnu99"
        case "c11": return "c11"
        case "iso9899_2011": return "iso9899:2011"
        case "gnu11": return "gnu11"
        case "c17": return "c17"
        case "iso9899_2017": return "iso9899:2017"
        case "gnu17": return "gnu17"
        default:
            limitations.append(.unsupportedExpression(expr, expected: "known C language standard"))
            return nil
        }
    }
    
    /// Parse C++ language standard like .gnucxx14
    private func parseCxxLanguageStandard(_ expr: ExprSyntax) -> String? {
        guard let memberAccess = expr.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil, // Leading dot syntax
              let standardName = memberAccess.declName.baseName.identifier?.name else {
            limitations.append(.unsupportedExpression(expr, expected: "C++ language standard"))
            return nil
        }
        
        // Map standard names to their string representations
        switch standardName {
        case "cxx98": return "c++98"
        case "cxx03": return "c++03"
        case "gnucxx98": return "gnu++98"
        case "gnucxx03": return "gnu++03"
        case "cxx11": return "c++11"
        case "gnucxx11": return "gnu++11"
        case "cxx14": return "c++14"
        case "gnucxx14": return "gnu++14"
        case "cxx17": return "c++17"
        case "gnucxx17": return "gnu++17"
        case "cxx20": return "c++20"
        case "gnucxx20": return "gnu++20"
        case "cxx23": return "c++23"
        case "gnucxx23": return "gnu++23"
        default:
            limitations.append(.unsupportedExpression(expr, expected: "known C++ language standard"))
            return nil
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

    /// Extract an array of integer values from the expression, if it is one.
    fileprivate func asIntegerArray() -> [Int]? {
        guard let arrayExpr = self.as(ArrayExprSyntax.self) else {
            return nil
        }

        var result: [Int] = []
        for element in arrayExpr.elements {
            guard let intLiteral = element.expression.as(IntegerLiteralExprSyntax.self),
                  let value = Int(intLiteral.literal.text) else {
                return nil
            }
            result.append(value)
        }

        return result
    }
    
    /// Extract an array of Swift language versions from the expression.
    /// Supports both old-style integers [3, 4] and new-style member references [.v3, .v4, .version("5")].
    fileprivate func asSwiftLanguageVersionArray() -> [SwiftLanguageVersion]? {
        guard let arrayExpr = self.as(ArrayExprSyntax.self) else {
            return nil
        }
        
        var result: [SwiftLanguageVersion] = []
        for element in arrayExpr.elements {
            let expr = element.expression
            
            // Try to parse as member access (e.g., .v3, .v4, .v4_2)
            if let memberAccess = expr.as(MemberAccessExprSyntax.self),
               memberAccess.base == nil,  // Leading dot syntax
               let memberName = memberAccess.declName.baseName.identifier?.name {
                // Map member names to version strings
                let versionString: String
                switch memberName {
                case "v3": versionString = "3"
                case "v4": versionString = "4"
                case "v4_2": versionString = "4.2"
                case "v5": versionString = "5"
                case "v6": versionString = "6"
                default:
                    return nil  // Unknown version member
                }
                
                guard let version = SwiftLanguageVersion(string: versionString) else {
                    return nil
                }
                result.append(version)
                continue
            }
            
            // Try to parse as function call (e.g., .version("5"))
            if let functionCall = expr.as(FunctionCallExprSyntax.self),
               let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
               memberAccess.base == nil,  // Leading dot syntax
               let methodName = memberAccess.declName.baseName.identifier?.name,
               methodName == "version",
               let firstArg = functionCall.arguments.first,
               firstArg.label == nil,
               let versionString = firstArg.expression.asStringLiteralValue() {
                guard let version = SwiftLanguageVersion(string: versionString) else {
                    return nil
                }
                result.append(version)
                continue
            }
            
            // Unable to parse this element
            return nil
        }
        
        return result
    }
}
