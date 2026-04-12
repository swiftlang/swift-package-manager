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

#if !DISABLE_PARSING_MANIFEST_LOADER
import Basics
import Dispatch
import Foundation
import PackageModel
import SourceControl

public import SwiftDiagnostics
import SwiftIfConfig
import SwiftOperators
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

    /// Build configurations indexed by language mode.
    let configurations: [SwiftLanguageVersion: StaticBuildConfiguration]

    let environment: [String: String]?

    /// Initialize the manifest loader with the given static build
    /// configuration, which will be used to evaluate `#if` conditions in
    /// the manifest.
    public init(
        configurations: [SwiftLanguageVersion: StaticBuildConfiguration],
        pruneDependencies: Bool = false,
        environment: [String: String]?
    ) {
        self.pruneDependencies = pruneDependencies
        self.configurations = configurations
        self.environment = environment
    }

    /// Initialize the manifest loader using the given host toolchain.
    /// The toolchain will be used to derive the static build configuration.
    public convenience init(
        toolchain: UserToolchain,
        pruneDependencies: Bool = false,
        extraManifestFlags: [String],
        environment: [String: String]?
    ) throws {
        var configurations: [SwiftLanguageVersion: StaticBuildConfiguration] = [:]
        for version in SwiftLanguageVersion.supportedSwiftLanguageVersions {
            let config = try StaticBuildConfiguration.getHostConfiguration(
                usingSwiftCompiler: toolchain.swiftCompilerPathForManifests,
                extraManifestFlags: extraManifestFlags + ["-swift-version", version.rawValue]
            )
            configurations[version] = config
        }

        self.init(
            configurations: configurations,
            pruneDependencies: pruneDependencies,
            environment: environment
        )
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
    ) throws(ManifestParserError) -> Manifest {
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

        let contextModel = StaticContextModel(
            packageDirectory: manifestPath.parentDirectory.pathString,
            environment: environment ?? ProcessInfo.processInfo.environment
        )

        // Adjust the language mode in the build configuration to match
        // the manifest's tools version. The static build configuration
        // from the compiler reflects its default language mode, but the
        // manifest is compiled with the language version implied by its
        // tools version (e.g., tools version 6.0 → Swift 6 mode).
        let toolsLanguageVersion = manifestToolsVersion.swiftLanguageVersion
        guard let config = configurations[toolsLanguageVersion] else {
            throw .unknownLanguageMode(toolsLanguageVersion)
        }

        // Parse the source file.
        var sourceFile: SourceFileSyntax = Parser.parse(source: manifestContents)

        // Fold all operators in the source file so we can evaluate
        // expressions.
        var operatorLimitations: [ManifestParseLimitation] = []
        sourceFile = OperatorTable.standardOperators.foldAll(sourceFile) { error in
            operatorLimitations.append(.operatorPrecedence(error.asDiagnostic.node))
        }.cast(SourceFileSyntax.self)

        if !operatorLimitations.isEmpty {
            throw .limitations(operatorLimitations)
        }

        // Check for syntax errors that would prevent us from going further.
        let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: sourceFile)
        if !diagnostics.isEmpty {
            // Filter out diagnostics in unparsed regions.
            let configured = sourceFile.configuredRegions(in: config)
            let relevantDiagnostics = diagnostics.filter { diag in
                switch configured.isActive(diag.node) {
                case .active, .inactive:
                    true

                case .unparsed:
                    false
                }
            }

            if !relevantDiagnostics.isEmpty {
                throw .syntaxErrors(relevantDiagnostics)
            }
        }

        // Walk the source file to parse
        let visitor = ManifestParseVisitor(
            manifestPath: manifestPath,
            configuration: config,
            dependencyMapper: dependencyMapper,
            fileSystem: fileSystem,
            contextModel: contextModel,
            defaultPackageAccess: manifestToolsVersion >= .v5_9
        )
        visitor.walk(sourceFile)

        // If the visitor produced any diagnostics while evaluating #if
        // conditions (e.g., canImport checks that StaticBuildConfiguration
        // cannot evaluate), treat them as limitations so we fall back to the
        // executing manifest loader.
        if !visitor.diagnostics.isEmpty {
            visitor.limitations.append(
                contentsOf: visitor.diagnostics.map {
                    .ifConfigDiagnostic($0)
                }
            )
        }

        // If we hit any of the limitations of the manifest parser, bail out
        // now.
        if !visitor.limitations.isEmpty {
            throw .limitations(visitor.limitations)
        }

        /// We need to found a package name to continue.
        guard let packageName = visitor.packageName else {
            throw .missingPackageName
        }

        // Convert legacy system library packages to the current target-based
        // model, mirroring the same logic in ManifestLoader.load().
        //
        // An old-style system library package has no explicit targets or
        // products in the manifest, but has a `module.modulemap` file at the
        // package root. In that case we synthesize a system library target and
        // an automatic library product that wraps it, carrying over the
        // package-level pkgConfig and providers.
        var products = visitor.products ?? []
        var targets = visitor.targets ?? []
        if products.isEmpty, targets.isEmpty,
            fileSystem.isFile(manifestPath.parentDirectory.appending(component: moduleMapFilename)) {
            // These initializers only throw for invalid argument combinations.
            // The arguments below are always valid (matching what ManifestLoader
            // synthesizes for legacy system library packages), so force-try is safe.
            products.append(try! ProductDescription(
                name: packageName,
                type: .library(.automatic),
                targets: [packageName])
            )
            targets.append(try! TargetDescription(
                name: packageName,
                path: "",
                type: .system,
                packageAccess: false,
                pkgConfig: visitor.pkgConfig,
                providers: visitor.providers
            ))
        }

        return Manifest(
            displayName: packageName,
            packageIdentity: packageIdentity,
            path: manifestPath,
            packageKind: packageKind,
            packageLocation: packageLocation,
            defaultLocalization: visitor.defaultLocalization,
            platforms: visitor.platforms ?? [],
            version: packageVersion?.version,
            revision: packageVersion?.revision,
            toolsVersion: manifestToolsVersion,
            pkgConfig: visitor.pkgConfig,
            providers: visitor.providers,
            cLanguageStandard: visitor.cLanguageStandard,
            cxxLanguageStandard: visitor.cxxLanguageStandard,
            swiftLanguageVersions: visitor.swiftLanguageVersions,
            dependencies: visitor.dependencies ?? [],
            products: products,
            targets: targets,
            traits: Set(visitor.traits ?? []),
            pruneDependencies: self.pruneDependencies
        )
    }
}

/// Syntax visitor that processes the parsed manifest.
class ManifestParseVisitor: ActiveSyntaxAnyVisitor {
    /// Limitations encountered while processing the manifest.
    var limitations: [ManifestParseLimitation] = []

    /// The path to the manifest file (used for resolving relative paths)
    let manifestPath: AbsolutePath
    
    /// Dependency mapper for handling path resolution and mirrors
    let dependencyMapper: DependencyMapper
    
    /// File system for path operations
    let fileSystem: FileSystem
    
    /// Context model for Context API support (packageDirectory, gitInformation, environment)
    let contextModel: StaticContextModel

    /// Package name
    var packageName: String?

    /// The default localization for resources.
    var defaultLocalization: String?

    /// Platforms.
    var platforms: [PlatformDescription]?

    /// Targets
    var targets: [TargetDescription]?

    var pkgConfig: String?

    /// Swift language versions.
    var swiftLanguageVersions: [SwiftLanguageVersion]?

    /// Package dependencies.
    var dependencies: [PackageDependency]?

    /// System package providers.
    var providers: [SystemPackageProviderDescription]?

    /// Products.
    var products: [ProductDescription]?

    /// Traits.
    var traits: [TraitDescription]?

    /// C++ language standard.
    var cxxLanguageStandard: String?

    /// C language standard.
    var cLanguageStandard: String?

    var defaultPackageAccess: Bool

    /// Storage for global variables defined in the manifest
    /// Maps variable names to their expression syntax nodes for lazy evaluation
    private var globalVariables: [String: ExprSyntax] = [:]

    init(
        manifestPath: AbsolutePath,
        configuration: StaticBuildConfiguration,
        dependencyMapper: DependencyMapper,
        fileSystem: FileSystem,
        contextModel: StaticContextModel,
        defaultPackageAccess: Bool
    ) {
        self.manifestPath = manifestPath
        self.dependencyMapper = dependencyMapper
        self.fileSystem = fileSystem
        self.contextModel = contextModel
        self.defaultPackageAccess = defaultPackageAccess
        super.init(viewMode: .fixedUp, configuration: configuration)
    }

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

