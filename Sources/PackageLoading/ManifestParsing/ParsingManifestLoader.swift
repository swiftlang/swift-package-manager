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
    let config: StaticBuildConfiguration
    let environment: [String: String]?

    /// Initialize the manifest loader with the given static build
    /// configuration, which will be used to evaluate `#if` conditions in
    /// the manifest.
    public init(
        configuration: StaticBuildConfiguration,
        pruneDependencies: Bool = false,
        environment: [String: String]?
    ) {
        self.pruneDependencies = pruneDependencies
        self.config = configuration
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
        self.init(
            configuration: try StaticBuildConfiguration.getHostConfiguration(
                usingSwiftCompiler: toolchain.swiftCompilerPathForManifests,
                extraManifestFlags: extraManifestFlags
            ),
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
        var products = visitor.products
        var targets = visitor.targets
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
            products: products,
            targets: targets,
            traits: Set(visitor.traits),
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
    var traits: [TraitDescription] = []

    /// C++ language standard.
    var cxxLanguageStandard: String?

    /// C language standard.
    var cLanguageStandard: String?

    var defaultPackageAccess: Bool

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
                guard let name = argument.expression.asStringLiteralValue(in: contextModel) else {
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
            
            if argument.label?.text == "dependencies" {
                guard let dependenciesArray = argument.expression.as(ArrayExprSyntax.self) else {
                    limitations.append(
                        .unsupportedExpression(
                            argument.expression,
                            expected: "array of package dependencies"
                        )
                    )
                    continue
                }
                
                for dependencyElement in dependenciesArray.elements {
                    if let dependency = parsePackageDependency(dependencyElement.expression, manifestPath: manifestPath) {
                        self.dependencies.append(dependency)
                    }
                }
                continue
            }

            // Accept both swiftLanguageVersions (deprecated) and swiftLanguageModes (6.0+)
            if argument.label?.text == "swiftLanguageVersions" || argument.label?.text == "swiftLanguageModes" {
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
                if let value = argument.expression.asStringLiteralValue(in: contextModel) {
                    self.pkgConfig = value
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "pkgConfig string"))
                }
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
            
            if argument.label?.text == "platforms" {
                guard let platformsArray = argument.expression.as(ArrayExprSyntax.self) else {
                    limitations.append(
                        .unsupportedExpression(
                            argument.expression,
                            expected: "array of platforms"
                        )
                    )
                    continue
                }
                
                var parsedPlatforms: [PlatformDescription] = []
                for platformElement in platformsArray.elements {
                    if let platform = parsePlatform(platformElement.expression) {
                        parsedPlatforms.append(platform)
                    }
                }
                self.platforms = parsedPlatforms
                continue
            }
            
            if argument.label?.text == "defaultLocalization" {
                if let value = argument.expression.asStringLiteralValue(in: contextModel) {
                    self.defaultLocalization = value
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "default localization language tag"))
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
            
            if argument.label?.text == "traits" {
                guard let traitsArray = argument.expression.as(ArrayExprSyntax.self) else {
                    limitations.append(
                        .unsupportedExpression(
                            argument.expression,
                            expected: "array of traits"
                        )
                    )
                    continue
                }
                
                var parsedTraits: [TraitDescription] = []
                for traitElement in traitsArray.elements {
                    if let trait = parseTrait(traitElement.expression) {
                        parsedTraits.append(trait)
                    }
                }
                self.traits = parsedTraits
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
        var url: String? = nil
        var checksum: String? = nil
        var exclude: [String] = []
        var sources: [String]? = nil
        var resources: [TargetDescription.Resource] = []
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
            
            if label == "name" {
                name = argument.expression.asStringLiteralValue(in: contextModel)
            } else if label == "dependencies" {
                if let deps = argument.expression.parseArrayElements(parseTargetDependency) {
                    dependencies.append(contentsOf: deps)
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of target dependencies"))
                }
            } else if label == "path" {
                if let value = argument.expression.asStringLiteralValue(in: contextModel) {
                    path = value
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "path string"))
                }
            } else if label == "url" {
                if let value = argument.expression.asStringLiteralValue(in: contextModel) {
                    url = value
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "url string"))
                }
            } else if label == "checksum" {
                if let value = argument.expression.asStringLiteralValue() {
                    checksum = value
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "checksum string"))
                }
            } else if label == "exclude" {
                if let value = argument.expression.asStringArray(in: contextModel) {
                    exclude = value
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of excluded paths"))
                }
            } else if label == "sources" {
                if let parsed = argument.expression.asStringArray(in: contextModel) {
                    sources = parsed
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of source file paths"))
                }
            } else if label == "publicHeadersPath" {
                if let value = argument.expression.asStringLiteralValue(in: contextModel) {
                    publicHeadersPath = value
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "publicHeadersPath string"))
                }
            } else if label == "pkgConfig" {
                if let value = argument.expression.asStringLiteralValue() {
                    pkgConfig = value
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "pkgConfig string"))
                }
            } else if label == "providers" {
                if let providersArray = argument.expression.as(ArrayExprSyntax.self) {
                    var parsedProviders: [SystemPackageProviderDescription] = []
                    for providerElement in providersArray.elements {
                        if let provider = parseSystemPackageProvider(providerElement.expression) {
                            parsedProviders.append(provider)
                        }
                    }
                    providers = parsedProviders.isEmpty ? nil : parsedProviders
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of system package providers"))
                }
            } else if label == "resources" {
                if let parsed = argument.expression.parseArrayElements(parseResource) {
                    resources.append(contentsOf: parsed)
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of resources"))
                }
            } else if label == "capability" {
                pluginCapability = parsePluginCapability(argument.expression)
            } else if label == "cSettings" {
                if let parsed = argument.expression.parseArrayElements({ parseBuildSetting($0, tool: .c) }) {
                    settings.append(contentsOf: parsed)
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of C build settings"))
                }
            } else if label == "cxxSettings" {
                if let parsed = argument.expression.parseArrayElements({ parseBuildSetting($0, tool: .cxx) }) {
                    settings.append(contentsOf: parsed)
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of C++ build settings"))
                }
            } else if label == "swiftSettings" {
                if let parsed = argument.expression.parseArrayElements({ parseBuildSetting($0, tool: .swift) }) {
                    settings.append(contentsOf: parsed)
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of Swift build settings"))
                }
            } else if label == "linkerSettings" {
                if let parsed = argument.expression.parseArrayElements({ parseBuildSetting($0, tool: .linker) }) {
                    settings.append(contentsOf: parsed)
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of linker settings"))
                }
            } else if label == "plugins" {
                if let parsed = argument.expression.parseArrayElements(parsePluginUsage) {
                    pluginUsages = parsed
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of plugin usages"))
                }
            } else if label == "packageAccess" {
                if let boolValue = argument.expression.asBooleanLiteralValue() {
                    packageAccess = boolValue
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "boolean literal for packageAccess"))
                }
            } else {
                limitations.append(.unsupportedArgument(argument, callee: methodName))
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
                url: url,
                exclude: exclude,
                sources: sources,
                resources: resources,
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
            return nil
        }
    }
    
    /// Parse a target dependency like "dep1", .target(name: "dep2"), or .product(name: "dep3", package: "Pkg")
    private func parseTargetDependency(_ expr: ExprSyntax) -> TargetDescription.Dependency? {
        // Case 1: String literal dependency (e.g., "dep1")
        if let depName = expr.asStringLiteralValue(in: contextModel) {
            return .byName(name: depName, condition: nil)
        }
        
        // Case 2: .target(name: ...) or .product(name: ..., package: ...)
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            limitations.append(.unsupportedExpression(expr, expected: "target dependency"))
            return nil
        }
        
        if methodName == "target" {
            // Parse .target(name: "...", condition: ...)
            var name: String?
            var condition: PackageConditionDescription?
            
            for argument in arguments {
                let label = argument.label?.text
                if label == "name" {
                    name = argument.expression.asStringLiteralValue(in: contextModel)
                } else if label == "condition" {
                    condition = parsePackageCondition(argument.expression)
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "target"))
                }
            }

            if let targetName = name {
                return .target(name: targetName, condition: condition)
            }
            limitations.append(.unsupportedExpression(expr, expected: ".target with name"))
            return nil
        } else if methodName == "product" {
            // Parse .product(name: "...", package: "...", moduleAliases: [...], condition: ...)
            var name: String?
            var package: String?
            var moduleAliases: [String: String]?
            var condition: PackageConditionDescription?
            
            for argument in arguments {
                let label = argument.label?.text
                if label == "name" {
                    name = argument.expression.asStringLiteralValue(in: contextModel)
                } else if label == "package" {
                    package = argument.expression.asStringLiteralValue(in: contextModel)
                } else if label == "moduleAliases" {
                    moduleAliases = parseModuleAliases(argument.expression)
                } else if label == "condition" {
                    condition = parsePackageCondition(argument.expression)
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "product"))
                }
            }

            if let productName = name {
                return .product(name: productName, package: package, moduleAliases: moduleAliases, condition: condition)
            }
            limitations.append(.unsupportedExpression(expr, expected: ".product with name"))
            return nil
        } else if methodName == "byName" {
            // Parse .byName(name: "...", condition: ...)
            var name: String?
            var condition: PackageConditionDescription?
            
            for argument in arguments {
                let label = argument.label?.text
                if label == "name" {
                    name = argument.expression.asStringLiteralValue(in: contextModel)
                } else if label == "condition" {
                    condition = parsePackageCondition(argument.expression)
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "byName"))
                }
            }

            if let depName = name {
                return .byName(name: depName, condition: condition)
            }
            limitations.append(.unsupportedExpression(expr, expected: ".byName with name"))
            return nil
        } else {
            limitations.append(.unsupportedExpression(expr, expected: ".target or .product dependency"))
            return nil
        }
    }
    
    /// Parse a package condition like .when(platforms: [.macOS, .linux])
    private func parsePackageCondition(_ expr: ExprSyntax) -> PackageConditionDescription? {
        guard let (methodName, arguments) = expr.asMemberAccessCall(),
              methodName == "when" else {
            limitations.append(.unsupportedExpression(expr, expected: "package condition"))
            return nil
        }
        
        var platformNames: [String] = []
        var hasPlatforms = false
        var config: String?
        var traits: [String]?

        for argument in arguments {
            let label = argument.label?.text
            
            if label == "platforms" {
                hasPlatforms = true
                guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of platform conditions"))
                    continue
                }
                for element in arrayExpr.elements {
                    if let name = element.expression.asPlatformConditionName() {
                        platformNames.append(name.lowercased())
                    } else {
                        limitations.append(.unsupportedExpression(element.expression, expected: "known platform"))
                    }
                }
            } else if label == "configuration" {
                if let value = argument.expression.asEnumMember() {
                    config = value
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "build configuration"))
                }
            } else if label == "traits" {
                if let parsed = argument.expression.asStringArray(in: contextModel) {
                    traits = parsed
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of trait names"))
                }
            } else {
                limitations.append(.unsupportedArgument(argument, callee: "when"))
            }
        }

        // If platforms is explicitly empty and no other conditions, return nil (no condition)
        if hasPlatforms && platformNames.isEmpty && config == nil && traits == nil {
            return nil
        }
        
        // At least one non-empty condition must be specified
        if !platformNames.isEmpty || config != nil || traits != nil {
            return PackageConditionDescription(platformNames: platformNames, config: config, traits: traits.map { Set($0)})
        }
        
        limitations.append(.unsupportedExpression(expr, expected: "package condition with platforms, configuration, or traits"))
        return nil
    }
    
    /// Parse module aliases dictionary like ["OriginalName": "AliasName", ...]
    private func parseModuleAliases(_ expr: ExprSyntax) -> [String: String]? {
        guard let dictExpr = expr.as(DictionaryExprSyntax.self) else {
            limitations.append(.unsupportedExpression(expr, expected: "dictionary for module aliases"))
            return nil
        }
        
        var aliases: [String: String] = [:]
        
        // Check if it's a dictionary with elements
        switch dictExpr.content {
        case .colon:
            // Empty dictionary [:]
            return nil
        case .elements(let elements):
            // Dictionary with key-value pairs
            for element in elements {
                if let keyString = element.key.asStringLiteralValue(in: contextModel),
                   let valueString = element.value.asStringLiteralValue(in: contextModel) {
                    aliases[keyString] = valueString
                } else {
                    limitations.append(.unsupportedExpression(element.key, expected: "string literal module alias key and value"))
                }
            }
        }
        
        return aliases.isEmpty ? nil : aliases
    }
    
    /// Parse a build setting like .headerSearchPath("path"), .define("NAME"), .linkedLibrary("lib"), etc.
    private func parseBuildSetting(_ expr: ExprSyntax, tool: TargetBuildSettingDescription.Tool) -> TargetBuildSettingDescription.Setting? {
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil,
              let methodName = memberAccess.declName.baseName.identifier?.name else {
            limitations.append(.unsupportedExpression(expr, expected: "build setting"))
            return nil
        }
        
        var kind: TargetBuildSettingDescription.Kind?
        var condition: PackageConditionDescription?
        var conditionArgumentIndex: Int?

        // Parse the kind based on method name
        switch methodName {
        case "headerSearchPath":
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil {
                    if kind == nil, let path = argument.expression.asStringLiteralValue(in: contextModel) {
                        kind = .headerSearchPath(path)
                    } else {
                        conditionArgumentIndex = index
                    }
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "headerSearchPath"))
                }
            }
        case "define":
            // .define("NAME") or .define("NAME", to: "VALUE")
            var name: String?
            var value: String?
            
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil {
                    if let str = argument.expression.asStringLiteralValue(in: contextModel) {
                        name = str
                    } else {
                        conditionArgumentIndex = index
                    }
                } else if label == "to" {
                    value = argument.expression.asStringLiteralValue(in: contextModel)
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "define"))
                }
            }
            
            if let defineName = name {
                if let defineValue = value {
                    kind = .define("\(defineName)=\(defineValue)")
                } else {
                    kind = .define(defineName)
                }
            }
        case "linkedLibrary":
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil {
                    if kind == nil, let library = argument.expression.asStringLiteralValue(in: contextModel) {
                        kind = .linkedLibrary(library)
                    } else {
                        conditionArgumentIndex = index
                    }
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "linkedLibrary"))
                }
            }
        case "linkedFramework":
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil {
                    if kind == nil, let framework = argument.expression.asStringLiteralValue(in: contextModel) {
                        kind = .linkedFramework(framework)
                    } else {
                        conditionArgumentIndex = index
                    }
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "linkedFramework"))
                }
            }
        case "unsafeFlags":
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil {
                    if kind == nil, let flagsArray = argument.expression.as(ArrayExprSyntax.self) {
                        var flags: [String] = []
                        for flagElement in flagsArray.elements {
                            if let flag = flagElement.expression.asStringLiteralValue(in: contextModel) {
                                flags.append(flag)
                            } else {
                                limitations.append(.unsupportedExpression(flagElement.expression, expected: "string literal in unsafeFlags"))
                            }
                        }
                        kind = .unsafeFlags(flags)
                    } else {
                        conditionArgumentIndex = index
                    }
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "unsafeFlags"))
                }
            }
        case "enableUpcomingFeature":
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil {
                    if kind == nil, let feature = argument.expression.asStringLiteralValue(in: contextModel) {
                        kind = .enableUpcomingFeature(feature)
                    } else {
                        conditionArgumentIndex = index
                    }
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "enableUpcomingFeature"))
                }
            }
        case "enableExperimentalFeature":
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil {
                    if kind == nil, let feature = argument.expression.asStringLiteralValue(in: contextModel) {
                        kind = .enableExperimentalFeature(feature)
                    } else {
                        conditionArgumentIndex = index
                    }
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "enableExperimentalFeature"))
                }
            }
        case "interoperabilityMode":
            // .interoperabilityMode(.C) or .interoperabilityMode(.Cxx)
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil {
                    if kind == nil,
                       let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                       memberAccess.base == nil,
                       let modeName = memberAccess.declName.baseName.identifier?.name {
                        switch modeName {
                        case "C":
                            kind = .interoperabilityMode(.C)
                        case "Cxx":
                            kind = .interoperabilityMode(.Cxx)
                        default:
                            limitations.append(.unsupportedExpression(argument.expression, expected: "known interoperability mode"))
                        }
                    } else {
                        conditionArgumentIndex = index
                    }
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "interoperabilityMode"))
                }
            }
        case "strictMemorySafety":
            kind = .strictMemorySafety
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil || label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "strictMemorySafety"))
                }
            }
        case "swiftLanguageMode", "swiftLanguageVersion":
            // .swiftLanguageMode(.v5) or .swiftLanguageMode(.version("6"))
            // Also supports deprecated .swiftLanguageVersion() for backward compatibility
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil {
                    if kind == nil, let version = parseSwiftLanguageVersion(argument.expression) {
                        kind = .swiftLanguageMode(version)
                    } else {
                        conditionArgumentIndex = index
                    }
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: methodName))
                }
            }
        case "treatAllWarnings":
            // .treatAllWarnings(.warning) or .treatAllWarnings(.error)
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil || label == "as" {
                    if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                       memberAccess.base == nil,
                       let levelName = memberAccess.declName.baseName.identifier?.name {
                        switch levelName {
                        case "warning":
                            kind = .treatAllWarnings(.warning)
                        case "error":
                            kind = .treatAllWarnings(.error)
                        default:
                            limitations.append(.unsupportedExpression(argument.expression, expected: "warning level (.warning or .error)"))
                        }
                    } else if label == nil {
                        conditionArgumentIndex = index
                    }
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "treatAllWarnings"))
                }
            }
        case "treatWarning":
            // .treatWarning("deprecated", as: .error)
            var warningName: String?
            var level: TargetBuildSettingDescription.WarningLevel?
            
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil {
                    if let str = argument.expression.asStringLiteralValue(in: contextModel) {
                        warningName = str
                    } else {
                        conditionArgumentIndex = index
                    }
                } else if label == "as" {
                    if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                       memberAccess.base == nil,
                       let levelName = memberAccess.declName.baseName.identifier?.name {
                        switch levelName {
                        case "warning":
                            level = .warning
                        case "error":
                            level = .error
                        default:
                            break
                        }
                    }
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "treatWarning"))
                }
            }
            
            if let warning = warningName, let warningLevel = level {
                kind = .treatWarning(warning, warningLevel)
            }
        case "enableWarning":
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil {
                    if kind == nil, let warning = argument.expression.asStringLiteralValue(in: contextModel) {
                        kind = .enableWarning(warning)
                    } else {
                        conditionArgumentIndex = index
                    }
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "enableWarning"))
                }
            }
        case "disableWarning":
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil {
                    if kind == nil, let warning = argument.expression.asStringLiteralValue(in: contextModel) {
                        kind = .disableWarning(warning)
                    } else {
                        conditionArgumentIndex = index
                    }
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "disableWarning"))
                }
            }
        case "defaultIsolation":
            // .defaultIsolation(MainActor.self) → .MainActor isolation
            // .defaultIsolation(nil)            → nonisolated (compiler default)
            for (index, argument) in functionCall.arguments.enumerated() {
                let label = argument.label?.text
                if label == nil {
                    if kind == nil {
                        if argument.expression.is(NilLiteralExprSyntax.self) {
                            kind = .defaultIsolation(.nonisolated)
                        } else if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                                  let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
                                  base.baseName.text == "MainActor",
                                  memberAccess.declName.baseName.text == "self" {
                            kind = .defaultIsolation(.MainActor)
                        } else {
                            conditionArgumentIndex = index
                        }
                    } else {
                        conditionArgumentIndex = index
                    }
                } else if label == "condition" {
                    conditionArgumentIndex = index
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "defaultIsolation"))
                }
            }
        default:
            limitations.append(.unsupportedExpression(expr, expected: "known build setting type"))
            return nil
        }
        
        // Parse condition if present. The condition parameter is unlabeled in the
        // PackageDescription API (e.g., .define("C", .when(platforms: [.linux]))),
        // though some manifests may also use the explicit label "condition:".
        // Each case above sets conditionArgumentIndex when it identifies the
        // condition argument.
        if let conditionIndex = conditionArgumentIndex {
            let conditionArg = functionCall.arguments[
                functionCall.arguments.index(functionCall.arguments.startIndex, offsetBy: conditionIndex)
            ]
            if let parsedCondition = parsePackageCondition(conditionArg.expression) {
                condition = parsedCondition
            }
        }
        
        guard let settingKind = kind else {
            limitations.append(.unsupportedExpression(expr, expected: "valid build setting"))
            return nil
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
    private func parseSystemPackageProvider(_ expr: ExprSyntax) -> SystemPackageProviderDescription? {
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil, // Leading dot syntax
              let methodName = memberAccess.declName.baseName.identifier?.name else {
            limitations.append(.unsupportedExpression(expr, expected: "system package provider"))
            return nil
        }
        
        // Parse arguments
        var packages: [String] = []
        for argument in functionCall.arguments {
            let label = argument.label?.text
            if label == nil {
                if let arrayExpr = argument.expression.as(ArrayExprSyntax.self) {
                    for element in arrayExpr.elements {
                        if let packageName = element.expression.asStringLiteralValue(in: contextModel) {
                            packages.append(packageName)
                        } else {
                            limitations.append(.unsupportedExpression(element.expression, expected: "string literal package name"))
                        }
                    }
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of package names"))
                }
            } else {
                limitations.append(.unsupportedArgument(argument, callee: methodName))
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
    
    /// Parse a resource declaration like .copy("foo.txt") or .process("bar.txt", localization: .default)
    private func parseResource(_ expr: ExprSyntax) -> TargetDescription.Resource? {
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            limitations.append(.unsupportedExpression(expr, expected: "resource declaration"))
            return nil
        }
        
        // Parse the path argument (first unlabeled argument)
        guard let firstArg = arguments.first,
              firstArg.label == nil,
              let path = firstArg.expression.asStringLiteralValue(in: contextModel) else {
            limitations.append(.unsupportedExpression(expr, expected: "resource with path"))
            return nil
        }
        
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
                        return nil
                    }
                    switch localizationName {
                    case "default":
                        localization = .default
                    case "base":
                        localization = .base
                    default:
                        limitations.append(.unsupportedExpression(argument.expression, expected: "known localization type"))
                        return nil
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
            limitations.append(.unsupportedExpression(expr, expected: "known resource type"))
            return nil
        }
        
        return TargetDescription.Resource(rule: rule, path: (try? RelativePath(validating: path))?.pathString ?? path)
    }
    
    /// Parse a plugin capability like .buildTool() or .command(intent: .custom(verb: "foo", description: "bar"))
    private func parsePluginCapability(_ expr: ExprSyntax) -> TargetDescription.PluginCapability? {
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            limitations.append(.unsupportedExpression(expr, expected: "plugin capability"))
            return nil
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
                let label = argument.label?.text
                if label == "intent" {
                    intent = parsePluginCommandIntent(argument.expression)
                } else if label == "permissions" {
                    permissions = argument.expression.parseArrayElements(parsePluginPermission) ?? []
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "command"))
                }
            }
            
            if let commandIntent = intent {
                return .command(intent: commandIntent, permissions: permissions)
            } else {
                limitations.append(.unsupportedExpression(expr, expected: "command capability with intent"))
                return nil
            }
        default:
            limitations.append(.unsupportedExpression(expr, expected: "known plugin capability type"))
            return nil
        }
    }
    
    /// Parse a plugin command intent like .documentationGeneration or .custom(verb: "foo", description: "bar")
    private func parsePluginCommandIntent(_ expr: ExprSyntax) -> TargetDescription.PluginCommandIntent? {
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
            case "documentationGeneration":
                return .documentationGeneration
            case "sourceCodeFormatting":
                return .sourceCodeFormatting
            case "custom":
                var verb: String?
                var description: String?
                
                for argument in arguments {
                    let label = argument.label?.text
                    if label == "verb" {
                        verb = argument.expression.asStringLiteralValue(in: contextModel)
                    } else if label == "description" {
                        description = argument.expression.asStringLiteralValue(in: contextModel)
                    } else {
                        limitations.append(.unsupportedArgument(argument, callee: "custom"))
                    }
                }
                
                if let v = verb, let d = description {
                    return .custom(verb: v, description: d)
                }
            default:
                break
            }
        }
        
        limitations.append(.unsupportedExpression(expr, expected: "plugin command intent"))
        return nil
    }
    
    /// Parse a plugin permission like .writeToPackageDirectory(reason: "...")
    private func parsePluginPermission(_ expr: ExprSyntax) -> TargetDescription.PluginPermission? {
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            limitations.append(.unsupportedExpression(expr, expected: "plugin permission"))
            return nil
        }
        
        switch methodName {
        case "writeToPackageDirectory":
            for argument in arguments {
                if argument.label?.text == "reason",
                   let reason = argument.expression.asStringLiteralValue(in: contextModel) {
                    return .writeToPackageDirectory(reason: reason)
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "writeToPackageDirectory"))
                }
            }
            limitations.append(.unsupportedExpression(expr, expected: "writeToPackageDirectory with reason"))
            return nil
        case "allowNetworkConnections":
            // Parse .allowNetworkConnections(scope: ..., reason: "...")
            var scope: TargetDescription.PluginNetworkPermissionScope?
            var reason: String?
            
            for argument in arguments {
                let label = argument.label?.text
                if label == "scope" {
                    scope = parsePluginNetworkPermissionScope(argument.expression)
                } else if label == "reason" {
                    reason = argument.expression.asStringLiteralValue(in: contextModel)
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "allowNetworkConnections"))
                }
            }
            
            if let s = scope, let r = reason {
                return .allowNetworkConnections(scope: s, reason: r)
            } else {
                limitations.append(.unsupportedExpression(expr, expected: "allowNetworkConnections with scope and reason"))
                return nil
            }
        default:
            limitations.append(.unsupportedExpression(expr, expected: "known plugin permission type"))
            return nil
        }
    }
    
    /// Parse a plugin network permission scope like .none, .local(ports: [8080]), .all(ports: []), .docker, .unixDomainSocket
    private func parsePluginNetworkPermissionScope(_ expr: ExprSyntax) -> TargetDescription.PluginNetworkPermissionScope? {
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
                   let portsArray = argument.expression.as(ArrayExprSyntax.self) {
                    for portElement in portsArray.elements {
                        if let intLiteral = portElement.expression.as(IntegerLiteralExprSyntax.self),
                           let port = Int(intLiteral.literal.text) {
                            ports.append(port)
                        }
                    }
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
                limitations.append(.unsupportedExpression(expr, expected: "known network permission scope"))
                return nil
            }
        }
        
        limitations.append(.unsupportedExpression(expr, expected: "plugin network permission scope"))
        return nil
    }
    
    /// Parse a plugin usage like "PluginName", .plugin(name: "MyPlugin"), or .plugin(name: "MyPlugin", package: "MyPackage")
    private func parsePluginUsage(_ expr: ExprSyntax) -> TargetDescription.PluginUsage? {
        // Case 1: String literal (e.g., "PluginName" - refers to plugin in same package)
        if let pluginName = expr.asStringLiteralValue(in: contextModel) {
            return .plugin(name: pluginName, package: nil)
        }
        
        // Case 2: .plugin(name: "...", package: "...") or .plugin(name: "...")
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil, // Leading dot syntax
              memberAccess.declName.baseName.text == "plugin" else {
            limitations.append(.unsupportedExpression(expr, expected: "plugin usage declaration"))
            return nil
        }
        
        var name: String?
        var package: String?
        
        for argument in functionCall.arguments {
            let label = argument.label?.text
            if label == "name" {
                name = argument.expression.asStringLiteralValue(in: contextModel)
            } else if label == "package" {
                package = argument.expression.asStringLiteralValue(in: contextModel)
            } else {
                limitations.append(.unsupportedArgument(argument, callee: "plugin"))
            }
        }
        
        guard let pluginName = name else {
            limitations.append(.unsupportedExpression(expr, expected: "plugin usage with name"))
            return nil
        }
        
        return .plugin(name: pluginName, package: package)
    }
    
    /// Parse a product declaration like .executable(name: "tool", targets: ["tool"])
    private func parseProduct(_ expr: ExprSyntax) -> ProductDescription? {
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            limitations.append(.unsupportedExpression(expr, expected: "product declaration"))
            return nil
        }

        // Parse product arguments
        var name: String?
        var targets: [String] = []
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

            if label == "name" {
                name = argument.expression.asStringLiteralValue(in: contextModel)
            } else if label == "targets" {
                targets = argument.expression.asStringArray(in: contextModel) ?? []
            } else if label == "type" {
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
            } else {
                // For Apple product types, additional labels are handled below.
                // On non-Apple builds any unrecognized label is a limitation.
                #if ENABLE_APPLE_PRODUCT_TYPES
                if label == "bundleIdentifier" {
                    bundleIdentifier = argument.expression.asStringLiteralValue(in: contextModel)
                } else if label == "teamIdentifier" {
                    teamIdentifier = argument.expression.asStringLiteralValue(in: contextModel)
                } else if label == "displayVersion" {
                    displayVersion = argument.expression.asStringLiteralValue(in: contextModel)
                } else if label == "bundleVersion" {
                    bundleVersion = argument.expression.asStringLiteralValue(in: contextModel)
                } else if label == "appIcon" {
                    appIcon = parseAppIcon(argument.expression)
                } else if label == "accentColor" {
                    accentColor = parseAccentColor(argument.expression)
                } else if label == "supportedDeviceFamilies" {
                    supportedDeviceFamilies = parseDeviceFamilies(argument.expression)
                } else if label == "supportedInterfaceOrientations" {
                    supportedInterfaceOrientations = parseInterfaceOrientations(argument.expression)
                } else if label == "capabilities" {
                    capabilities = parseCapabilities(argument.expression)
                } else if label == "appCategory" {
                    appCategory = parseAppCategory(argument.expression)
                } else if label == "additionalInfoPlistContentFilePath" {
                    additionalInfoPlistContentFilePath = argument.expression.asStringLiteralValue(in: contextModel)
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: methodName))
                }
                #else
                limitations.append(.unsupportedArgument(argument, callee: methodName))
                #endif
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
            return nil
        }
        
        do {
            return try ProductDescription(
                name: productName,
                type: finalProductType,
                targets: targets,
                settings: settings
            )
        } catch {
            limitations.append(.unsupportedExpression(expr, expected: "valid product configuration"))
            return nil
        }
    }
    
    /// Parse C language standard like .iso9899_199409
    private func parseCLanguageStandard(_ expr: ExprSyntax) -> String? {
        guard let standardName = expr.asEnumMember() else {
            limitations.append(.unsupportedExpression(expr, expected: "C language standard"))
            return nil
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
            limitations.append(.unsupportedExpression(expr, expected: "known C language standard"))
            return nil
        }
    }
    
    /// Parse C++ language standard like .gnucxx14
    private func parseCxxLanguageStandard(_ expr: ExprSyntax) -> String? {
        guard let standardName = expr.asEnumMember() else {
            limitations.append(.unsupportedExpression(expr, expected: "C++ language standard"))
            return nil
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
            limitations.append(.unsupportedExpression(expr, expected: "known C++ language standard"))
            return nil
        }
    }
    
    #if ENABLE_APPLE_PRODUCT_TYPES
    /// Parse an app icon like .asset("icon") or .placeholder(.appIcon)
    private func parseAppIcon(_ expr: ExprSyntax) -> ProductSetting.IOSAppInfo.AppIcon? {
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            limitations.append(.unsupportedExpression(expr, expected: "app icon"))
            return nil
        }
        
        switch methodName {
        case "asset":
            if let name = arguments.first?.expression.asStringLiteralValue(in: contextModel) {
                for argument in arguments.dropFirst() {
                    limitations.append(.unsupportedArgument(argument, callee: "asset"))
                }
                return .asset(name: name)
            }
        case "placeholder":
            if let iconArg = arguments.first?.expression,
               let iconName = iconArg.asEnumMember() {
                for argument in arguments.dropFirst() {
                    limitations.append(.unsupportedArgument(argument, callee: "placeholder"))
                }
                return .placeholder(icon: .init(rawValue: iconName))
            }
        default:
            break
        }
        
        limitations.append(.unsupportedExpression(expr, expected: "valid app icon"))
        return nil
    }
    
    /// Parse an accent color like .asset("color") or .presetColor(.blue)
    private func parseAccentColor(_ expr: ExprSyntax) -> ProductSetting.IOSAppInfo.AccentColor? {
        guard let (methodName, arguments) = expr.asMemberAccessCall() else {
            limitations.append(.unsupportedExpression(expr, expected: "accent color"))
            return nil
        }
        
        switch methodName {
        case "asset":
            if let name = arguments.first?.expression.asStringLiteralValue(in: contextModel) {
                for argument in arguments.dropFirst() {
                    limitations.append(.unsupportedArgument(argument, callee: "asset"))
                }
                return .asset(name: name)
            }
        case "presetColor":
            if let colorArg = arguments.first?.expression,
               let colorName = colorArg.asEnumMember() {
                for argument in arguments.dropFirst() {
                    limitations.append(.unsupportedArgument(argument, callee: "presetColor"))
                }
                return .presetColor(presetColor: .init(rawValue: colorName))
            }
        default:
            break
        }
        
        limitations.append(.unsupportedExpression(expr, expected: "valid accent color"))
        return nil
    }
    
    /// Parse device families like [.pad, .phone, .mac]
    private func parseDeviceFamilies(_ expr: ExprSyntax) -> [ProductSetting.IOSAppInfo.DeviceFamily] {
        guard let arrayExpr = expr.as(ArrayExprSyntax.self) else {
            limitations.append(.unsupportedExpression(expr, expected: "device family array"))
            return []
        }
        
        var families: [ProductSetting.IOSAppInfo.DeviceFamily] = []
        for element in arrayExpr.elements {
            if let familyName = element.expression.asEnumMember(),
               let family = ProductSetting.IOSAppInfo.DeviceFamily(rawValue: familyName) {
                families.append(family)
            }
        }
        return families
    }
    
    /// Parse interface orientations like [.portrait, .landscapeRight(.when(deviceFamilies: [.mac]))]
    private func parseInterfaceOrientations(_ expr: ExprSyntax) -> [ProductSetting.IOSAppInfo.InterfaceOrientation] {
        guard let arrayExpr = expr.as(ArrayExprSyntax.self) else {
            limitations.append(.unsupportedExpression(expr, expected: "interface orientation array"))
            return []
        }
        
        var orientations: [ProductSetting.IOSAppInfo.InterfaceOrientation] = []
        for element in arrayExpr.elements {
            if let orientation = parseInterfaceOrientation(element.expression) {
                orientations.append(orientation)
            }
        }
        return orientations
    }
    
    /// Parse a single interface orientation like .portrait or .landscapeRight(.when(deviceFamilies: [.mac]))
    private func parseInterfaceOrientation(_ expr: ExprSyntax) -> ProductSetting.IOSAppInfo.InterfaceOrientation? {
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
                break
            }
        }
        
        // Handle conditional case: .portrait(.when(deviceFamilies: [.mac]))
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil,
              let orientationName = memberAccess.declName.baseName.identifier?.name else {
            limitations.append(.unsupportedExpression(expr, expected: "interface orientation"))
            return nil
        }
        
        var condition: ProductSetting.IOSAppInfo.DeviceFamilyCondition?
        if let conditionArg = functionCall.arguments.first?.expression {
            condition = parseDeviceFamilyCondition(conditionArg)
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
            limitations.append(.unsupportedExpression(expr, expected: "valid interface orientation"))
            return nil
        }
    }
    
    /// Parse a device family condition like .when(deviceFamilies: [.mac])
    private func parseDeviceFamilyCondition(_ expr: ExprSyntax) -> ProductSetting.IOSAppInfo.DeviceFamilyCondition? {
        guard let (methodName, arguments) = expr.asMemberAccessCall(),
              methodName == "when" else {
            limitations.append(.unsupportedExpression(expr, expected: "device family condition"))
            return nil
        }
        
        for argument in arguments {
            if argument.label?.text == "deviceFamilies" {
                let families = parseDeviceFamilies(argument.expression)
                return ProductSetting.IOSAppInfo.DeviceFamilyCondition(deviceFamilies: families)
            }
        }
        
        return nil
    }
    
    /// Parse capabilities like [.camera(purposeString: "..."), .microphone(purposeString: "...")]
    private func parseCapabilities(_ expr: ExprSyntax) -> [ProductSetting.IOSAppInfo.Capability] {
        guard let arrayExpr = expr.as(ArrayExprSyntax.self) else {
            limitations.append(.unsupportedExpression(expr, expected: "capability array"))
            return []
        }
        
        var capabilities: [ProductSetting.IOSAppInfo.Capability] = []
        for element in arrayExpr.elements {
            if let capability = parseCapability(element.expression) {
                capabilities.append(capability)
            }
        }
        return capabilities
    }
    
    /// Parse a single capability
    private func parseCapability(_ expr: ExprSyntax) -> ProductSetting.IOSAppInfo.Capability? {
        guard let (purpose, arguments) = expr.asMemberAccessCall() else {
            limitations.append(.unsupportedExpression(expr, expected: "capability"))
            return nil
        }
        
        var purposeString: String?
        var bonjourServiceTypes: [String]?
        var condition: ProductSetting.IOSAppInfo.DeviceFamilyCondition?
        
        for argument in arguments {
            let label = argument.label?.text
            
            if label == "purposeString" {
                purposeString = argument.expression.asStringLiteralValue(in: contextModel)
            } else if label == "bonjourServiceTypes" {
                bonjourServiceTypes = argument.expression.asStringArray(in: contextModel)
            } else if label == nil {
                // Unlabeled argument could be a condition
                if let cond = parseDeviceFamilyCondition(argument.expression) {
                    condition = cond
                }
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
    private func parseAppCategory(_ expr: ExprSyntax) -> ProductSetting.IOSAppInfo.AppCategory? {
        guard let categoryName = expr.asEnumMember() else {
            limitations.append(.unsupportedExpression(expr, expected: "app category"))
            return nil
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
    private func parsePackageDependency(_ expr: ExprSyntax, manifestPath: AbsolutePath) -> PackageDependency? {
        // Expect a function call like .package(url: "/foo", from: "1.0.0")
        guard let functionCall = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil, // Leading dot syntax
              let methodName = memberAccess.declName.baseName.identifier?.name,
              methodName == "package" else {
            limitations.append(.unsupportedExpression(expr, expected: "package dependency declaration"))
            return nil
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
            let label = argument.label?.text

            if label == "name" {
                name = argument.expression.asStringLiteralValue(in: contextModel)
            } else if label == "id" {
                id = argument.expression.asStringLiteralValue(in: contextModel)
            } else if label == "url" {
                url = argument.expression.asStringLiteralValue(in: contextModel)
            } else if label == "path" {
                path = argument.expression.asStringLiteralValue(in: contextModel)
            } else if label == "traits" {
                traits = parseDependencyTraits(argument.expression)
            } else if label == "from" {
                if let versionString = argument.expression.asStringLiteralValue(),
                   let version = Version(versionString) {
                    if id != nil {
                        // Registry dependency
                        registryRequirement = .range(.upToNextMajor(from: version))
                    } else {
                        // Source control dependency
                        requirement = .range(.upToNextMajor(from: version))
                    }
                }
            } else if label == "branch" {
                if let branch = argument.expression.asStringLiteralValue(in: contextModel) {
                    requirement = .branch(branch)
                }
            } else if label == "revision" {
                if let revision = argument.expression.asStringLiteralValue(in: contextModel) {
                    requirement = .revision(revision)
                }
            } else if label == "exact" {
                if let versionString = argument.expression.asStringLiteralValue(),
                   let version = Version(versionString) {
                    if id != nil {
                        // Registry dependency
                        registryRequirement = .exact(version)
                    } else {
                        // Source control dependency
                        requirement = .exact(version)
                    }
                }
            } else if label == nil {
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
                } else if let rangeExpr = argument.expression.as(SequenceExprSyntax.self) {
                    // Fallback: Check for range operators in SequenceExprSyntax (for older syntax trees)
                    // Look for range operators like ..< or ...
                    var lowerBound: Version?
                    var upperBound: Version?
                    var isClosedRange = false

                    for element in rangeExpr.elements {
                        if let stringLiteral = element.asStringLiteralValue(),
                           let version = Version(stringLiteral) {
                            if lowerBound == nil {
                                lowerBound = version
                            } else {
                                upperBound = version
                            }
                        } else if let binaryOp = element.as(BinaryOperatorExprSyntax.self) {
                            let opText = binaryOp.operator.text.trimmingCharacters(in: .whitespaces)
                            if opText == "..." {
                                isClosedRange = true
                            }
                        } else {
                            // Check if this element is just the operator token
                            let elementText = element.description.trimmingCharacters(in: .whitespaces)
                            if elementText == "..." {
                                isClosedRange = true
                            }
                        }
                    }

                    if let lower = lowerBound, let upper = upperBound {
                        if isClosedRange {
                            // Convert closed range to open range by using next patch version
                            let upperNext = Version(
                                upper.major,
                                upper.minor,
                                upper.patch + 1,
                                prereleaseIdentifiers: upper.prereleaseIdentifiers,
                                buildMetadataIdentifiers: upper.buildMetadataIdentifiers
                            )
                            if id != nil {
                                registryRequirement = .range(lower..<upperNext)
                            } else {
                                requirement = .range(lower..<upperNext)
                            }
                        } else {
                            if id != nil {
                                registryRequirement = .range(lower..<upper)
                            } else {
                                requirement = .range(lower..<upper)
                            }
                        }
                    } else {
                        limitations.append(.unsupportedExpression(argument.expression, expected: "version range with two bounds"))
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
                        }
                    case "exact":
                        if let versionString = reqExpr.arguments.first?.expression.asStringLiteralValue(),
                           let version = Version(versionString) {
                            if id != nil {
                                registryRequirement = .exact(version)
                            } else {
                                requirement = .exact(version)
                            }
                        }
                    case "branch":
                        if let branch = reqExpr.arguments.first?.expression.asStringLiteralValue() {
                            requirement = .branch(branch)
                        }
                    case "revision":
                        if let revision = reqExpr.arguments.first?.expression.asStringLiteralValue() {
                            requirement = .revision(revision)
                        }
                    default:
                        limitations.append(.unsupportedExpression(argument.expression, expected: "package dependency requirement"))
                    }
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "package dependency requirement"))
                }
            } else {
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
                return nil
            }
        }

        // Handle registry dependencies
        if let packageID = id {
            guard let regReq = registryRequirement else {
                limitations.append(.unsupportedExpression(expr, expected: "registry dependency with requirement"))
                return nil
            }

            let identity = PackageIdentity.plain(packageID)
            return .registry(
                identity: identity,
                requirement: regReq,
                productFilter: .everything,
                traits: Set(traits ?? [.init(name: "default")])
            )
        }

        guard let url = url, let requirement = requirement else {
            limitations.append(.unsupportedExpression(expr, expected: "package dependency with url and requirement"))
            return nil
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
            return nil
        }
    }
    
    /// Parse a platform description like `.macOS("10.13.option1.option2")` or `.iOS(.v12)`
    private func parsePlatform(_ expr: ExprSyntax) -> PlatformDescription? {
        // Expect a function call like .macOS("10.13")
        guard let (platformName, arguments) = expr.asMemberAccessCall() else {
            limitations.append(.unsupportedExpression(expr, expected: "platform declaration"))
            return nil
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
                let label = argument.label?.text
                if label == nil {
                    customName = argument.expression.asStringLiteralValue()
                } else if label == "versionString" {
                    versionString = argument.expression.asStringLiteralValue()
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "custom"))
                }
            }
            guard let name = customName, let version = versionString else {
                limitations.append(.unsupportedExpression(expr, expected: "custom platform with name and versionString"))
                return nil
            }
            return PlatformDescription(name: name, version: version, options: [])

        default:
            limitations.append(.unsupportedExpression(expr, expected: "known platform"))
            return nil
        }
        
        // Get the version argument and check for unexpected extra arguments
        guard let firstArg = arguments.first else {
            limitations.append(.unsupportedExpression(expr, expected: "platform with version"))
            return nil
        }
        
        for argument in arguments.dropFirst() {
            limitations.append(.unsupportedArgument(argument, callee: platformName))
        }

        var version: String
        var options: [String] = []
        
        // Check if it's a string literal like "10.13.option1.option2"
        if let versionString = firstArg.expression.asStringLiteralValue() {
            // Parse version and options from the string
            let components = versionString.split(separator: ".")
            if components.isEmpty {
                limitations.append(.unsupportedExpression(expr, expected: "valid version string"))
                return nil
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
        // Check if it's a member access like .v10_13
        else if let memberAccess = firstArg.expression.as(MemberAccessExprSyntax.self),
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
                limitations.append(.unsupportedExpression(expr, expected: "version in format .vX_Y"))
                return nil
            }
        }
        else {
            limitations.append(.unsupportedExpression(expr, expected: "string literal or version constant"))
            return nil
        }
        
        return PlatformDescription(name: canonicalName, version: version, options: options)
    }
    
    /// Parse a trait declaration like "Trait1", Trait(name: "Trait2", description: "..."), or .trait(name: "Trait3", enabledTraits: [...])
    private func parseTrait(_ expr: ExprSyntax) -> TraitDescription? {
        // Case 1: String literal "TraitName"
        if let traitName = expr.asStringLiteralValue(in: contextModel) {
            return TraitDescription(name: traitName)
        }
        
        // Case 2: Trait(name: "...", description: "...", enabledTraits: [...]) or .trait(...) or .default(...)
        guard let functionCall = expr.as(FunctionCallExprSyntax.self) else {
            limitations.append(.unsupportedExpression(expr, expected: "trait declaration"))
            return nil
        }
        
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
            limitations.append(.unsupportedExpression(expr, expected: "Trait(...), .trait(...), or .default(...)"))
            return nil
        }
        
        // Handle .default(enabledTraits: [...])
        if method == "default" {
            var enabledTraits: [String] = []

            for argument in functionCall.arguments {
                if argument.label?.text == "enabledTraits" {
                    if let parsed = argument.expression.asStringArray(in: contextModel) {
                        enabledTraits = parsed
                    } else {
                        limitations.append(.unsupportedExpression(argument.expression, expected: "array of enabled trait names"))
                    }
                } else {
                    limitations.append(.unsupportedArgument(argument, callee: "default"))
                }
            }

            return TraitDescription(
                name: "default",
                description: "The default traits of this package.",
                enabledTraits: Set(enabledTraits)
            )
        }

        // Handle .trait(...) or Trait(...)
        var name: String?
        var description: String?
        var enabledTraits: [String] = []

        for argument in functionCall.arguments {
            let label = argument.label?.text
            if label == "name" {
                name = argument.expression.asStringLiteralValue(in: contextModel)
            } else if label == "description" {
                description = argument.expression.asStringLiteralValue(in: contextModel)
            } else if label == "enabledTraits" {
                if let parsed = argument.expression.asStringArray(in: contextModel) {
                    enabledTraits = parsed
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of enabled trait names"))
                }
            } else {
                limitations.append(.unsupportedArgument(argument, callee: "trait"))
            }
        }
        
        guard let traitName = name else {
            limitations.append(.unsupportedExpression(expr, expected: "trait with name"))
            return nil
        }
        
        return TraitDescription(name: traitName, description: description, enabledTraits: Set(enabledTraits))
    }
    
    /// Parse dependency traits array like ["FooTrait1", .trait(name: "FooTrait2", condition: ...), .defaults]
    private func parseDependencyTraits(_ expr: ExprSyntax) -> [PackageDependency.Trait]? {
        guard let arrayExpr = expr.as(ArrayExprSyntax.self) else {
            limitations.append(.unsupportedExpression(expr, expected: "array of dependency traits"))
            return nil
        }
        
        var traits: [PackageDependency.Trait] = []
        
        for traitElement in arrayExpr.elements {
            if let trait = parseDependencyTrait(traitElement.expression) {
                traits.append(trait)
            }
        }
        
        return traits.isEmpty ? nil : traits
    }
    
    /// Parse a single dependency trait like "FooTrait1", .trait(name: "...", condition: ...), or .defaults
    private func parseDependencyTrait(_ expr: ExprSyntax) -> PackageDependency.Trait? {
        // Case 1: String literal "TraitName"
        if let traitName = expr.asStringLiteralValue(in: contextModel) {
            return PackageDependency.Trait(name: traitName)
        }
        
        // Case 2: .defaults
        if let memberAccess = expr.as(MemberAccessExprSyntax.self),
           memberAccess.base == nil,
           memberAccess.declName.baseName.text == "defaults" {
            return PackageDependency.Trait(name: "default")
        }
        
        // Case 3: .trait(name: "...", condition: ...) or Package.Dependency.Trait(name: "...", condition: ...)
        guard let functionCall = expr.as(FunctionCallExprSyntax.self) else {
            limitations.append(.unsupportedExpression(expr, expected: "dependency trait declaration"))
            return nil
        }
        
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
            limitations.append(.unsupportedExpression(expr, expected: ".trait(...) or Package.Dependency.Trait(...)"))
            return nil
        }
        
        var name: String?
        var condition: PackageDependency.Trait.Condition?
        
        for argument in functionCall.arguments {
            let label = argument.label?.text
            if label == "name" {
                name = argument.expression.asStringLiteralValue(in: contextModel)
            } else if label == "condition" {
                condition = parseDependencyTraitCondition(argument.expression)
            } else {
                limitations.append(.unsupportedArgument(argument, callee: "trait"))
            }
        }
        
        guard let traitName = name else {
            limitations.append(.unsupportedExpression(expr, expected: "dependency trait with name"))
            return nil
        }
        
        return PackageDependency.Trait(name: traitName, condition: condition)
    }
    
    /// Parse a dependency trait condition like .when(traits: ["Trait1"])
    private func parseDependencyTraitCondition(_ expr: ExprSyntax) -> PackageDependency.Trait.Condition? {
        guard let (methodName, arguments) = expr.asMemberAccessCall(),
              methodName == "when" else {
            limitations.append(.unsupportedExpression(expr, expected: "trait condition"))
            return nil
        }
        
        var traits: [String]?
        
        for argument in arguments {
            if argument.label?.text == "traits" {
                if let parsed = argument.expression.asStringArray(in: contextModel) {
                    traits = parsed
                } else {
                    limitations.append(.unsupportedExpression(argument.expression, expected: "array of trait names"))
                }
            } else {
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

    /// Evaluate a string literal that may contain Context interpolations, or a direct Context expression.
    /// Returns the evaluated string, or nil if it cannot be evaluated.
    fileprivate func asStringLiteralValue(in contextModel: StaticContextModel) -> String? {
        // First, try to evaluate as a direct Context expression (e.g., Context.packageDirectory)
        if let value = self.evaluateContextExpression(contextModel: contextModel) {
            return value
        }

        // Otherwise, try to parse as a string literal
        guard let stringLiteral = self.as(StringLiteralExprSyntax.self) else {
            return nil
        }

        // Simple case: no interpolation — use representedLiteralValue to correctly handle
        // escape sequences (e.g. \" in a C preprocessor define value becomes ").
        if let value = stringLiteral.representedLiteralValue {
            return value
        }

        // Complex case: handle interpolations with Context values
        var result = ""
        for segment in stringLiteral.segments {
            switch segment {
            case .stringSegment(let contents):
                result += contents.content.text

            case .expressionSegment(let exprSegment):
                // Try to evaluate the interpolated expression
                if let value = exprSegment.expressions.first?.expression.evaluateContextExpression(contextModel: contextModel) {
                    result += value
                } else {
                    // Cannot evaluate this interpolation
                    return nil
                }
            }
        }

        return result
    }
    
    /// Evaluate a Context expression like Context.gitInformation?.currentTag or Context.environment["KEY"]
    /// Returns the string representation of the value, or nil if it cannot be evaluated.
    fileprivate func evaluateContextExpression(contextModel: StaticContextModel) -> String? {
        var expr: ExprSyntax = self
        var nilCoalescingDefault: String? = nil

        // Handle nil-coalescing operator (??)
        if let infixExpr = expr.as(InfixOperatorExprSyntax.self),
           let op = infixExpr.operator.as(BinaryOperatorExprSyntax.self),
           op.operator.text.trimmingCharacters(in: .whitespaces) == "??" {
            // Get the default value from the right side
            if let rightValue = infixExpr.rightOperand.asStringLiteralValue() {
                nilCoalescingDefault = rightValue
            }
            // Continue evaluating the left side
            expr = infixExpr.leftOperand
        }
        
        // Handle boolean comparison (== true)
        if let infixExpr = expr.as(InfixOperatorExprSyntax.self),
           let op = infixExpr.operator.as(BinaryOperatorExprSyntax.self),
           op.operator.text.trimmingCharacters(in: .whitespaces) == "==" {
            // Check if right side is 'true'
            if let boolLit = infixExpr.rightOperand.as(BooleanLiteralExprSyntax.self),
               boolLit.literal.tokenKind == .keyword(.true) {
                expr = infixExpr.leftOperand
            }
        }
        
        // Check for subscript access (e.g., Context.environment["KEY"])
        if let subscriptExpr = expr.as(SubscriptCallExprSyntax.self) {
            // Parse the base expression (e.g., Context.environment)
            var baseParts: [String] = []
            var currentExpr = subscriptExpr.calledExpression
            
            // Walk through the member access chain
            while true {
                if let memberAccess = currentExpr.as(MemberAccessExprSyntax.self) {
                    baseParts.insert(memberAccess.declName.baseName.text, at: 0)
                    if let base = memberAccess.base {
                        currentExpr = base
                    } else {
                        break
                    }
                } else if let declRef = currentExpr.as(DeclReferenceExprSyntax.self) {
                    baseParts.insert(declRef.baseName.text, at: 0)
                    break
                } else {
                    return nil
                }
            }
            
            // Check if it's Context.environment
            if baseParts.count == 2 && baseParts[0] == "Context" && baseParts[1] == "environment" {
                // Get the subscript key
                if let firstArg = subscriptExpr.arguments.first,
                   let keyString = firstArg.expression.asStringLiteralValue() {
                    // Look up the environment variable
                    if let value = contextModel.environment[keyString] {
                        return value
                    } else {
                        return nilCoalescingDefault
                    }
                }
            }
            
            return nil
        }
        
        // Now parse the member access chain
        // Expected patterns:
        // - Context.packageDirectory
        // - Context.gitInformation?.currentTag
        // - Context.gitInformation?.currentCommit
        // - Context.gitInformation?.hasUncommittedChanges
        
        // Extract all parts of the member access chain
        var parts: [String] = []
        var currentExpr = expr
        
        // Walk backwards through the member access chain
        while true {
            if let sequence = currentExpr.as(SequenceExprSyntax.self) {
                // A sequence expression can contain optional chaining
                // For "Context.gitInformation?.currentTag", this will be a sequence
                // We need to extract the meaningful parts
                
                // For optional chaining, the sequence contains: base, postfixOperator(?), member access
                // Let's try to parse it differently - just take the first element if it's what we need
                if let firstElement = sequence.elements.first {
                    currentExpr = firstElement
                    continue
                } else {
                    return nil
                }
            } else if let memberAccess = currentExpr.as(MemberAccessExprSyntax.self) {
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
            } else if let postfixUnary = currentExpr.as(PostfixUnaryExprSyntax.self) {
                // This handles the ? in optional chaining
                currentExpr = postfixUnary.expression
            } else if let declRef = currentExpr.as(DeclReferenceExprSyntax.self) {
                // This is the base identifier (e.g., "Context")
                parts.insert(declRef.baseName.text, at: 0)
                break
            } else {
                // Unknown expression structure
                return nil
            }
        }
        
        // Now evaluate based on the parts
        guard parts.count >= 2 && parts[0] == "Context" else {
            return nil
        }
        
        switch parts[1] {
        case "packageDirectory":
            return contextModel.packageDirectory
            
        case "gitInformation":
            guard parts.count >= 3 else {
                return nil
            }
            guard let gitInfo = contextModel.gitInformation else {
                return nilCoalescingDefault
            }
            
            switch parts[2] {
            case "currentTag":
                if let tag = gitInfo.currentTag {
                    return tag
                } else {
                    return nilCoalescingDefault ?? ""
                }
                
            case "currentCommit":
                return gitInfo.currentCommit
                
            case "hasUncommittedChanges":
                let value = gitInfo.hasUncommittedChanges
                return value ? "true" : "false"
                
            default:
                return nil
            }
            
        default:
            return nil
        }
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

    /// Parse array elements using a transform function.
    /// Returns array of successfully transformed elements, or nil if expression is not an array.
    fileprivate func parseArrayElements<T>(_ transform: (ExprSyntax) -> T?) -> [T]? {
        guard let arrayExpr = self.as(ArrayExprSyntax.self) else {
            return nil
        }

        var result: [T] = []
        for element in arrayExpr.elements {
            if let value = transform(element.expression) {
                result.append(value)
            }
        }
        return result
    }

    /// Parse an array of string literals.
    fileprivate func asStringArray(in contextModel: StaticContextModel) -> [String]? {
        return parseArrayElements {
            $0.asStringLiteralValue(in: contextModel)
        }
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

    /// Parse a platform name as used in a `.when(platforms: [...])` condition.
    /// Handles both plain enum members (e.g. `.linux`) and custom platforms
    /// (e.g. `.custom("freebsd")`).
    fileprivate func asPlatformConditionName() -> String? {
        if let name = self.asEnumMember() {
            return name
        }

        // Handle .custom("platformName")
        guard let functionCall = self.as(FunctionCallExprSyntax.self),
              let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil,
              memberAccess.declName.baseName.identifier?.name == "custom",
              let firstArg = functionCall.arguments.first,
              firstArg.label == nil,
              let customName = firstArg.expression.asStringLiteralValue() else {
            return nil
        }
        return customName
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
#endif