    /// Process global variable declarations to find the "package" declaration or global variables.
    override func visit(_ varNode: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Dig out the name and initializer.
        guard let (varName, initializer) = varNode.asSingleInitializedVariable() else {
            limitations.append(.unsupportedVariableForm(varNode))
            return .skipChildren
        }

        // Check whether we know this call or not.
        if let (knownCall, arguments) = initializer.asKnownCall() {
            // Handle any top-level known calls here.
            switch knownCall {
            case .package:
                handlePackageDeclaration(initializer: initializer, arguments: arguments)
            }
            return .skipChildren
        }

        // Store the expression for this global variable
        // We'll parse it on-demand when it's referenced
        globalVariables[varName.name] = initializer
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

/// MARK: Handling arrays and variable resolution
extension ManifestParseVisitor {
    /// An error that can occur when resolving an expression to a value.
    enum ResolutionError: Error {
        case unhandledExpression(ExprSyntax)
        case missingValue(ExprSyntax, description: String)

        var nearestExpr: ExprSyntax {
            switch self {
            case .unhandledExpression(let expr):
                return expr
            case .missingValue(let expr, description: _):
                return expr
            }
        }
    }

    /// Attempt to resolve the given expression using the given matching function,
    /// writing the resulting value into `result` if it succeeds and recording
    /// a limitation if it fails.
    ///
    /// \returns true on success, false (and records a limitation) on failure
    @discardableResult
    private func resolve<T>(_ expr: ExprSyntax, description: String, into result: inout T?, matcher: (ExprSyntax) throws(ResolutionError) -> T) -> Bool {
        do {
            result = try matcher(expr)
            return true
        } catch {
            limitations.append(.unsupportedExpression(error.nearestExpr, expected: description))
        }
        return false
    }

    /// Atempt to resolve the given expression for an arbitrary type that conforms
    /// to ParsingResolvable. The result is written into result on success, and a
    /// limitation is reported on failure.
    @discardableResult
    private func resolve<T: ParsingResolvable>(_ expr: ExprSyntax, description: String, into result: inout T?) -> Bool {
        resolve(expr, description: description, into: &result) { expr throws(ResolutionError) in
            try T.resolve(expr, in: self)
        }
    }

    /// Attempt to resolve the given expression using the given matching function,
    /// where the matcher may return nil to indicate no value (as opposed to an error).
    /// The result is written into `result` if non-nil; a limitation is recorded on error.
    @discardableResult
    private func resolve<T>(_ expr: ExprSyntax, description: String, into result: inout T?, matcher: (ExprSyntax) throws(ResolutionError) -> T?) -> Bool {
        do {
            result = try matcher(expr)
            return true
        } catch {
            limitations.append(.unsupportedExpression(error.nearestExpr, expected: description))
        }
        return false
    }

    /// Attempt to resolve the given expression as an array and append to the given array.
    /// Records a limitation if resolution fails.
    ///
    /// \returns true on success, false (and records a limitation) on failure
    @discardableResult
    private func resolve<T>(_ expr: ExprSyntax, description: String, appendingInto result: inout [T], matcher: (ExprSyntax) throws(ResolutionError) -> T) -> Bool {
        var temp: [T]?
        let ok = resolve(expr, description: description, into: &temp) { expr throws(ResolutionError) in
            try resolveArray(expr, elementParser: matcher)
        }
        if let temp { result.append(contentsOf: temp) }
        return ok
    }

    /// Attempt to resolve the given expression as an array and append to the given array.
    /// Records a limitation if resolution fails.
    ///
    /// \returns true on success, false (and records a limitation) on failure
    @discardableResult
    private func resolve<T: ParsingResolvable>(_ expr: ExprSyntax, description: String, appendingInto result: inout [T]) -> Bool {
        return resolve(expr, description: description, appendingInto: &result) { expr throws(ResolutionError) in
            try T.resolve(expr, in: self)
        }
    }

    /// Resolve a string literal expression with support for global variable references and interpolations
    /// - Parameters:
    ///   - expr: The expression to parse (could be a string literal, variable reference, or Context expression)
    /// - Returns: The resolved string value
    /// - Throws: ResolutionError with the narrowest expression that could not be handled, on failure.
    fileprivate func resolveStringLiteral(_ expr: ExprSyntax) throws(ResolutionError) -> String {
        // Case 1: String literal (possibly with interpolations)
        if let stringLiteral = expr.as(StringLiteralExprSyntax.self) {
            // Simple case: no interpolation — use representedLiteralValue to correctly handle
            // escape sequences (e.g. \" in a C preprocessor define value becomes ").
            if let value = stringLiteral.representedLiteralValue {
                return value
            }

            // Complex case: handle interpolations with Context values and global variables
            var result = ""
            for segment in stringLiteral.segments {
                switch segment {
                case .stringSegment(let contents):
                    // For string segments.
                    result += contents.content.text

                case .expressionSegment(let exprSegment):
                    // Try to evaluate the interpolated expression
                    guard let interpolatedExpr = exprSegment.expressions.first?.expression, exprSegment.expressions.count == 1 else {
                        throw .unhandledExpression(expr)
                    }

                    // Recursively resolve the interpolated expression
                    // This allows variable references, Context expressions, etc.
                    result += try resolveStringLiteral(interpolatedExpr)
                }
            }

            return result
        }

        // Case 2: Variable reference - resolve and recurse
        if let varRef = expr.as(DeclReferenceExprSyntax.self),
           let varName = varRef.baseName.identifier?.name,
           let value = globalVariables[varName] {
            // Recursively resolve the variable's value
            return try resolveStringLiteral(value)
        }
        
        // Case 3: Direct Context expression (e.g., Context.packageDirectory)
        return try evaluateContextExpression(expr)
    }

    /// Evaluate a Context expression like Context.gitInformation?.currentTag or Context.environment["KEY"]
    /// Returns the string representation of the value, or throws an error if something cannot be evaluated.
    private func evaluateContextExpression(_ expr: ExprSyntax) throws(ResolutionError) -> String {
        var currentExpr: ExprSyntax = expr
        var nilCoalescingDefault: String? = nil

        // Handle nil-coalescing operator (??)
        if let infixExpr = currentExpr.as(InfixOperatorExprSyntax.self),
           let op = infixExpr.operator.as(BinaryOperatorExprSyntax.self),
           op.operator.text.trimmingCharacters(in: .whitespaces) == "??" {
            // Get the default value from the right side
            nilCoalescingDefault = try resolveStringLiteral(infixExpr.rightOperand)

            // Continue evaluating the left side
            currentExpr = infixExpr.leftOperand
        }
        
        // Handle boolean comparison (== true)
        if let infixExpr = currentExpr.as(InfixOperatorExprSyntax.self),
           let op = infixExpr.operator.as(BinaryOperatorExprSyntax.self),
           op.operator.text.trimmingCharacters(in: .whitespaces) == "==" {
            // Check if right side is 'true'
            if let boolLit = infixExpr.rightOperand.as(BooleanLiteralExprSyntax.self),
               boolLit.literal.tokenKind == .keyword(.true) {
                currentExpr = infixExpr.leftOperand
            } else {
                throw .unhandledExpression(infixExpr.rightOperand)
            }
        }
        
        // Check for subscript access (e.g., Context.environment["KEY"])
        if let subscriptExpr = currentExpr.as(SubscriptCallExprSyntax.self) {
            // Parse the base expression (e.g., Context.environment)
            var baseParts: [String] = []
            var baseExpr = subscriptExpr.calledExpression
            
            // Walk through the member access chain
            while true {
                if let memberAccess = baseExpr.as(MemberAccessExprSyntax.self) {
                    baseParts.insert(memberAccess.declName.baseName.text, at: 0)
                    if let base = memberAccess.base {
                        baseExpr = base
                    } else {
                        break
                    }
                } else if let declRef = baseExpr.as(DeclReferenceExprSyntax.self) {
                    baseParts.insert(declRef.baseName.text, at: 0)
                    break
                } else {
                    throw .unhandledExpression(baseExpr)
                }
            }
            
            // Check if it's Context.environment
            if baseParts.count == 2 && baseParts[0] == "Context" && baseParts[1] == "environment" {
                // Get the subscript key
                if let firstArg = subscriptExpr.arguments.first {
                   let keyString = try resolveStringLiteral(firstArg.expression)
                    if let value = contextModel.environment[keyString] {
                        return value
                    } else if let nilCoalescingDefault {
                        return nilCoalescingDefault
                    } else {
                        throw .unhandledExpression(firstArg.expression)
                    }
                }
            }
            
            throw .unhandledExpression(currentExpr)
        }
        
        // Now parse the member access chain
        // Expected patterns:
        // - Context.packageDirectory
        // - Context.gitInformation?.currentTag
        // - Context.gitInformation?.currentCommit
        // - Context.gitInformation?.hasUncommittedChanges
        
        // Extract all parts of the member access chain
        var parts: [String] = []
        
        // Walk backwards through the member access chain
        while true {
            if let memberAccess = currentExpr.as(MemberAccessExprSyntax.self) {
                // Add the member name
                parts.insert(memberAccess.declName.baseName.text, at: 0)
                
                if let base = memberAccess.base {
                    currentExpr = base
                } else {
                    // No more base, we're done
                    break
                }
            } else if let optChain = currentExpr.as(OptionalChainingExprSyntax.self) {
                // Skip the optional chaining wrapper and continue
                currentExpr = optChain.expression
            } else if let postfixUnary = currentExpr.as(PostfixOperatorExprSyntax.self) {
                // This handles the ? in optional chaining
                currentExpr = postfixUnary.expression
            } else if let declRef = currentExpr.as(DeclReferenceExprSyntax.self) {
                // This is the base identifier (e.g., "Context")
                parts.insert(declRef.baseName.text, at: 0)
                break
            } else {
                // Unknown expression structure
                throw .unhandledExpression(currentExpr)
            }
        }
        
        // Now evaluate based on the parts
        guard parts.count >= 2 && parts[0] == "Context" else {
            throw .unhandledExpression(expr)
        }
        
        switch parts[1] {
        case "packageDirectory":
            return contextModel.packageDirectory
            
        case "gitInformation":
            guard parts.count >= 3 else {
                throw .unhandledExpression(expr)
            }
            guard let gitInfo = contextModel.gitInformation else {
                if let nilCoalescingDefault {
                    return nilCoalescingDefault
                } else {
                    throw .unhandledExpression(expr)
                }
            }
            
            switch parts[2] {
            case "currentTag":
                if let tag = gitInfo.currentTag {
                    return tag
                } else if let nilCoalescingDefault {
                    return nilCoalescingDefault
                } else {
                    throw .unhandledExpression(expr)
                }

            case "currentCommit":
                return gitInfo.currentCommit
                
            case "hasUncommittedChanges":
                let value = gitInfo.hasUncommittedChanges
                return value ? "true" : "false"
                
            default:
                throw .unhandledExpression(expr)
            }
            
        default:
            throw .unhandledExpression(expr)
        }
    }
    
    /// Parse an array expression with full support for variable resolution, concatenation, and element parsing
    /// - Parameters:
    ///   - expr: The expression to parse (could be an array literal, variable reference, or array concatenation)
    ///   - elementParser: Closure that parses individual array elements
    /// - Returns: Array of parsed elements
    /// - Throws: ResolutionError if something could not be parsed.
    ///
    /// This function recursively handles:
    /// - Variable references (e.g., `myArray`)
    /// - Array concatenation (e.g., `array1 + array2`)
    /// - Nested combinations (e.g., `var1 + var2 + [.item3]`)
    fileprivate func resolveArray<T>(
        _ expr: ExprSyntax,
        elementParser: (ExprSyntax) throws(ResolutionError) -> T
    ) throws(ResolutionError) -> [T] {
        // Case 1: Variable reference - resolve and recurse
        if let varRef = expr.as(DeclReferenceExprSyntax.self),
           let varName = varRef.baseName.identifier?.name,
           let value = globalVariables[varName] {
            // Recursively resolve and parse the variable's value
            return try resolveArray(
                value,
                elementParser: elementParser
            )
        }
        
        // Case 2: Binary expression (array concatenation with +)
        if let infixExpr = expr.as(InfixOperatorExprSyntax.self),
           let op = infixExpr.operator.as(BinaryOperatorExprSyntax.self),
           op.operator.text.trimmingCharacters(in: .whitespaces) == "+" {
            
            // Recursively resolve and parse both operands
            let leftElements = try resolveArray(
                infixExpr.leftOperand,
                elementParser: elementParser
            )

            let rightElements = try resolveArray(
                infixExpr.rightOperand,
                elementParser: elementParser
            )
            
            // Combine the parsed elements from both sides
            return leftElements + rightElements
        }
        
        // Case 3: Array literal - parse its elements directly
        guard let arrayExpr = expr.as(ArrayExprSyntax.self) else {
            throw .unhandledExpression(expr)
        }
        
        // Parse each element in the array
        var results: [T] = []
        for element in arrayExpr.elements {
            var elementExpr = element.expression
            if let varRef = element.expression.as(DeclReferenceExprSyntax.self),
               let varName = varRef.baseName.identifier?.name,
               let value = globalVariables[varName] {
                elementExpr = value
            }

            results.append(try elementParser(elementExpr))
        }
        
        return results
    }

    /// Parse a platform name as used in a `.when(platforms: [...])` condition.
    /// Handles both plain enum members (e.g. `.linux`) and custom platforms
    /// (e.g. `.custom("freebsd")`).
    /// - Parameters:
    ///   - expr: The expression to parse
    /// - Returns: The platform name
    private func parsePlatformConditionName(_ expr: ExprSyntax) throws (ResolutionError) -> String {
        if let name = expr.asEnumMember() {
            return name
        }

        // Handle .custom("platformName")
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil,
              memberAccess.declName.baseName.identifier?.name == "custom",
              let firstArg = functionCall.arguments.first,
              firstArg.label == nil else {
            throw .unhandledExpression(expr)
        }
        
        return try resolveStringLiteral(firstArg.expression)
    }
}

/// MARK: Declaration handling
extension ManifestParseVisitor {
    private func parseSwiftLanguageVersions(_ expr: ExprSyntax) throws(ResolutionError) -> [SwiftLanguageVersion] {
        // Try new-style syntax first (e.g., [.v3, .v4, .version("5")])
        if let versions = expr.asSwiftLanguageVersionArray() {
            return versions
        }

        // Fall back to old-style integer array syntax (e.g., [3, 4])
        guard let intVersions = expr.asIntegerArray() else {
            throw .unhandledExpression(expr)
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
                if let arrayExpr = expr.as(ArrayExprSyntax.self),
                   index < arrayExpr.elements.count {
                    let element = arrayExpr.elements[arrayExpr.elements.index(arrayExpr.elements.startIndex, offsetBy: index)]
                    limitations.append(.invalidSwiftLanguageVersion(element.expression, value: versionString))
                }
                continue
            }
            validatedVersions.append(swiftVersion)
        }

        // Only set if we successfully validated all versions
        if hasValidationError {
            throw .unhandledExpression(expr)
        }

        return validatedVersions
    }

    func handlePackageDeclaration(
        initializer: ExprSyntax,
        arguments: LabeledExprListSyntax
    ) {
        for argument in arguments {
            switch argument.label?.text {
            case "name":
                resolve(argument.expression, description: "package name", into: &self.packageName)

            case "dependencies":
                resolve(argument.expression, description: "array of package dependencies", into: &self.dependencies)

            // Accept both swiftLanguageVersions (deprecated) and swiftLanguageModes (6.0+)
            case "swiftLanguageVersions", "swiftLanguageModes":
                resolve(argument.expression, description: "swift language modes", into: &self.swiftLanguageVersions) { expr throws(ResolutionError) in
                    try parseSwiftLanguageVersions(expr)
                }

            case "pkgConfig":
                resolve(argument.expression, description: "pkgConfig string", into: &self.pkgConfig)

            case "providers":
                resolve(argument.expression, description: "array of providers", into: &self.providers)

            case "products":
                resolve(argument.expression, description: "array of products", into: &self.products)

            case "cLanguageStandard":
                resolve(argument.expression, description: "C language standard", into: &self.cLanguageStandard) { expr throws(ResolutionError) in
                    try parseCLanguageStandard(expr)
                }

            case "cxxLanguageStandard":
                resolve(argument.expression, description: "C++ language standard", into: &self.cxxLanguageStandard) { expr throws(ResolutionError) in
                    try parseCxxLanguageStandard(expr)
                }

            case "platforms":
                resolve(argument.expression, description: "array of platforms", into: &self.platforms)

            case "defaultLocalization":
                resolve(argument.expression, description: "default localization language tag", into: &self.defaultLocalization)

            case "targets":
                resolve(argument.expression, description: "array of targets", into: &self.targets)

            case "traits":
                resolve(argument.expression, description: "array of traits", into: &self.traits)

            default:
                limitations.append(.unsupportedArgument(argument, callee: "Package"))
            }
        }
    }
    
    /// Parse a target declaration like .target(name: "foo", dependencies: [...])
    fileprivate func parseTarget(_ expr: ExprSyntax) throws(ResolutionError) -> TargetDescription {
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil, // Leading dot syntax
              let methodName = memberAccess.declName.baseName.identifier?.name else {
            throw .unhandledExpression(expr)
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
            throw .unhandledExpression(expr)
        }

        // Parse target arguments
        var name: String? = nil
        var dependencies: [TargetDescription.Dependency]? = nil
        var path: String? = nil
        var url: String? = nil
        var checksum: String? = nil
        var exclude: [String]? = nil
        var sources: [String]? = nil
        var resources: [TargetDescription.Resource]? = nil
        var publicHeadersPath: String? = nil
        var pkgConfig: String? = nil
        var providers: [SystemPackageProviderDescription]? = nil
        var pluginCapability: TargetDescription.PluginCapability? = nil
        var settings: [TargetBuildSettingDescription.Setting] = []
        var pluginUsages: [TargetDescription.PluginUsage]? = nil
        // Binary and system library targets always have packageAccess: false;
        // neither exposes package-access symbols and the PackageDescription API
        // does not accept a packageAccess parameter for binaryTarget(…) or
        // systemLibrary(…).
        var packageAccess: Bool = (targetType == .binary || targetType == .system) ? false : defaultPackageAccess

        for argument in functionCall.arguments {
            let label = argument.label?.text

            switch label {
            case "name":
                resolve(argument.expression, description: "target name", into: &name)
            case "dependencies":
                resolve(argument.expression, description: "array of target dependencies", into: &dependencies)
            case "path":
                resolve(argument.expression, description: "path string", into: &path)
            case "url":
                resolve(argument.expression, description: "url string", into: &url)
            case "checksum":
                resolve(argument.expression, description: "checksum string", into: &checksum)
            case "exclude":
                resolve(argument.expression, description: "array of excluded paths", into: &exclude)
            case "sources":
                resolve(argument.expression, description: "array of source file paths", into: &sources)
            case "publicHeadersPath":
                resolve(argument.expression, description: "publicHeadersPath string", into: &publicHeadersPath)
            case "pkgConfig":
                resolve(argument.expression, description: "pkgConfig string", into: &pkgConfig)
            case "providers":
                resolve(argument.expression, description: "array of system package providers", into: &providers)
            case "resources":
                resolve(argument.expression, description: "array of resources", into: &resources)
            case "capability":
                resolve(argument.expression, description: "plugin capability", into: &pluginCapability)
            case "cSettings":
                resolve(argument.expression, description: "array of C build settings", appendingInto: &settings) { expr throws(ResolutionError) in
                    try parseBuildSetting(expr, tool: .c)
                }
            case "cxxSettings":
                resolve(argument.expression, description: "array of C++ build settings", appendingInto: &settings) { expr throws(ResolutionError) in
                    try parseBuildSetting(expr, tool: .cxx)
                }
            case "swiftSettings":
                resolve(argument.expression, description: "array of Swift build settings", appendingInto: &settings) { expr throws(ResolutionError) in
                    try parseBuildSetting(expr, tool: .swift)
                }
            case "linkerSettings":
                resolve(argument.expression, description: "array of linker settings", appendingInto: &settings) { expr throws(ResolutionError) in
                    try parseBuildSetting(expr, tool: .linker)
                }
            case "plugins":
                resolve(argument.expression, description: "array of plugin usages", into: &pluginUsages)
            case "packageAccess":
                if let boolValue = argument.expression.asBooleanLiteralValue() {
                    packageAccess = boolValue
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "boolean literal for packageAccess"))
                }
            default:
                limitations.append(.unsupportedArgument(argument, callee: methodName))
            }
        }

        guard let targetName = name else {
            throw .missingValue(expr, description: "target with name")
        }

        do {
            return try TargetDescription(
                name: targetName,
                dependencies: dependencies ?? [],
                path: path,
                url: url,
                exclude: exclude ?? [],
                sources: sources,
                resources: resources ?? [],
                publicHeadersPath: publicHeadersPath,
                type: targetType,
                packageAccess: packageAccess,
                pkgConfig: pkgConfig,
                providers: providers,
                pluginCapability: pluginCapability,
                settings: settings,
                checksum: checksum,
                pluginUsages: pluginUsages
            )
        } catch {
            // If TargetDescription initialization fails (e.g., invalid property combinations),
            // treat it as a limitation
            limitations.append(.unsupportedExpression(expr, expected: "valid target configuration"))
            throw .unhandledExpression(expr)
        }
    }
    
    /// Parse a target dependency like "dep1", .target(name: "dep2"), or .product(name: "dep3", package: "Pkg")
    fileprivate func parseTargetDependency(_ expr: ExprSyntax) throws(ResolutionError) -> TargetDescription.Dependency {
        // If we don't have a member access call, it must be a string literal.
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            // Case 1: String literal dependency (e.g., "dep1")
            var depName: String?
            resolve(expr, description: "target dependency name", into: &depName)
            guard let depName else {
                throw .unhandledExpression(expr)
            }
            return .byName(name: depName, condition: nil)
        }

        // Case 2: .target(name: ...) or .product(name: ..., package: ...)
        switch methodName {
        case "target":
            // Parse .target(name: "...", condition: ...)
            var name: String?
            var condition: PackageConditionDescription?

            for argument in arguments {
                let label = argument.label?.text
                switch label {
                case "name":
                    resolve(argument.expression, description: "target dependency name", into: &name)
                case "condition":
                    resolve(argument.expression, description: "target dependency condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "target"))
                }
            }

            guard let targetName = name else {
                throw .missingValue(expr, description: ".target with name")
            }
            return .target(name: targetName, condition: condition)

        case "product":
            // Parse .product(name: "...", package: "...", moduleAliases: [...], condition: ...)
            var name: String?
            var package: String?
            var moduleAliases: [String: String]?
            var condition: PackageConditionDescription?

            for argument in arguments {
                let label = argument.label?.text
                switch label {
                case "name":
                    resolve(argument.expression, description: "product dependency name", into: &name)
                case "package":
                    resolve(argument.expression, description: "product dependency package", into: &package)
                case "moduleAliases":
                    resolve(argument.expression, description: "module aliases", into: &moduleAliases) { expr throws(ResolutionError) in
                        try parseModuleAliases(expr)
                    }
                case "condition":
                    resolve(argument.expression, description: "product dependency condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "product"))
                }
            }

            guard let productName = name else {
                throw .missingValue(expr, description: ".product with name")
            }
            return .product(name: productName, package: package, moduleAliases: moduleAliases, condition: condition)

        case "byName":
            // Parse .byName(name: "...", condition: ...)
            var name: String?
            var condition: PackageConditionDescription?

            for argument in arguments {
                let label = argument.label?.text
                switch label {
                case "name":
                    resolve(argument.expression, description: "byName dependency name", into: &name)
                case "condition":
                    resolve(argument.expression, description: "byName dependency condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "byName"))
                }
            }

            guard let depName = name else {
                throw .missingValue(expr, description: ".byName with name")
            }
            return .byName(name: depName, condition: condition)

        default:
            throw .unhandledExpression(expr)
        }
    }
    
    /// Parse a package condition like .when(platforms: [.macOS, .linux])
    fileprivate func parsePackageCondition(_ expr: ExprSyntax) throws(ResolutionError) -> PackageConditionDescription? {
        guard let (methodName, arguments) = expr.asMemberAccessCall(),
              methodName == "when" else {
            throw .unhandledExpression(expr)
        }

        var platformNames: [String] = []
        var config: String?
        var traits: [String]?

        for argument in arguments {
            let label = argument.label?.text
            switch label {
            case "platforms":
                resolve(argument.expression, description: "array of platform conditions", appendingInto: &platformNames) { expr throws(ResolutionError) in
                    try parsePlatformConditionName(expr)
                }
            case "configuration":
                resolve(argument.expression, description: "build configuration", into: &config) { expr throws(ResolutionError) -> String in
                    guard let member = expr.asEnumMember() else {
                        throw .unhandledExpression(expr)
                    }

                    return member
                }
            case "traits":
                resolve(argument.expression, description: "array of trait names", into: &traits)
            default:
                limitations.append(.unsupportedArgument(argument, callee: "when"))
            }
        }

        // An empty condition (e.g., .when(platforms: [])) means no condition.
        if config == nil && traits == nil && platformNames.isEmpty {
            return nil
        }

        return PackageConditionDescription(
            platformNames: platformNames.map { $0.lowercased() },
            config: config,
            traits: traits.map { Set($0) }
        )
    }
    
    /// Parse module aliases dictionary like ["OriginalName": "AliasName", ...]
    private func parseModuleAliases(_ expr: ExprSyntax) throws(ResolutionError) -> [String: String] {
        guard let dictExpr = expr.as(DictionaryExprSyntax.self) else {
            throw .unhandledExpression(expr)
        }

        var aliases: [String: String] = [:]

        // Check if it's a dictionary with elements
        switch dictExpr.content {
        case .colon:
            break
        case .elements(let elements):
            // Dictionary with key-value pairs
            for element in elements {
                let keyString = try resolveStringLiteral(element.key)
                let valueString = try resolveStringLiteral(element.value)
                aliases[keyString] = valueString
            }
        }

        return aliases
    }
    
    /// Parse a build setting like .headerSearchPath("path"), .define("NAME"), .linkedLibrary("lib"), etc.
    fileprivate func parseBuildSetting(_ expr: ExprSyntax, tool: TargetBuildSettingDescription.Tool) throws(ResolutionError) -> TargetBuildSettingDescription.Setting {
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil,
              let methodName = memberAccess.declName.baseName.identifier?.name else {
            throw .unhandledExpression(expr)
        }

        var kind: TargetBuildSettingDescription.Kind?
        var condition: PackageConditionDescription?

        // Parse the kind based on method name
        switch methodName {
        case "headerSearchPath":
            for argument in functionCall.arguments {
                switch argument.label?.text {
                case nil where kind == nil:
                    kind = .headerSearchPath(try resolveStringLiteral(argument.expression))
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "headerSearchPath"))
                }
            }
        case "define":
            // .define("NAME") or .define("NAME", to: "VALUE")
            var name: String?
            var value: String?

            for argument in functionCall.arguments {
                switch argument.label?.text {
                case nil where name == nil:
                    resolve(argument.expression, description: "define", into: &name)
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                case "to":
                    resolve(argument.expression, description: "'to' value of 'define'", into: &value)
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "define"))
                }
            }

            if let name {
                if let value {
                    kind = .define("\(name)=\(value)")
                } else {
                    kind = .define(name)
                }
            }
        case "linkedLibrary":
            for argument in functionCall.arguments {
                switch argument.label?.text {
                case nil where kind == nil:
                    kind = .linkedLibrary(try resolveStringLiteral(argument.expression))

                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "linkedLibrary"))
                }
            }
        case "linkedFramework":
            for argument in functionCall.arguments {
                switch argument.label?.text {
                case nil where kind == nil:
                    kind = .linkedFramework(try resolveStringLiteral(argument.expression))
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "linkedFramework"))
                }
            }
        case "unsafeFlags":
            for argument in functionCall.arguments {
                switch argument.label?.text {
                case nil where kind == nil:
                    kind = .unsafeFlags(try resolveArray(argument.expression) { expr throws(ResolutionError) in
                        try resolveStringLiteral(expr)
                    })
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "unsafeFlags"))
                }
            }
        case "enableUpcomingFeature":
            for argument in functionCall.arguments {
                switch argument.label?.text {
                case nil where kind == nil:
                    kind = .enableUpcomingFeature(try resolveStringLiteral(argument.expression))
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "enableUpcomingFeature"))
                }
            }
        case "enableExperimentalFeature":
            for argument in functionCall.arguments {
                switch argument.label?.text {
                case nil where kind == nil:
                    kind = .enableExperimentalFeature(try resolveStringLiteral(argument.expression))
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "enableExperimentalFeature"))
                }
            }
        case "interoperabilityMode":
            // .interoperabilityMode(.C) or .interoperabilityMode(.Cxx)
            for argument in functionCall.arguments {
                let label = argument.label?.text
                switch label {
                case nil where kind == nil:
                    guard let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                          memberAccess.base == nil,
                          let modeName = memberAccess.declName.baseName.identifier?.name else {
                        limitations.append(.unsupportedArgument(argument, callee: "interoperabilityMode"))
                        continue
                    }

                    switch modeName {
                    case "C":
                        kind = .interoperabilityMode(.C)
                    case "Cxx":
                        kind = .interoperabilityMode(.Cxx)
                    default:
                        limitations.append(.unsupportedExpression(argument.expression, expected: "known interoperability mode"))
                    }
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "interoperabilityMode"))
                }
            }
        case "strictMemorySafety":
            kind = .strictMemorySafety
            for argument in functionCall.arguments {
                switch argument.label?.text {
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "strictMemorySafety"))
                }
            }
        case "swiftLanguageMode", "swiftLanguageVersion":
            // .swiftLanguageMode(.v5) or .swiftLanguageMode(.version("6"))
            // Also supports deprecated .swiftLanguageVersion() for backward compatibility
            for argument in functionCall.arguments {
                switch argument.label?.text {
                case nil where kind == nil:
                    if let version = parseSwiftLanguageVersion(argument.expression) {
                        kind = .swiftLanguageMode(version)
                    } else {
                        resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                    }
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: methodName))
                }
            }
        case "treatAllWarnings":
            // .treatAllWarnings(.warning) or .treatAllWarnings(.error)
            var warningLevel: TargetBuildSettingDescription.WarningLevel?
            for argument in functionCall.arguments {
                switch argument.label?.text {
                case "as":
                    resolve(argument.expression, description: "warning level", into: &warningLevel)
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "treatAllWarnings"))
                }
            }
            if let warningLevel {
                kind = .treatAllWarnings(warningLevel)
            }
        case "treatWarning":
            // .treatWarning("deprecated", as: .error)
            var warningName: String?
            var level: TargetBuildSettingDescription.WarningLevel?

            for argument in functionCall.arguments {
                let label = argument.label?.text
                switch label {
                case nil where warningName == nil:
                    resolve(argument.expression, description: "warning name", into: &warningName)
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                case "as":
                    resolve(argument.expression, description: "warning level", into: &level)
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "treatWarning"))
                }
            }

            if let warning = warningName, let warningLevel = level {
                kind = .treatWarning(warning, warningLevel)
            }
        case "enableWarning":
            for argument in functionCall.arguments {
                let label = argument.label?.text
                switch label {
                case nil where kind == nil:
                    kind = .enableWarning(try resolveStringLiteral(argument.expression))
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "enableWarning"))
                }
            }
        case "disableWarning":
            for argument in functionCall.arguments {
                let label = argument.label?.text
                switch label {
                case nil where kind == nil:
                    kind = .disableWarning(try resolveStringLiteral(argument.expression))
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "disableWarning"))
                }
            }
        case "defaultIsolation":
            // .defaultIsolation(MainActor.self) → .MainActor isolation
            // .defaultIsolation(nil)            → nonisolated (compiler default)
            for argument in functionCall.arguments {
                let label = argument.label?.text
                switch label {
                case nil where kind == nil && argument.expression.is(NilLiteralExprSyntax.self):
                    kind = .defaultIsolation(.nonisolated)
                case nil where kind == nil:
                    if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                       let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
                       base.baseName.text == "MainActor",
                       memberAccess.declName.baseName.text == "self" {
                        kind = .defaultIsolation(.MainActor)
                    } else {
                        limitations.append(.unsupportedArgument(argument, callee: "defaultIsolation"))
                    }
                case nil:
                    resolve(argument.expression, description: "build setting condition", into: &condition) { expr throws(ResolutionError) in try parsePackageCondition(expr) }
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "defaultIsolation"))
                }
            }
        default:
            limitations.append(.unsupportedExpression(expr, expected: "known build setting type"))
            throw .unhandledExpression(expr)
        }

        guard let settingKind = kind else {
            throw .missingValue(expr, description: "valid build setting")
        }

        return TargetBuildSettingDescription.Setting(tool: tool, kind: settingKind, condition: condition)
    }
    
    /// Parse a Swift language version like .v5, .v6, or .version("5")
    private func parseSwiftLanguageVersion(_ expr: ExprSyntax?) -> SwiftLanguageVersion? {
        guard let expr = expr else { return nil }
        
        // Case 1: Member access like .v5, .v6
        if let memberAccess = expr.as(MemberAccessExprSyntax.self),
           memberAccess.base == nil,
           let versionName = memberAccess.declName.baseName.identifier?.name {
            let versionString: String
            switch versionName {
            case "v3": versionString = "3"
            case "v4": versionString = "4"
            case "v4_2": versionString = "4.2"
            case "v5": versionString = "5"
            case "v6": versionString = "6"
            default: return nil
            }
            return SwiftLanguageVersion(string: versionString)
        }
        
        // Case 2: Function call like .version("5")
        if let functionCall = expr.as(FunctionCallExprSyntax.self),
           let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.base == nil,
           let methodName = memberAccess.declName.baseName.identifier?.name,
           methodName == "version",
           let firstArg = functionCall.arguments.first,
           firstArg.label == nil,
           let versionString = firstArg.expression.asStringLiteralValue() {
            return SwiftLanguageVersion(string: versionString)
        }
        
        return nil
    }
    
    /// Parse a system package provider like .brew(["openssl"]) or .apt(["openssl", "libssl-dev"])
    fileprivate func parseSystemPackageProvider(_ expr: ExprSyntax) throws(ResolutionError) -> SystemPackageProviderDescription {
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil, // Leading dot syntax
              let methodName = memberAccess.declName.baseName.identifier?.name else {
            throw .unhandledExpression(expr)
        }

        // Parse arguments
        var packages: [String]?
        for argument in functionCall.arguments {
            let label = argument.label?.text
            if label == nil {
                resolve(argument.expression, description: "array of package names", into: &packages)
            } else {
                limitations.append(.unsupportedArgument(argument, callee: methodName))
            }
        }

        switch methodName {
        case "brew":
            return .brew(packages ?? [])
        case "apt":
            return .apt(packages ?? [])
        case "yum":
            return .yum(packages ?? [])
        case "nuget":
            return .nuget(packages ?? [])
        case "pkg":
            return .pkg(packages ?? [])
        default:
            throw .unhandledExpression(expr)
        }
    }
    
    /// Parse a resource declaration like .copy("foo.txt") or .process("bar.txt", localization: .default)
    fileprivate func parseResource(_ expr: ExprSyntax) throws(ResolutionError) -> TargetDescription.Resource {
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            throw .unhandledExpression(expr)
        }

        // Parse the path argument (first unlabeled argument)
        guard let firstArg = arguments.first,
              firstArg.label == nil else {
            throw .missingValue(expr, description: "resource with path")
        }
        let path = try resolveStringLiteral(firstArg.expression)

        // Determine the rule based on method name
        let rule: TargetDescription.Resource.Rule
        switch methodName {
        case "copy":
            for argument in arguments.dropFirst() {
                limitations.append(.unsupportedArgument(argument, callee: methodName))
            }
            rule = .copy
        case "process":
            // Check for localization argument
            var localization: TargetDescription.Resource.Localization? = nil
            for argument in arguments.dropFirst() {
                if argument.label?.text == "localization" {
                    guard let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                          memberAccess.base == nil,
                          let localizationName = memberAccess.declName.baseName.identifier?.name else {
                        limitations.append(.unsupportedExpression(argument.expression, expected: "known localization type"))
                        throw .unhandledExpression(argument.expression)
                    }
                    switch localizationName {
                    case "default":
                        localization = .default
                    case "base":
                        localization = .base
                    default:
                        limitations.append(.unsupportedExpression(argument.expression, expected: "known localization type"))
                        throw .unhandledExpression(argument.expression)
                    }
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: methodName))
                }
            }
            rule = .process(localization: localization)
        case "embedInCode":
            for argument in arguments.dropFirst() {
                limitations.append(.unsupportedArgument(argument, callee: methodName))
            }
            rule = .embedInCode
        default:
            throw .unhandledExpression(expr)
        }

        let normalizedPath = (try? RelativePath(validating: path))?.pathString ?? path
        return TargetDescription.Resource(rule: rule, path: normalizedPath)
    }
    
    /// Parse a plugin capability like .buildTool() or .command(intent: .custom(verb: "foo", description: "bar"))
    fileprivate func parsePluginCapability(_ expr: ExprSyntax) throws(ResolutionError) -> TargetDescription.PluginCapability {
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            throw .unhandledExpression(expr)
        }

        switch methodName {
        case "buildTool":
            for argument in arguments {
                limitations.append(.unsupportedArgument(argument, callee: "buildTool"))
            }
            return .buildTool
        case "command":
            // Parse .command(intent: ..., permissions: [...])
            var intent: TargetDescription.PluginCommandIntent?
            var permissions: [TargetDescription.PluginPermission] = []

            for argument in arguments {
                switch argument.label?.text {
                case "intent":
                    resolve(argument.expression, description: "plugin command intent", into: &intent)
                case "permissions":
                    resolve(argument.expression, description: "array of plugin permissions", appendingInto: &permissions)
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "command"))
                }
            }

            guard let commandIntent = intent else {
                throw .missingValue(expr, description: "command capability with intent")
            }
            return .command(intent: commandIntent, permissions: permissions)
        default:
            throw .unhandledExpression(expr)
        }
    }
    
    /// Parse a plugin command intent like .documentationGeneration or .custom(verb: "foo", description: "bar")
    fileprivate func parsePluginCommandIntent(_ expr: ExprSyntax) throws(ResolutionError) -> TargetDescription.PluginCommandIntent {
        // Handle .documentationGeneration or .sourceCodeFormatting (without parens)
        if let intentName = expr.asEnumMember() {
            switch intentName {
            case "documentationGeneration":
                return .documentationGeneration
            case "sourceCodeFormatting":
                return .sourceCodeFormatting
            default:
                break
            }
        }

        // Handle .documentationGeneration(), .sourceCodeFormatting(), or .custom(verb:description:) (with parens)
        if let (methodName, arguments) = expr.asMemberAccessCall() {
            switch methodName {
            case "custom":
                var verb: String?
                var description: String?

                for argument in arguments {
                    switch argument.label?.text {
                    case "verb":
                        resolve(argument.expression, description: "plugin command verb", into: &verb)
                    case "description":
                        resolve(argument.expression, description: "plugin command description", into: &description)
                    default:
                        limitations.append(.unsupportedArgument(argument, callee: "custom"))
                    }
                }

                if let verb, let description {
                    return .custom(verb: verb, description: description)
                }
            default:
                break
            }
        }

        throw .unhandledExpression(expr)
    }
    
    /// Parse a plugin permission like .writeToPackageDirectory(reason: "...")
    fileprivate func parsePluginPermission(_ expr: ExprSyntax) throws(ResolutionError) -> TargetDescription.PluginPermission {
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            throw .unhandledExpression(expr)
        }

        switch methodName {
        case "writeToPackageDirectory":
            var reason: String?
            for argument in arguments {
                switch argument.label?.text {
                case "reason":
                    resolve(argument.expression, description: "writeToPackageDirectory reason", into: &reason)
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "writeToPackageDirectory"))
                }
            }
            guard let reason else {
                throw .missingValue(expr, description: "writeToPackageDirectory with reason")
            }
            return .writeToPackageDirectory(reason: reason)
        case "allowNetworkConnections":
            // Parse .allowNetworkConnections(scope: ..., reason: "...")
            var scope: TargetDescription.PluginNetworkPermissionScope?
            var reason: String?

            for argument in arguments {
                switch argument.label?.text {
                case "scope":
                    resolve(argument.expression, description: "plugin network permission scope", into: &scope)
                case "reason":
                    resolve(argument.expression, description: "plugin permission reason", into: &reason)
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "allowNetworkConnections"))
                }
            }

            guard let scope, let reason else {
                throw .missingValue(expr, description: "allowNetworkConnections with scope and reason")
            }
            return .allowNetworkConnections(scope: scope, reason: reason)
        default:
            throw .unhandledExpression(expr)
        }
    }
    
    /// Parse a plugin network permission scope like .none, .local(ports: [8080]), .all(ports: []), .docker, .unixDomainSocket
    fileprivate func parsePluginNetworkPermissionScope(_ expr: ExprSyntax) throws(ResolutionError) -> TargetDescription.PluginNetworkPermissionScope {
        // Simple cases: .none, .docker, .unixDomainSocket
        if let memberAccess = expr.as(MemberAccessExprSyntax.self),
           memberAccess.base == nil,
           let scopeName = memberAccess.declName.baseName.identifier?.name {
            switch scopeName {
            case "none":
                return TargetDescription.PluginNetworkPermissionScope.none
            case "docker":
                return .docker
            case "unixDomainSocket":
                return .unixDomainSocket
            default:
                break
            }
        }

        // Cases with ports: .local(ports: [...]), .all(ports: [...])
        if let functionCall = expr.as(FunctionCallExprSyntax.self),
           let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.base == nil,
           let scopeName = memberAccess.declName.baseName.identifier?.name {
            var ports: [Int] = []

            for argument in functionCall.arguments {
                if argument.label?.text == "ports",
                   let portsArray = argument.expression.asIntegerArray() {
                    ports = portsArray
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: scopeName))
                }
            }

            switch scopeName {
            case "local":
                return .local(ports: ports)
            case "all":
                return .all(ports: ports)
            default:
                throw .unhandledExpression(expr)
            }
        }

        throw .unhandledExpression(expr)
    }
    
    /// Parse a plugin usage like "PluginName", .plugin(name: "MyPlugin"), or .plugin(name: "MyPlugin", package: "MyPackage")
    fileprivate func parsePluginUsage(_ expr: ExprSyntax) throws(ResolutionError) -> TargetDescription.PluginUsage {
        // Case 1: .plugin(name: "...", package: "...") or .plugin(name: "...")
        if let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil, // Leading dot syntax
              memberAccess.declName.baseName.text == "plugin" {
            var name: String?
            var package: String?

            for argument in functionCall.arguments {
                switch argument.label?.text {
                case "name":
                    resolve(argument.expression, description: "plugin name", into: &name)
                case "package":
                    resolve(argument.expression, description: "plugin package", into: &package)
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "plugin"))
                }
            }

            guard let pluginName = name else {
                throw .missingValue(expr, description: "plugin usage with name")
            }

            return .plugin(name: pluginName, package: package)
        }

        // Case 2: String literal (e.g., "PluginName" - refers to plugin in same package)
        let pluginName = try resolveStringLiteral(expr)
        return .plugin(name: pluginName, package: nil)
    }
    
    /// Parse a product declaration like .executable(name: "tool", targets: ["tool"])
    fileprivate func parseProduct(_ expr: ExprSyntax) throws(ResolutionError) -> ProductDescription {
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            throw .unhandledExpression(expr)
        }

        // Parse product arguments
        var name: String?
        var targets: [String]?
        var productType: ProductType?
        var settings: [ProductSetting] = []

        #if ENABLE_APPLE_PRODUCT_TYPES
        // For iOSApplication products, we collect settings from individual parameters
        var bundleIdentifier: String?
        var teamIdentifier: String?
        var displayVersion: String?
        var bundleVersion: String?
        var appIcon: ProductSetting.IOSAppInfo.AppIcon?
        var accentColor: ProductSetting.IOSAppInfo.AccentColor?
        var supportedDeviceFamilies: [ProductSetting.IOSAppInfo.DeviceFamily] = []
        var supportedInterfaceOrientations: [ProductSetting.IOSAppInfo.InterfaceOrientation] = []
        var capabilities: [ProductSetting.IOSAppInfo.Capability] = []
        var appCategory: ProductSetting.IOSAppInfo.AppCategory?
        var additionalInfoPlistContentFilePath: String?
        #endif

        for argument in arguments {
            let label = argument.label?.text

            switch label {
            case "name":
                resolve(argument.expression, description: "product name", into: &name)

            case "targets":
                resolve(argument.expression, description: "product targets", into: &targets)

            case "type":
                // Parse library type like .dynamic or .static
                if let typeName = argument.expression.asEnumMember() {
                    switch typeName {
                    case "dynamic":
                        productType = .library(.dynamic)
                    case "static":
                        productType = .library(.static)
                    default:
                        limitations.append(.unsupportedExpression(argument.expression, expected: "known library type"))
                    }
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "known library type"))
                }

            default:
                // For Apple product types, additional labels are handled below.
                // On non-Apple builds any unrecognized label is a limitation.
                #if ENABLE_APPLE_PRODUCT_TYPES
                switch label {
                case "bundleIdentifier":
                    resolve(argument.expression, description: "product bundle identifier", into: &bundleIdentifier)
                case "teamIdentifier":
                    resolve(argument.expression, description: "product team identifier", into: &teamIdentifier)
                case "displayVersion":
                    resolve(argument.expression, description: "product display version", into: &displayVersion)
                case "bundleVersion":
                    resolve(argument.expression, description: "product bundle version", into: &bundleVersion)
                case "appIcon":
                    resolve(argument.expression, description: "app icon", into: &appIcon)
                case "accentColor":
                    resolve(argument.expression, description: "accent color", into: &accentColor)
                case "supportedDeviceFamilies":
                    resolve(argument.expression, description: "supported device families", appendingInto: &supportedDeviceFamilies)
                case "supportedInterfaceOrientations":
                    resolve(argument.expression, description: "supported interface orientations", appendingInto: &supportedInterfaceOrientations)
                case "capabilities":
                    resolve(argument.expression, description: "capabilities", appendingInto: &capabilities)
                case "appCategory":
                    resolve(argument.expression, description: "app category", into: &appCategory)
                case "additionalInfoPlistContentFilePath":
                    resolve(argument.expression, description: "additional info plist path", into: &additionalInfoPlistContentFilePath)
                default:
                    limitations.append(.unsupportedArgument(argument, callee: methodName))
                }
                #else
                limitations.append(.unsupportedArgument(argument, callee: methodName))
                #endif
            }
        }

        guard let productName = name else {
            throw .missingValue(expr, description: "product with name")
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
        #if ENABLE_APPLE_PRODUCT_TYPES
        case "iOSApplication":
            finalProductType = .executable

            // Build product settings from parsed iOS app configuration
            if let bundleIdentifier = bundleIdentifier {
                settings.append(.bundleIdentifier(bundleIdentifier))
            }
            if let teamIdentifier = teamIdentifier {
                settings.append(.teamIdentifier(teamIdentifier))
            }
            if let displayVersion = displayVersion {
                settings.append(.displayVersion(displayVersion))
            }
            if let bundleVersion = bundleVersion {
                settings.append(.bundleVersion(bundleVersion))
            }
            
            // Create IOSAppInfo setting if we have any iOS-specific configuration
            let appInfo = ProductSetting.IOSAppInfo(
                appIcon: appIcon,
                accentColor: accentColor,
                supportedDeviceFamilies: supportedDeviceFamilies,
                supportedInterfaceOrientations: supportedInterfaceOrientations,
                capabilities: capabilities,
                appCategory: appCategory,
                additionalInfoPlistContentFilePath: additionalInfoPlistContentFilePath
            )
            settings.append(.iOSAppInfo(appInfo))
        #endif
        default:
            limitations.append(.unsupportedExpression(expr, expected: "known product type"))
            throw .unhandledExpression(expr)
        }

        do {
            return try ProductDescription(
                name: productName,
                type: finalProductType,
                targets: targets ?? [],
                settings: settings
            )
        } catch {
            limitations.append(.unsupportedExpression(expr, expected: "valid product configuration"))
            throw .unhandledExpression(expr)
        }
    }

    /// Parse a warning level like .warning or .error
    fileprivate func parseWarningLevel(_ expr: ExprSyntax) throws(ResolutionError) -> TargetBuildSettingDescription.WarningLevel {
        guard let name = expr.asEnumMember() else {
            throw .unhandledExpression(expr)
        }

        switch name {
        case "warning": return .warning
        case "error": return .error
        default: throw .unhandledExpression(expr)
        }
    }

    /// Parse C language standard like .iso9899_199409
    fileprivate func parseCLanguageStandard(_ expr: ExprSyntax) throws(ResolutionError) -> String {
        guard let standardName = expr.asEnumMember() else {
            throw .unhandledExpression(expr)
        }

        // Map enum case names (as written in Package.swift) to their string representations.
        // These must stay in sync with Serialization.CLanguageStandard in
        // PackageDescriptionSerialization.swift.
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
        case "c18": return "c18"
        case "iso9899_2017": return "iso9899:2017"
        case "iso9899_2018": return "iso9899:2018"
        case "gnu17": return "gnu17"
        case "gnu18": return "gnu18"
        case "c2x": return "c2x"
        case "gnu2x": return "gnu2x"
        default:
            throw .unhandledExpression(expr)
        }
    }
    
    /// Parse C++ language standard like .gnucxx14
    fileprivate func parseCxxLanguageStandard(_ expr: ExprSyntax) throws(ResolutionError) -> String {
        guard let standardName = expr.asEnumMember() else {
            throw .unhandledExpression(expr)
        }

        // Map enum case names (as written in Package.swift) to their string representations.
        // These must stay in sync with Serialization.CXXLanguageStandard in
        // PackageDescriptionSerialization.swift.
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
        case "cxx1z": return "c++1z"
        case "gnucxx17": return "gnu++17"
        case "gnucxx1z": return "gnu++1z"
        case "cxx20": return "c++20"
        case "gnucxx20": return "gnu++20"
        case "cxx2b": return "c++2b"
        case "gnucxx2b": return "gnu++2b"
        default:
            throw .unhandledExpression(expr)
        }
    }
    
    #if ENABLE_APPLE_PRODUCT_TYPES
    /// Parse an app icon like .asset("icon") or .placeholder(.appIcon)
    fileprivate func parseAppIcon(_ expr: ExprSyntax) throws(ResolutionError) -> ProductSetting.IOSAppInfo.AppIcon {
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            throw .unhandledExpression(expr)
        }

        switch methodName {
        case "asset":
            guard let firstExpr = arguments.first?.expression else {
                throw .missingValue(expr, description: "app icon asset name")
            }
            let name = try resolveStringLiteral(firstExpr)
            for argument in arguments.dropFirst() {
                limitations.append(.unsupportedArgument(argument, callee: "asset"))
            }
            return .asset(name: name)
        case "placeholder":
            guard let iconArg = arguments.first?.expression,
                  let iconName = iconArg.asEnumMember() else {
                throw .unhandledExpression(expr)
            }
            for argument in arguments.dropFirst() {
                limitations.append(.unsupportedArgument(argument, callee: "placeholder"))
            }
            return .placeholder(icon: .init(rawValue: iconName))
        default:
            throw .unhandledExpression(expr)
        }
    }

    /// Parse an accent color like .asset("color") or .presetColor(.blue)
    fileprivate func parseAccentColor(_ expr: ExprSyntax) throws(ResolutionError) -> ProductSetting.IOSAppInfo.AccentColor {
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            throw .unhandledExpression(expr)
        }

        switch methodName {
        case "asset":
            guard let firstExpr = arguments.first?.expression else {
                throw .missingValue(expr, description: "accent color asset name")
            }
            let name = try resolveStringLiteral(firstExpr)
            for argument in arguments.dropFirst() {
                limitations.append(.unsupportedArgument(argument, callee: "asset"))
            }
            return .asset(name: name)
        case "presetColor":
            guard let colorArg = arguments.first?.expression,
                  let colorName = colorArg.asEnumMember() else {
                throw .unhandledExpression(expr)
            }
            for argument in arguments.dropFirst() {
                limitations.append(.unsupportedArgument(argument, callee: "presetColor"))
            }
            return .presetColor(presetColor: .init(rawValue: colorName))
        default:
            throw .unhandledExpression(expr)
        }
    }

    /// Parse a device family like .pad, .phone, .mac
    fileprivate func parseDeviceFamily(_ expr: ExprSyntax) throws(ResolutionError) -> ProductSetting.IOSAppInfo.DeviceFamily {
        guard let familyName = expr.asEnumMember(),
              let family = ProductSetting.IOSAppInfo.DeviceFamily(rawValue: familyName) else {
            throw .unhandledExpression(expr)
        }
        return family
    }

    /// Parse a single interface orientation like .portrait or .landscapeRight(.when(deviceFamilies: [.mac]))
    fileprivate func parseInterfaceOrientation(_ expr: ExprSyntax) throws(ResolutionError) -> ProductSetting.IOSAppInfo.InterfaceOrientation {
        // Handle simple case: .portrait (no condition)
        if let orientationName = expr.asEnumMember() {
            switch orientationName {
            case "portrait":
                return .portrait(condition: nil)
            case "portraitUpsideDown":
                return .portraitUpsideDown(condition: nil)
            case "landscapeRight":
                return .landscapeRight(condition: nil)
            case "landscapeLeft":
                return .landscapeLeft(condition: nil)
            default:
                throw .unhandledExpression(expr)
            }
        }

        // Handle conditional case: .portrait(.when(deviceFamilies: [.mac]))
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil,
              let orientationName = memberAccess.declName.baseName.identifier?.name else {
            throw .unhandledExpression(expr)
        }

        var condition: ProductSetting.IOSAppInfo.DeviceFamilyCondition?
        if let conditionArg = functionCall.arguments.first?.expression {
            resolve(conditionArg, description: "device family condition", into: &condition)
        }
        for argument in functionCall.arguments.dropFirst() {
            limitations.append(.unsupportedArgument(argument, callee: orientationName))
        }

        switch orientationName {
        case "portrait":
            return .portrait(condition: condition)
        case "portraitUpsideDown":
            return .portraitUpsideDown(condition: condition)
        case "landscapeRight":
            return .landscapeRight(condition: condition)
        case "landscapeLeft":
            return .landscapeLeft(condition: condition)
        default:
            throw .unhandledExpression(expr)
        }
    }

    /// Parse a device family condition like .when(deviceFamilies: [.mac])
    fileprivate func parseDeviceFamilyCondition(_ expr: ExprSyntax) throws(ResolutionError) -> ProductSetting.IOSAppInfo.DeviceFamilyCondition {
        guard let (methodName, arguments) = expr.asMemberAccessCall(),
              methodName == "when" else {
            throw .unhandledExpression(expr)
        }

        var families: [ProductSetting.IOSAppInfo.DeviceFamily]?
        for argument in arguments {
            switch argument.label?.text {
            case "deviceFamilies":
                resolve(argument.expression, description: "device families", into: &families)
            default:
                limitations.append(.unsupportedArgument(argument, callee: "when"))
            }
        }

        return ProductSetting.IOSAppInfo.DeviceFamilyCondition(deviceFamilies: families ?? [])
    }

    /// Parse a single capability
    fileprivate func parseCapability(_ expr: ExprSyntax) throws(ResolutionError) -> ProductSetting.IOSAppInfo.Capability {
        guard let (purpose, arguments) = expr.asMemberAccessCall() else {
            throw .unhandledExpression(expr)
        }

        var purposeString: String?
        var bonjourServiceTypes: [String]?
        var condition: ProductSetting.IOSAppInfo.DeviceFamilyCondition?

        for argument in arguments {
            switch argument.label?.text {
            case "purposeString":
                resolve(argument.expression, description: "capability purpose string", into: &purposeString)
            case "bonjourServiceTypes":
                resolve(argument.expression, description: "array of Bonjour service types", into: &bonjourServiceTypes)
            case nil:
                resolve(argument.expression, description: "device family condition", into: &condition)
            default:
                limitations.append(.unsupportedArgument(argument, callee: purpose))
            }
        }

        return ProductSetting.IOSAppInfo.Capability(
            purpose: purpose,
            purposeString: purposeString,
            bonjourServiceTypes: bonjourServiceTypes,
            condition: condition
        )
    }

    /// Parse an app category like .developerTools
    fileprivate func parseAppCategory(_ expr: ExprSyntax) throws(ResolutionError) -> ProductSetting.IOSAppInfo.AppCategory {
        guard let categoryName = expr.asEnumMember() else {
            throw .unhandledExpression(expr)
        }

        // Map the enum name to the raw value format
        let rawValue: String
        switch categoryName {
        case "business":
            rawValue = "public.app-category.business"
        case "developerTools":
            rawValue = "public.app-category.developer-tools"
        case "education":
            rawValue = "public.app-category.education"
        case "entertainment":
            rawValue = "public.app-category.entertainment"
        case "finance":
            rawValue = "public.app-category.finance"
        case "games":
            rawValue = "public.app-category.games"
        case "healthAndFitness":
            rawValue = "public.app-category.healthcare-fitness"
        case "lifestyle":
            rawValue = "public.app-category.lifestyle"
        case "medical":
            rawValue = "public.app-category.medical"
        case "music":
            rawValue = "public.app-category.music"
        case "news":
            rawValue = "public.app-category.news"
        case "photography":
            rawValue = "public.app-category.photography"
        case "productivity":
            rawValue = "public.app-category.productivity"
        case "reference":
            rawValue = "public.app-category.reference"
        case "socialNetworking":
            rawValue = "public.app-category.social-networking"
        case "sports":
            rawValue = "public.app-category.sports"
        case "travel":
            rawValue = "public.app-category.travel"
        case "utilities":
            rawValue = "public.app-category.utilities"
        case "weather":
            rawValue = "public.app-category.weather"
        case "graphics_design":
            rawValue = "public.app-category.graphics-design"
        default:
            rawValue = categoryName
        }

        return ProductSetting.IOSAppInfo.AppCategory(rawValue: rawValue)
    }
    #endif
    
    /// Parse a package dependency like `.package(url: "/foo", from: "1.0.0")` or `.package(url: "/foo", branch: "main")`
    fileprivate func parsePackageDependency(_ expr: ExprSyntax) throws(ResolutionError) -> PackageDependency {
        // Expect a function call like .package(url: "/foo", from: "1.0.0")
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil, // Leading dot syntax
              let methodName = memberAccess.declName.baseName.identifier?.name,
              methodName == "package" else {
            throw .unhandledExpression(expr)
        }

        var name: String?
        var url: String?
        var path: String?  // Filesystem path
        var id: String?  // Registry package ID
        var requirement: PackageDependency.SourceControl.Requirement?
        var registryRequirement: PackageDependency.Registry.Requirement?
        var traits: [PackageDependency.Trait]?

        // Parse arguments
        for argument in functionCall.arguments {
            switch argument.label?.text {
            case "name":
                resolve(argument.expression, description: "dependency name", into: &name)
            case "id":
                resolve(argument.expression, description: "dependency id", into: &id)
            case "url":
                resolve(argument.expression, description: "dependency url", into: &url)
            case "path":
                resolve(argument.expression, description: "dependency path", into: &path)
            case "traits":
                resolve(argument.expression, description: "array of dependency traits", into: &traits)
            case "from":
                if let versionString = argument.expression.asStringLiteralValue(),
                   let version = Version(versionString) {
                    if id != nil {
                        registryRequirement = .range(.upToNextMajor(from: version))
                    } else {
                        requirement = .range(.upToNextMajor(from: version))
                    }
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "version"))
                }
            case "branch":
                var branch: String?
                resolve(argument.expression, description: "branch name", into: &branch)
                if let branch {
                    requirement = .branch(try resolveStringLiteral(argument.expression))
                }
            case "revision":
                var revision: String?
                resolve(argument.expression, description: "revision", into: &revision)
                if let revision {
                    requirement = .revision(revision)
                }
            case "exact":
                if let versionString = argument.expression.asStringLiteralValue(),
                   let version = Version(versionString) {
                    if id != nil {
                        registryRequirement = .exact(version)
                    } else {
                        requirement = .exact(version)
                    }
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "version"))
                }
            case nil:
                // Unlabeled argument could be:
                // 1. A requirement like .upToNextMajor(from: "1.0.0")
                // 2. A range operator expression like "1.0.0"..<"2.0.0"

                // Check for range operators - handle InfixOperatorExprSyntax (after sequence folding)
                if let infixExpr = argument.expression.as(InfixOperatorExprSyntax.self),
                   let op = infixExpr.operator.as(BinaryOperatorExprSyntax.self) {
                    let opText = op.operator.text.trimmingCharacters(in: .whitespaces)

                    if opText == "..<" || opText == "..." {
                        // Parse the left and right operands as version strings
                        if let lowerString = infixExpr.leftOperand.asStringLiteralValue(),
                           let lowerVersion = Version(lowerString),
                           let upperString = infixExpr.rightOperand.asStringLiteralValue(),
                           let upperVersion = Version(upperString) {

                            if opText == "..." {
                                // Closed range - convert to half-open range
                                let upperNext = Version(
                                    upperVersion.major,
                                    upperVersion.minor,
                                    upperVersion.patch + 1,
                                    prereleaseIdentifiers: upperVersion.prereleaseIdentifiers,
                                    buildMetadataIdentifiers: upperVersion.buildMetadataIdentifiers
                                )
                                if id != nil {
                                    registryRequirement = .range(lowerVersion..<upperNext)
                                } else {
                                    requirement = .range(lowerVersion..<upperNext)
                                }
                            } else {
                                // Half-open range
                                if id != nil {
                                    registryRequirement = .range(lowerVersion..<upperVersion)
                                } else {
                                    requirement = .range(lowerVersion..<upperVersion)
                                }
                            }
                        } else {
                            limitations.append(.unsupportedExpression(argument.expression, expected: "version range with string literal bounds"))
                        }
                    } else {
                        limitations.append(.unsupportedExpression(argument.expression, expected: "version range operator (..<  or ...)"))
                    }
                } else if let reqExpr = argument.expression.as(FunctionCallExprSyntax.self),
                   let reqMemberAccess = reqExpr.calledExpression.as(MemberAccessExprSyntax.self),
                   reqMemberAccess.base == nil,
                   let reqName = reqMemberAccess.declName.baseName.identifier?.name {

                    switch reqName {
                    case "upToNextMajor":
                        if let fromArg = reqExpr.arguments.first(where: { $0.label?.text == "from" }),
                           let versionString = fromArg.expression.asStringLiteralValue(),
                           let version = Version(versionString) {
                            if id != nil {
                                registryRequirement = .range(.upToNextMajor(from: version))
                            } else {
                                requirement = .range(.upToNextMajor(from: version))
                            }
                        } else {
                            limitations.append(.unsupportedExpression(argument.expression, expected: "package dependency requirement"))
                        }
                    case "upToNextMinor":
                        if let fromArg = reqExpr.arguments.first(where: { $0.label?.text == "from" }),
                           let versionString = fromArg.expression.asStringLiteralValue(),
                           let version = Version(versionString) {
                            if id != nil {
                                registryRequirement = .range(.upToNextMinor(from: version))
                            } else {
                                requirement = .range(.upToNextMinor(from: version))
                            }
                        } else {
                            limitations.append(.unsupportedExpression(argument.expression, expected: "package dependency requirement"))
                        }
                    case "exact":
                        if let versionString = reqExpr.arguments.first?.expression.asStringLiteralValue(),
                           let version = Version(versionString) {
                            if id != nil {
                                registryRequirement = .exact(version)
                            } else {
                                requirement = .exact(version)
                            }
                        } else {
                            limitations.append(.unsupportedExpression(argument.expression, expected: "package dependency requirement"))
                        }
                    case "branch":
                        if let branch = reqExpr.arguments.first?.expression.asStringLiteralValue() {
                            requirement = .branch(branch)
                        } else {
                            limitations.append(.unsupportedExpression(argument.expression, expected: "package dependency requirement"))
                        }
                    case "revision":
                        if let revision = reqExpr.arguments.first?.expression.asStringLiteralValue() {
                            requirement = .revision(revision)
                        } else {
                            limitations.append(.unsupportedExpression(argument.expression, expected: "package dependency requirement"))
                        }
                    default:
                        limitations.append(.unsupportedExpression(argument.expression, expected: "package dependency requirement"))
                    }
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "package dependency requirement"))
                }
            default:
                limitations.append(.unsupportedArgument(argument, callee: "package"))
            }
        }

        // Handle filesystem dependencies (no version control)
        if let fsPath = path {
            let mappableDep = MappablePackageDependency(
                parentPackagePath: manifestPath.parentDirectory,
                kind: .fileSystem(name: name, path: fsPath),
                productFilter: .everything,
                traits: Set(traits ?? [.init(name: "default")])
            )

            do {
                return try dependencyMapper.mappedDependency(mappableDep, fileSystem: fileSystem)
            } catch {
                limitations.append(.unsupportedExpression(expr, expected: "valid filesystem path: \(error)"))
                throw .unhandledExpression(expr)
            }
        }

        // Handle registry dependencies
        if let packageID = id {
            guard let regReq = registryRequirement else {
                throw .missingValue(expr, description: "registry dependency with requirement")
            }

            let identity = PackageIdentity.plain(packageID)
            return .registry(
                identity: identity,
                requirement: regReq,
                productFilter: .everything,
                traits: Set(traits ?? [.init(name: "default")])
            )
        }

        guard let url, let requirement else {
            throw .missingValue(expr, description: "package dependency with url and requirement")
        }

        // Use the dependency mapper for source control dependencies
        let mappableDep = MappablePackageDependency(
            parentPackagePath: manifestPath.parentDirectory,
            kind: .sourceControl(name: name, location: url, requirement: requirement),
            productFilter: .everything,
            traits: Set(traits ?? [.init(name: "default")])
        )

        do {
            return try dependencyMapper.mappedDependency(mappableDep, fileSystem: fileSystem)
        } catch {
            limitations.append(.unsupportedExpression(expr, expected: "valid source control dependency: \(error)"))
            throw .unhandledExpression(expr)
        }
    }
    
    /// Parse a platform description like `.macOS("10.13.option1.option2")` or `.iOS(.v12)`
    fileprivate func parsePlatform(_ expr: ExprSyntax) throws(ResolutionError) -> PlatformDescription {
        // Expect a function call like .macOS("10.13")
        guard let (platformName, arguments) = expr.asMemberAccessCall() else {
            throw .unhandledExpression(expr)
        }

        // Map platform names (as written in Package.swift) to their canonical form.
        // These must stay in sync with the static properties on Platform in
        // PackageModel/Platform.swift.
        let canonicalName: String
        switch platformName {
        case "macOS": canonicalName = "macos"
        case "iOS": canonicalName = "ios"
        case "tvOS": canonicalName = "tvos"
        case "watchOS": canonicalName = "watchos"
        case "visionOS": canonicalName = "visionos"
        case "macCatalyst": canonicalName = "maccatalyst"
        case "driverKit": canonicalName = "driverkit"
        case "linux": canonicalName = "linux"
        case "windows": canonicalName = "windows"
        case "android": canonicalName = "android"
        case "wasi": canonicalName = "wasi"
        case "openbsd": canonicalName = "openbsd"
        case "freebsd": canonicalName = "freebsd"

        case "custom":
            // .custom("platformName", versionString: "1.0")
            var customName: String?
            var versionString: String?
            for argument in arguments {
                switch argument.label?.text {
                case nil:
                    resolve(argument.expression, description: "custom platform name", into: &customName)
                case "versionString":
                    resolve(argument.expression, description: "custom platform version", into: &versionString)
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "custom"))
                }
            }
            guard let name = customName, let version = versionString else {
                throw .missingValue(expr, description: "custom platform with name and versionString")
            }
            return PlatformDescription(name: name, version: version, options: [])

        default:
            throw .unhandledExpression(expr)
        }

        // Get the version argument and check for unexpected extra arguments
        guard let firstArg = arguments.first else {
            throw .missingValue(expr, description: "platform with version")
        }

        for argument in arguments.dropFirst() {
            limitations.append(.unsupportedArgument(argument, callee: platformName))
        }

        var version: String
        var options: [String] = []

        // Check if it's a member access like .v10_13
        if let memberAccess = firstArg.expression.as(MemberAccessExprSyntax.self),
                memberAccess.base == nil,
                let versionName = memberAccess.declName.baseName.identifier?.name {
            // Parse version from names like "v10_13" or "v12"
            if versionName.hasPrefix("v") {
                let versionPart = String(versionName.dropFirst()) // Remove "v"
                // Replace underscores with dots
                version = versionPart.replacingOccurrences(of: "_", with: ".")

                // Normalize version to have at least major.minor (e.g., "12" -> "12.0")
                if !version.contains(".") {
                    version = version + ".0"
                }
            } else {
                throw .unhandledExpression(firstArg.expression)
            }
        } else {
            // Check if it's a string literal like "10.13.option1.option2"
            let versionString = try resolveStringLiteral(firstArg.expression)
            // Parse version and options from the string
            let components = versionString.split(separator: ".")
            if components.isEmpty {
                throw .missingValue(expr, description: "valid version string")
            }

            // Find where version numbers end and options begin
            var versionComponents: [Substring] = []
            var optionComponents: [String] = []
            var inOptions = false

            for component in components {
                if !inOptions && component.allSatisfy({ $0.isNumber }) {
                    versionComponents.append(component)
                } else {
                    inOptions = true
                    optionComponents.append(String(component))
                }
            }

            version = versionComponents.joined(separator: ".")
            options = optionComponents
        }

        return PlatformDescription(name: canonicalName, version: version, options: options)
    }
    
    /// Parse a trait declaration like "Trait1", Trait(name: "Trait2", description: "..."), or .trait(name: "Trait3", enabledTraits: [...])
    fileprivate func parseTrait(_ expr: ExprSyntax) throws(ResolutionError) -> TraitDescription {
        // Case 1: Trait(name: "...", description: "...", enabledTraits: [...]) or .trait(...) or .default(...)
        if let functionCall = expr.as(FunctionCallExprSyntax.self) {
            // Check if it's Trait(...), .trait(...), or .default(...)
            let methodName: String?
            if let identifierExpr = functionCall.calledExpression.as(DeclReferenceExprSyntax.self),
               identifierExpr.baseName.text == "Trait" {
                methodName = "trait"
            } else if let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
                      memberAccess.base == nil {
                methodName = memberAccess.declName.baseName.text
            } else {
                methodName = nil
            }

            guard let method = methodName, (method == "trait" || method == "default") else {
                throw .unhandledExpression(expr)
            }

            // Handle .default(enabledTraits: [...])
            if method == "default" {
                var enabledTraits: [String]?

                for argument in functionCall.arguments {
                    if argument.label?.text == "enabledTraits" {
                        resolve(argument.expression, description: "array of enabled trait names", into: &enabledTraits)
                    } else {
                        limitations.append(.unsupportedArgument(argument, callee: "default"))
                    }
                }

                return TraitDescription(
                    name: "default",
                    description: "The default traits of this package.",
                    enabledTraits: Set(enabledTraits ?? [])
                )
            }

            // Handle .trait(...) or Trait(...)
            var name: String?
            var description: String?
            var enabledTraits: [String]?

            for argument in functionCall.arguments {
                let label = argument.label?.text
                if label == "name" {
                    resolve(argument.expression, description: "trait name", into: &name)
                } else if label == "description" {
                    resolve(argument.expression, description: "trait description", into: &description)
                } else if label == "enabledTraits" {
                    resolve(argument.expression, description: "array of enabled trait names", into: &enabledTraits)
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "trait"))
                }
            }

            guard let traitName = name else {
                throw .missingValue(expr, description: "trait with name")
            }

            return TraitDescription(name: traitName, description: description, enabledTraits: Set(enabledTraits ?? []))
        }

        // Case 2: String literal "TraitName"
        let traitName = try resolveStringLiteral(expr)
        return TraitDescription(name: traitName)
    }

    /// Parse a single dependency trait like "FooTrait1", .trait(name: "...", condition: ...), or .defaults
    fileprivate func parseDependencyTrait(_ expr: ExprSyntax) throws(ResolutionError) -> PackageDependency.Trait {
        // Case 1: .defaults
        if let memberAccess = expr.as(MemberAccessExprSyntax.self),
           memberAccess.base == nil,
           memberAccess.declName.baseName.text == "defaults" {
            return PackageDependency.Trait(name: "default")
        }

        // Case 2: .trait(name: "...", condition: ...) or Package.Dependency.Trait(name: "...", condition: ...)
        if let functionCall = expr.as(FunctionCallExprSyntax.self) {
            // Check if it's .trait(...) or Package.Dependency.Trait(...)
            let isValidCall: Bool
            if let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
               memberAccess.base == nil,
               memberAccess.declName.baseName.text == "trait" {
                isValidCall = true
            } else if let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
                      let baseAccess = memberAccess.base?.as(MemberAccessExprSyntax.self),
                      memberAccess.declName.baseName.text == "Trait" {
                // Package.Dependency.Trait(...)
                isValidCall = true
                _ = baseAccess
            } else {
                isValidCall = false
            }

            guard isValidCall else {
                throw .unhandledExpression(expr)
            }

            var name: String?
            var condition: PackageDependency.Trait.Condition?

            for argument in functionCall.arguments {
                switch argument.label?.text {
                case "name":
                    resolve(argument.expression, description: "dependency trait name", into: &name)
                case "condition":
                    resolve(argument.expression, description: "dependency trait condition", into: &condition)
                default:
                    limitations.append(.unsupportedArgument(argument, callee: "trait"))
                }
            }

            guard let traitName = name else {
                throw .missingValue(expr, description: "dependency trait with name")
            }

            return PackageDependency.Trait(name: traitName, condition: condition)
        }

        // Case 3: String literal "TraitName"
        let traitName = try resolveStringLiteral(expr)
        return PackageDependency.Trait(name: traitName)
    }

    /// Parse a dependency trait condition like .when(traits: ["Trait1"])
    fileprivate func parseDependencyTraitCondition(_ expr: ExprSyntax) throws(ResolutionError) -> PackageDependency.Trait.Condition {
        guard let (methodName, arguments) = expr.asMemberAccessCall(),
              methodName == "when" else {
            throw .unhandledExpression(expr)
        }

        var traits: [String]?

        for argument in arguments {
            switch argument.label?.text {
            case "traits":
                resolve(argument.expression, description: "array of trait names", into: &traits)
            default:
                limitations.append(.unsupportedArgument(argument, callee: "when"))
            }
        }

        return PackageDependency.Trait.Condition(traits: traits.map { Set($0) })
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
              (bindingSpecifier.tokenKind == .keyword(.let) ||
               bindingSpecifier.tokenKind == .keyword(.var)),
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
        guard let stringLiteral = self.as(StringLiteralExprSyntax.self) else {
            return nil
        }

        return stringLiteral.representedLiteralValue
    }

    /// Extract the boolean literal value from the expression, if it is one.
    fileprivate func asBooleanLiteralValue() -> Bool? {
        guard let boolLiteral = self.as(BooleanLiteralExprSyntax.self) else {
            return nil
        }

        return boolLiteral.literal.tokenKind == .keyword(.true)
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

    /// Extract a member access function call (e.g., `.target(name: "foo")`)
    /// Returns the method name and arguments if successful.
    fileprivate func asMemberAccessCall() -> (methodName: String, arguments: LabeledExprListSyntax)? {
        guard let functionCall = self.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil,  // Leading dot syntax
              let methodName = memberAccess.declName.baseName.identifier?.name else {
            return nil
        }
        return (methodName, functionCall.arguments)
    }

    /// Parse an enum member access (e.g., `.static`, `.dynamic`).
    /// Returns the member name if it's a simple member access with no base.
    fileprivate func asEnumMember() -> String? {
        guard let memberAccess = self.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil,  // Leading dot syntax
              let memberName = memberAccess.declName.baseName.identifier?.name else {
            return nil
        }
        return memberName
    }
}

/// A version of ContextModel that stores everything directly, rather than
/// falling back to the current process's environment.
class StaticContextModel {
    let packageDirectory : String
    var environment: [String : String]

    init(packageDirectory: String, environment: [String : String]) {
        self.packageDirectory = packageDirectory
        self.environment = environment
    }

    lazy var gitInformation: ContextModel.GitInformation? = {
        do {
            let repo = GitRepository(path: try AbsolutePath(validating: packageDirectory))
            return ContextModel.GitInformation(
                currentTag: repo.getCurrentTag(),
                currentCommit: try repo.getCurrentRevision().identifier,
                hasUncommittedChanges: repo.hasUncommittedChanges()
            )
        } catch {
            // Ignore errors getting git info
            return nil
        }
    }()
}

// MARK: Resolution of types in a package manifest.

fileprivate protocol ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws (ManifestParseVisitor.ResolutionError)-> Self
}

extension String: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> String {
        try visitor.resolveStringLiteral(expr)
    }
}

extension Array: ParsingResolvable where Element: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> [Element] {
        try visitor.resolveArray(expr) { expr throws(ManifestParseVisitor.ResolutionError) in
            try Element.resolve(expr, in: visitor)
        }
    }
}

extension ProductDescription: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> ProductDescription {
        try visitor.parseProduct(expr)
    }
}

extension TargetDescription: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> TargetDescription {
        try visitor.parseTarget(expr)
    }
}

extension TargetDescription.Dependency: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> TargetDescription.Dependency {
        try visitor.parseTargetDependency(expr)
    }
}

extension TargetDescription.Resource: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> TargetDescription.Resource {
        try visitor.parseResource(expr)
    }
}

extension TargetDescription.PluginCapability: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> TargetDescription.PluginCapability {
        try visitor.parsePluginCapability(expr)
    }
}

extension TargetDescription.PluginUsage: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> TargetDescription.PluginUsage {
        try visitor.parsePluginUsage(expr)
    }
}

extension TargetDescription.PluginPermission: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> TargetDescription.PluginPermission {
        try visitor.parsePluginPermission(expr)
    }
}

extension TargetDescription.PluginCommandIntent: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> TargetDescription.PluginCommandIntent {
        try visitor.parsePluginCommandIntent(expr)
    }
}

extension TargetDescription.PluginNetworkPermissionScope: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> TargetDescription.PluginNetworkPermissionScope {
        try visitor.parsePluginNetworkPermissionScope(expr)
    }
}

extension PlatformDescription: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> PlatformDescription {
        try visitor.parsePlatform(expr)
    }
}

extension TraitDescription: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> TraitDescription {
        try visitor.parseTrait(expr)
    }
}

extension PackageDependency: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> PackageDependency {
        try visitor.parsePackageDependency(expr)
    }
}

extension PackageDependency.Trait: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> PackageDependency.Trait {
        try visitor.parseDependencyTrait(expr)
    }
}

extension PackageDependency.Trait.Condition: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> PackageDependency.Trait.Condition {
        try visitor.parseDependencyTraitCondition(expr)
    }
}

extension SystemPackageProviderDescription: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> SystemPackageProviderDescription {
        try visitor.parseSystemPackageProvider(expr)
    }
}



extension TargetBuildSettingDescription.WarningLevel: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> TargetBuildSettingDescription.WarningLevel {
        try visitor.parseWarningLevel(expr)
    }
}

#if ENABLE_APPLE_PRODUCT_TYPES
extension ProductSetting.IOSAppInfo.AppIcon: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> ProductSetting.IOSAppInfo.AppIcon {
        try visitor.parseAppIcon(expr)
    }
}

extension ProductSetting.IOSAppInfo.AccentColor: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> ProductSetting.IOSAppInfo.AccentColor {
        try visitor.parseAccentColor(expr)
    }
}

extension ProductSetting.IOSAppInfo.DeviceFamily: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> ProductSetting.IOSAppInfo.DeviceFamily {
        try visitor.parseDeviceFamily(expr)
    }
}

extension ProductSetting.IOSAppInfo.InterfaceOrientation: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> ProductSetting.IOSAppInfo.InterfaceOrientation {
        try visitor.parseInterfaceOrientation(expr)
    }
}

extension ProductSetting.IOSAppInfo.DeviceFamilyCondition: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> ProductSetting.IOSAppInfo.DeviceFamilyCondition {
        try visitor.parseDeviceFamilyCondition(expr)
    }
}

extension ProductSetting.IOSAppInfo.Capability: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> ProductSetting.IOSAppInfo.Capability {
        try visitor.parseCapability(expr)
    }
}

extension ProductSetting.IOSAppInfo.AppCategory: ParsingResolvable {
    static func resolve(_ expr: ExprSyntax, in visitor: ManifestParseVisitor) throws(ManifestParseVisitor.ResolutionError) -> ProductSetting.IOSAppInfo.AppCategory {
        try visitor.parseAppCategory(expr)
    }
}
#endif

#endif
