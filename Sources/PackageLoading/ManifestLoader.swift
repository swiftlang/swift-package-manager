/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import TSCBasic
import PackageModel
import TSCUtility
import Foundation
public typealias FileSystem = TSCBasic.FileSystem

public enum ManifestParseError: Swift.Error {
    /// The manifest contains invalid format.
    case invalidManifestFormat(String, diagnosticFile: AbsolutePath?)

    /// The manifest was successfully loaded by swift interpreter but there were runtime issues.
    case runtimeManifestErrors([String])
}

/// Resources required for manifest loading.
///
/// These requirements are abstracted out to make it easier to add support for
/// using the package manager with alternate toolchains in the future.
public protocol ManifestResourceProvider {
    /// The path of the swift compiler.
    var swiftCompiler: AbsolutePath { get }

    /// The path of the library resources.
    var libDir: AbsolutePath { get }

    /// The path to SDK root.
    ///
    /// If provided, it will be passed to the swift interpreter.
    var sdkRoot: AbsolutePath? { get }

    /// The bin directory.
    var binDir: AbsolutePath? { get }

    /// Extra flags to pass the Swift compiler.
    var swiftCompilerFlags: [String] { get }

    /// XCTest Location
    var xctestLocation: AbsolutePath? { get }
}

/// Default implemention for the resource provider.
public extension ManifestResourceProvider {

    var sdkRoot: AbsolutePath? {
        return nil
    }

    var binDir: AbsolutePath? {
        return nil
    }

    var swiftCompilerFlags: [String] {
        return []
    }

    var xctestLocation: AbsolutePath? {
        return nil
    }
}

/// Protocol for the manifest loader interface.
public protocol ManifestLoaderProtocol {
    /// Load the manifest for the package at `path`.
    ///
    /// - Parameters:
    ///   - at: The root path of the package.
    ///   - packageIdentity: the identity of the package
    ///   - packageKind: The kind of package the manifest is from.
    ///   - packageLocation: The location the package the manifest was loaded from.
    ///   - version: Optional. The version the manifest is from, if known.
    ///   - revision: Optional. The revision the manifest is from, if known
    ///   - toolsVersion: The version of the tools the manifest supports.
    ///   - identityResolver: A helper to resolve identities based on configuration
    ///   - fileSystem: The file system to load from.
    ///   - diagnostics: Optional.  The diagnostics engine.
    ///   - on: The dispatch queue to perform asynchronous operations on.
    ///   - completion: The completion handler .
    func load(
        at path: AbsolutePath,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        version: Version?,
        revision: String?,
        toolsVersion: ToolsVersion,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem,
        diagnostics: DiagnosticsEngine?,
        on queue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    )

    /// Reset any internal cache held by the manifest loader.
    func resetCache() throws

    /// Reset any internal cache held by the manifest loader and purge any entries in a shared cache
    func purgeCache() throws
}

public protocol ManifestLoaderDelegate {
    func willLoad(manifest: AbsolutePath)
    func willParse(manifest: AbsolutePath)
}

/// Utility class for loading manifest files.
///
/// This class is responsible for reading the manifest data and produce a
/// properly formed `PackageModel.Manifest` object. It currently does so by
/// interpreting the manifest source using Swift -- that produces a JSON
/// serialized form of the manifest (as implemented by `PackageDescription`'s
/// `atexit()` handler) which is then deserialized and loaded.
public final class ManifestLoader: ManifestLoaderProtocol {
    private static var _hostTriple = ThreadSafeBox<Triple>()
    private static var _packageDescriptionMinimumDeploymentTarget = ThreadSafeBox<String>()

    private let resources: ManifestResourceProvider
    private let serializedDiagnostics: Bool
    private let isManifestSandboxEnabled: Bool
    private let delegate: ManifestLoaderDelegate?
    private let extraManifestFlags: [String]

    private let databaseCacheDir: AbsolutePath?

    private let sdkRootCache = ThreadSafeBox<AbsolutePath>()

    private let operationQueue: OperationQueue

    public init(
        manifestResources: ManifestResourceProvider,
        serializedDiagnostics: Bool = false,
        isManifestSandboxEnabled: Bool = true,
        cacheDir: AbsolutePath? = nil,
        delegate: ManifestLoaderDelegate? = nil,
        extraManifestFlags: [String] = []
    ) {
        self.resources = manifestResources
        self.serializedDiagnostics = serializedDiagnostics
        self.isManifestSandboxEnabled = isManifestSandboxEnabled
        self.delegate = delegate
        self.extraManifestFlags = extraManifestFlags

        self.databaseCacheDir = cacheDir.map(resolveSymlinks)

        self.operationQueue = OperationQueue()
        self.operationQueue.name = "org.swift.swiftpm.manifest-loader"
        self.operationQueue.maxConcurrentOperationCount = Concurrency.maxOperations
    }

    // deprecated 3/21, remove once clients migrated over
    @available(*, deprecated, message: "use loadRootManifest instead")
    public static func loadManifest(
        at path: AbsolutePath,
        kind: PackageReference.Kind,
        swiftCompiler: AbsolutePath,
        swiftCompilerFlags: [String],
        identityResolver: IdentityResolver,
        on queue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        do {
            let fileSystem = localFileSystem
            let resources = try UserManifestResources(swiftCompiler: swiftCompiler, swiftCompilerFlags: swiftCompilerFlags)
            let loader = ManifestLoader(manifestResources: resources)
            let toolsVersion = try ToolsVersionLoader().load(at: path, fileSystem: fileSystem)
            let packageLocation = path.pathString
            let packageIdentity = identityResolver.resolveIdentity(for: packageLocation)
            loader.load(
                at: path,
                packageIdentity: packageIdentity,
                packageKind: kind,
                packageLocation: packageLocation,
                version: nil,
                revision: nil,
                toolsVersion: toolsVersion,
                identityResolver: identityResolver,
                fileSystem: fileSystem,
                diagnostics: nil,
                on: queue,
                completion: completion
            )
        } catch {
            return completion(.failure(error))
        }
    }

    /// Loads a root manifest from a path using the resources associated with a particular `swiftc` executable.
    ///
    /// - Parameters:
    ///   - at: The absolute path of the package root.
    ///   - swiftCompiler: The absolute path of a `swiftc` executable. Its associated resources will be used by the loader.
    ///   - identityResolver: A helper to resolve identities based on configuration
    ///   - diagnostics: Optional.  The diagnostics engine.
    ///   - on: The dispatch queue to perform asynchronous operations on.
    ///   - completion: The completion handler .
    public static func loadRootManifest(
        at path: AbsolutePath,
        swiftCompiler: AbsolutePath,
        swiftCompilerFlags: [String],
        identityResolver: IdentityResolver,
        diagnostics: DiagnosticsEngine? = nil,
        fileSystem: FileSystem = localFileSystem,
        on queue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        do {
            let resources = try UserManifestResources(swiftCompiler: swiftCompiler, swiftCompilerFlags: swiftCompilerFlags)
            let loader = ManifestLoader(manifestResources: resources)
            let toolsVersion = try ToolsVersionLoader().load(at: path, fileSystem: fileSystem)
            let packageLocation = fileSystem.isFile(path) ? path.parentDirectory : path
            let packageIdentity = identityResolver.resolveIdentity(for: packageLocation)
            loader.load(
                at: path,
                packageIdentity: packageIdentity,
                packageKind: .root,
                packageLocation: packageLocation.pathString,
                version: nil,
                revision: nil,
                toolsVersion: toolsVersion,
                identityResolver: identityResolver,
                fileSystem: fileSystem,
                diagnostics: diagnostics,
                on: queue,
                completion: completion
            )
        } catch {
            return completion(.failure(error))
        }
    }

    // deprecated 3/21, remove once clients migrated over
    @available(*, deprecated, message: "use load(at: packageIdentity:, ...) variant instead")
    public func load(
        at path: AbsolutePath,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        version: Version?,
        revision: String?,
        toolsVersion: ToolsVersion,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem,
        diagnostics: DiagnosticsEngine? = nil,
        on queue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        let packageIdentity = identityResolver.resolveIdentity(for: packageLocation)
        self.load(at: path,
                  packageIdentity: packageIdentity,
                  packageKind: packageKind,
                  packageLocation: packageLocation,
                  version: version,
                  revision: revision,
                  toolsVersion: toolsVersion,
                  identityResolver: identityResolver,
                  fileSystem: fileSystem,
                  diagnostics: diagnostics,
                  on: queue,
                  completion: completion)
    }

    public func load(
        at path: AbsolutePath,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        version: Version?,
        revision: String?,
        toolsVersion: ToolsVersion,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem,
        diagnostics: DiagnosticsEngine? = nil,
        on queue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        do {
            let manifestPath = try Manifest.path(atPackagePath: path, fileSystem: fileSystem)
            self.loadFile(at: manifestPath,
                          packageIdentity: packageIdentity,
                          packageKind: packageKind,
                          packageLocation: packageLocation,
                          version: version,
                          revision: revision,
                          toolsVersion: toolsVersion,
                          identityResolver: identityResolver,
                          fileSystem: fileSystem,
                          diagnostics: diagnostics,
                          on: queue,
                          completion: completion)
        } catch {
            return completion(.failure(error))
        }
    }

    private func loadFile(
        at path: AbsolutePath,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        version: Version?,
        revision: String?,
        toolsVersion: ToolsVersion,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem,
        diagnostics: DiagnosticsEngine? = nil,
        on queue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        self.operationQueue.addOperation {
            do {
                // Inform the delegate.
                queue.async {
                    self.delegate?.willLoad(manifest: path)
                }

                // Validate that the file exists.
                guard fileSystem.isFile(path) else {
                    throw PackageModel.Package.Error.noManifest(
                        at: path, version: version?.description)
                }

                // Get the JSON string for the manifest.
                let jsonString = try self.loadJSONString(
                    at: path,
                    packageIdentity: packageIdentity,
                    toolsVersion: toolsVersion,
                    fileSystem: fileSystem,
                    diagnostics: diagnostics
                )

                // Load the manifest from JSON.
                let parsedManifest = try ManifestJSONParser.parse(v4: jsonString,
                                                                  toolsVersion: toolsVersion,
                                                                  packageLocation: packageLocation,
                                                                  identityResolver: identityResolver,
                                                                  fileSystem: fileSystem)
                // Throw if we encountered any runtime errors.
                guard parsedManifest.errors.isEmpty else {
                    throw ManifestParseError.runtimeManifestErrors(parsedManifest.errors)
                }

                // Convert legacy system packages to the current target‐based model.
                var products = parsedManifest.products
                var targets = parsedManifest.targets
                if products.isEmpty, targets.isEmpty,
                    fileSystem.isFile(path.parentDirectory.appending(component: moduleMapFilename)) {
                        products.append(ProductDescription(
                        name: parsedManifest.name,
                        type: .library(.automatic),
                        targets: [parsedManifest.name])
                    )
                    targets.append(try TargetDescription(
                        name: parsedManifest.name,
                        path: "",
                        type: .system,
                        pkgConfig: parsedManifest.pkgConfig,
                        providers: parsedManifest.providers
                    ))
                }

                let manifest = Manifest(
                    name: parsedManifest.name,
                    path: path,
                    packageKind: packageKind,
                    packageLocation: packageLocation,
                    defaultLocalization: parsedManifest.defaultLocalization,
                    platforms: parsedManifest.platforms,
                    version: version,
                    revision: revision,
                    toolsVersion: toolsVersion,
                    pkgConfig: parsedManifest.pkgConfig,
                    providers: parsedManifest.providers,
                    cLanguageStandard: parsedManifest.cLanguageStandard,
                    cxxLanguageStandard: parsedManifest.cxxLanguageStandard,
                    swiftLanguageVersions: parsedManifest.swiftLanguageVersions,
                    dependencies: parsedManifest.dependencies,
                    products: products,
                    targets: targets
                )

                try self.validate(manifest, toolsVersion: toolsVersion, diagnostics: diagnostics)

                if let diagnostics = diagnostics, diagnostics.hasErrors {
                    throw Diagnostics.fatalError
                }

                queue.async {
                    completion(.success(manifest))
                }
            } catch {
                queue.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Validate the provided manifest.
    private func validate(_ manifest: Manifest, toolsVersion: ToolsVersion, diagnostics: DiagnosticsEngine?) throws {
        try self.validateTargets(manifest, diagnostics: diagnostics)
        try self.validateProducts(manifest, diagnostics: diagnostics)
        try self.validateDependencies(manifest, toolsVersion: toolsVersion, diagnostics: diagnostics)

        // Checks reserved for tools version 5.2 features
        if toolsVersion >= .v5_2 {
            try self.validateTargetDependencyReferences(manifest, diagnostics: diagnostics)
            try self.validateBinaryTargets(manifest, diagnostics: diagnostics)
        }
    }

    private func validateTargets(_ manifest: Manifest, diagnostics: DiagnosticsEngine?) throws {
        let duplicateTargetNames = manifest.targets.map({ $0.name }).spm_findDuplicates()
        for name in duplicateTargetNames {
            try diagnostics.emit(.duplicateTargetName(targetName: name))
        }
    }

    private func validateProducts(_ manifest: Manifest, diagnostics: DiagnosticsEngine?) throws {
        for product in manifest.products {
            // Check that the product contains targets.
            guard !product.targets.isEmpty else {
                try diagnostics.emit(.emptyProductTargets(productName: product.name))
                continue
            }

            // Check that the product references existing targets.
            for target in product.targets {
                if !manifest.targetMap.keys.contains(target) {
                    try diagnostics.emit(.productTargetNotFound(productName: product.name, targetName: target, validTargets: manifest.targetMap.keys.sorted()))
                }
            }

            // Check that products that reference only binary targets don't define a type.
            let areTargetsBinary = product.targets.allSatisfy { manifest.targetMap[$0]?.type == .binary }
            if areTargetsBinary && product.type != .library(.automatic) {
                try diagnostics.emit(.invalidBinaryProductType(productName: product.name))
            }
        }
    }

    private func validateDependencies(
        _ manifest: Manifest,
        toolsVersion: ToolsVersion,
        diagnostics: DiagnosticsEngine?
    ) throws {
        let dependenciesByIdentity = Dictionary(grouping: manifest.dependencies, by: { dependency in
            dependency.identity
        })

        let duplicateDependencyIdentities = dependenciesByIdentity
            .lazy
            .filter({ $0.value.count > 1 })
            .map({ $0.key })

        for identity in duplicateDependencyIdentities {
            try diagnostics.emit(.duplicateDependency(dependencyIdentity: identity))
        }

        if toolsVersion >= .v5_2 {
            let duplicateDependencies = try duplicateDependencyIdentities.flatMap{ identifier -> [PackageDependencyDescription] in
                guard let dependency = dependenciesByIdentity[identifier] else {
                    throw InternalError("unknown dependency \(identifier)")
                }
                return dependency
            }
            let duplicateDependencyNames = manifest.dependencies
                .lazy
                .filter({ !duplicateDependencies.contains($0) })
                .map({ $0.nameForTargetDependencyResolutionOnly })
                .spm_findDuplicates()

            for name in duplicateDependencyNames {
                try diagnostics.emit(.duplicateDependencyName(dependencyName: name))
            }
        }
    }

    private func validateBinaryTargets(_ manifest: Manifest, diagnostics: DiagnosticsEngine?) throws {
        // Check that binary targets point to the right file type.
        for target in manifest.targets where target.type == .binary {
            guard let location = URL(string: target.url ?? target.path ?? "") else {
                try diagnostics.emit(.invalidBinaryLocation(targetName: target.name))
                continue
            }

            let isRemote = target.url != nil
            let validSchemes = ["https"]
            if isRemote && (location.scheme.map({ !validSchemes.contains($0) }) ?? true) {
                try diagnostics.emit(.invalidBinaryURLScheme(
                    targetName: target.name,
                    validSchemes: validSchemes
                ))
            }

            let validExtensions = isRemote ? ["zip"] : BinaryTarget.Kind.allCases.map{ $0.fileExtension }
            if !validExtensions.contains(location.pathExtension) {
                try diagnostics.emit(.unsupportedBinaryLocationExtension(
                    targetName: target.name,
                    validExtensions: validExtensions
                ))
            }
        }
    }

    /// Validates that product target dependencies reference an existing package.
    private func validateTargetDependencyReferences(_ manifest: Manifest, diagnostics: DiagnosticsEngine?) throws {
        for target in manifest.targets {
            for targetDependency in target.dependencies {
                switch targetDependency {
                case .target:
                    // If this is a target dependency, we don't need to check anything.
                    break
                case .product(_, let packageName, _):
                    if manifest.packageDependency(referencedBy: targetDependency) == nil {
                        try diagnostics.emit(.unknownTargetPackageDependency(
                            packageName: packageName ?? "unknown package name",
                            targetName: target.name,
                            validPackages: manifest.dependencies.map { $0.nameForTargetDependencyResolutionOnly }
                        ))
                    }
                case .byName(let name, _):
                    // Don't diagnose root manifests so we can emit a better diagnostic during package loading.
                    if manifest.packageKind != .root &&
                       !manifest.targetMap.keys.contains(name) &&
                       manifest.packageDependency(referencedBy: targetDependency) == nil
                    {
                        try diagnostics.emit(.unknownTargetDependency(
                            dependency: name,
                            targetName: target.name,
                            validDependencies: manifest.dependencies.map { $0.nameForTargetDependencyResolutionOnly }
                        ))
                    }
                }
            }
        }
    }

    /// Load the JSON string for the given manifest.
    private func loadJSONString(
        at path: AbsolutePath,
        packageIdentity: PackageIdentity,
        toolsVersion: ToolsVersion,
        fileSystem: FileSystem,
        diagnostics: DiagnosticsEngine?
    ) throws -> String {

        let cacheKey = try ManifestCacheKey(
            packageIdentity: packageIdentity,
            manifestPath: path,
            toolsVersion: toolsVersion,
            env: ProcessEnv.vars,
            swiftpmVersion: SwiftVersion.currentVersion.displayString,
            fileSystem: fileSystem
        )

        let result = self.parseAndCacheManifest(key: cacheKey, diagnostics: diagnostics)
        // Throw now if we weren't able to parse the manifest.
        guard let parsedManifest = result.parsedManifest else {
            let errors = result.errorOutput ?? result.compilerOutput ?? "Unknown error parsing manifest for \(packageIdentity)"
            throw ManifestParseError.invalidManifestFormat(errors, diagnosticFile: result.diagnosticFile)
        }

        // We should not have any fatal error at this point.
        assert(result.errorOutput == nil)

        // We might have some non-fatal output (warnings/notes) from the compiler even when
        // we were able to parse the manifest successfully.
        if let compilerOutput = result.compilerOutput {
            // FIXME: Temporary workaround to filter out debug output from integrated Swift driver. [rdar://73710910]
            if !(compilerOutput.hasPrefix("<unknown>:0: remark: new Swift driver at") && compilerOutput.hasSuffix("will be used")) {
                diagnostics?.emit(.warning(ManifestLoadingDiagnostic(output: compilerOutput, diagnosticFile: result.diagnosticFile)))
            }
        }

        return parsedManifest
    }

    fileprivate func parseAndCacheManifest(key: ManifestCacheKey, diagnostics: DiagnosticsEngine?) -> ManifestParseResult {
        let cache = self.databaseCacheDir.map { cacheDir -> SQLiteManifestCache in
            let path = Self.manifestCacheDBPath(cacheDir)
            var configuration = SQLiteManifestCache.Configuration()
            // FIXME: expose as user-facing configuration
            configuration.maxSizeInMegabytes = 100
            configuration.truncateWhenFull = true
            return SQLiteManifestCache(location: .path(path), configuration: configuration, diagnosticsEngine: diagnostics)
        }

        // TODO: we could wrap the failure here with diagnostics if it wasn't optional throughout
        defer { try? cache?.close() }

        do {
            if let result = try cache?.get(key: key) {
                return result
            }
        } catch  {
            diagnostics?.emit(.warning("failed loading manifest for '\(key.packageIdentity)' from cache: \(error)"))
        }

        let result = self.parse(packageIdentity: key.packageIdentity,
                                manifestPath: key.manifestPath,
                                manifestContents: key.manifestContents,
                                toolsVersion: key.toolsVersion)

        // only cache successfully parsed manifests,
        // this is important for swift-pm development
        if !result.hasErrors {
            do {
                try cache?.put(key: key, manifest: result)
            } catch {
                diagnostics?.emit(.warning("failed storing manifest for '\(key.packageIdentity)' in cache: \(error)"))
            }
        }

        return result
    }

    internal struct ManifestCacheKey: Hashable {
        let packageIdentity: PackageIdentity
        let manifestPath: AbsolutePath
        let manifestContents: [UInt8]
        let toolsVersion: ToolsVersion
        let env: [String: String]
        let swiftpmVersion: String
        let sha256Checksum: String

        init (packageIdentity: PackageIdentity,
              manifestPath: AbsolutePath,
              toolsVersion: ToolsVersion,
              env: [String: String],
              swiftpmVersion: String,
              fileSystem: FileSystem
        ) throws {
            let manifestContents = try fileSystem.readFileContents(manifestPath).contents
            let sha256Checksum = try Self.computeSHA256Checksum(packageIdentity: packageIdentity, manifestContents: manifestContents, toolsVersion: toolsVersion, env: env, swiftpmVersion: swiftpmVersion)

            self.packageIdentity = packageIdentity
            self.manifestPath = manifestPath
            self.manifestContents = manifestContents
            self.toolsVersion = toolsVersion
            self.env = env
            self.swiftpmVersion = swiftpmVersion
            self.sha256Checksum = sha256Checksum
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(self.sha256Checksum)
        }

        private static func computeSHA256Checksum(
            packageIdentity: PackageIdentity,
            manifestContents: [UInt8],
            toolsVersion: ToolsVersion,
            env: [String: String],
            swiftpmVersion: String
        ) throws -> String {
            let stream = BufferedOutputByteStream()
            stream <<< packageIdentity
            stream <<< manifestContents
            stream <<< toolsVersion.description
            for key in env.keys.sorted(by: >) {
                stream <<< key <<< env[key]! // forced unwrap safe
            }
            stream <<< swiftpmVersion
            return stream.bytes.sha256Checksum
        }
    }

    internal struct ManifestParseResult: Codable {
        var hasErrors: Bool {
            return parsedManifest == nil
        }

        /// The path to the diagnostics file (.dia).
        ///
        /// This is only present if serialized diagnostics are enabled.
        var diagnosticFile: AbsolutePath?

        /// The output from compiler, if any.
        ///
        /// This would contain the errors and warnings produced when loading the manifest file.
        var compilerOutput: String?

        /// The parsed manifest in JSON format.
        var parsedManifest: String?

        /// Any non-compiler error that might have occurred during manifest loading.
        ///
        /// For e.g., we could have failed to spawn the process or create temporary file.
        var errorOutput: String? {
            didSet {
                assert(parsedManifest == nil)
            }
        }
    }

    /// Parse the manifest at the given path to JSON.
    fileprivate func parse(
        packageIdentity: PackageIdentity,
        manifestPath: AbsolutePath,
        manifestContents: [UInt8],
        toolsVersion: ToolsVersion
    ) -> ManifestParseResult {
        /// Helper method for parsing the manifest.
        func _parse(
            path manifestPath: AbsolutePath,
            toolsVersion: ToolsVersion,
            manifestParseResult: inout ManifestParseResult
        ) throws {
            self.delegate?.willParse(manifest: manifestPath)

            // The compiler has special meaning for files with extensions like .ll, .bc etc.
            // Assert that we only try to load files with extension .swift to avoid unexpected loading behavior.
            assert(manifestPath.extension == "swift",
                   "Manifest files must contain .swift suffix in their name, given: \(manifestPath).")

            // For now, we load the manifest by having Swift interpret it directly.
            // Eventually, we should have two loading processes, one that loads only
            // the declarative package specification using the Swift compiler directly
            // and validates it.

            // Compute the path to runtime we need to load.
            let runtimePath = self.runtimePath(for: toolsVersion)

            // FIXME: Workaround for the module cache bug that's been haunting Swift CI
            // <rdar://problem/48443680>
            let moduleCachePath = (ProcessEnv.vars["SWIFTPM_MODULECACHE_OVERRIDE"] ?? ProcessEnv.vars["SWIFTPM_TESTS_MODULECACHE"]).flatMap{ AbsolutePath.init($0) }

            var cmd: [String] = []
            cmd += [resources.swiftCompiler.pathString]
            cmd += verbosity.ccArgs

            let macOSPackageDescriptionPath: AbsolutePath
            // If we got the binDir that means we could be developing SwiftPM in Xcode
            // which produces a framework for dynamic package products.
            let packageFrameworkPath = runtimePath.appending(component: "PackageFrameworks")
            if resources.binDir != nil, localFileSystem.exists(packageFrameworkPath)  {
                cmd += [
                    "-F", packageFrameworkPath.pathString,
                    "-framework", "PackageDescription",
                    "-Xlinker", "-rpath", "-Xlinker", packageFrameworkPath.pathString,
                ]

                macOSPackageDescriptionPath = packageFrameworkPath.appending(RelativePath("PackageDescription.framework/PackageDescription"))
            } else {
                cmd += [
                    "-L", runtimePath.pathString,
                    "-lPackageDescription",
                ]
#if !os(Windows)
                // -rpath argument is not supported on Windows,
                // so we add runtimePath to PATH when executing the manifest instead
                cmd += ["-Xlinker", "-rpath", "-Xlinker", runtimePath.pathString]
#endif

                // note: this is not correct for all platforms, but we only actually use it on macOS.
                macOSPackageDescriptionPath = runtimePath.appending(RelativePath("libPackageDescription.dylib"))
            }

            // Use the same minimum deployment target as the PackageDescription library (with a fallback of 10.15).
            #if os(macOS)
            let triple = Self._hostTriple.memoize {
                Triple.getHostTriple(usingSwiftCompiler: resources.swiftCompiler)
            }

            let version = try Self._packageDescriptionMinimumDeploymentTarget.memoize {
                (try MinimumDeploymentTarget.computeMinimumDeploymentTarget(of: macOSPackageDescriptionPath, platform: .macOS))?.versionString ?? "10.15"
            }
            cmd += ["-target", "\(triple.tripleString(forPlatformVersion: version))"]
            #endif

            // Add any extra flags required as indicated by the ManifestLoader.
            cmd += resources.swiftCompilerFlags

            cmd += self.interpreterFlags(for: toolsVersion)
            if let moduleCachePath = moduleCachePath {
                cmd += ["-module-cache-path", moduleCachePath.pathString]
            }

            // Add the arguments for emitting serialized diagnostics, if requested.
            if self.serializedDiagnostics, let databaseCacheDir = self.databaseCacheDir {
                let diaDir = databaseCacheDir.appending(component: "ManifestLoading")
                let diagnosticFile = diaDir.appending(component: "\(packageIdentity).dia")
                try localFileSystem.createDirectory(diaDir, recursive: true)
                cmd += ["-Xfrontend", "-serialize-diagnostics-path", "-Xfrontend", diagnosticFile.pathString]
                manifestParseResult.diagnosticFile = diagnosticFile
            }

            cmd += [manifestPath.pathString]

            cmd += self.extraManifestFlags

            try withTemporaryDirectory(removeTreeOnDeinit: true) { tmpDir in
                // Set path to compiled manifest executable.
#if os(Windows)
                let executableSuffix = ".exe"
#else
                let executableSuffix = ""
#endif
                let compiledManifestFile = tmpDir.appending(component: "\(packageIdentity)-manifest\(executableSuffix)")
                cmd += ["-o", compiledManifestFile.pathString]

                // Compile the manifest.
                let compilerResult = try Process.popen(arguments: cmd)
                let compilerOutput = try (compilerResult.utf8Output() + compilerResult.utf8stderrOutput()).spm_chuzzle()
                manifestParseResult.compilerOutput = compilerOutput

                // Return now if there was an error.
                if compilerResult.exitStatus != .terminated(code: 0) {
                    return
                }

                // Pass an open file descriptor of a file to which the JSON representation of the manifest will be written.
                let jsonOutputFile = tmpDir.appending(component: "\(packageIdentity)-output.json")
                guard let jsonOutputFileDesc = fopen(jsonOutputFile.pathString, "w") else {
                    throw StringError("couldn't create the manifest's JSON output file")
                }

                cmd = [compiledManifestFile.pathString]
#if os(Windows)
                // NOTE: `_get_osfhandle` returns a non-owning, unsafe,
                // unretained HANDLE.  DO NOT invoke `CloseHandle` on `hFile`.
                let hFile: Int = _get_osfhandle(_fileno(jsonOutputFileDesc))
                cmd += ["-handle", "\(String(hFile, radix: 16))"]
#else
                cmd += ["-fileno", "\(fileno(jsonOutputFileDesc))"]
#endif
                // If enabled, run command in a sandbox.
                // This provides some safety against arbitrary code execution when parsing manifest files.
                // We only allow the permissions which are absolutely necessary.
                if isManifestSandboxEnabled {
                    let cacheDirectories = [self.databaseCacheDir, moduleCachePath].compactMap{ $0 }
                    let strictness: Sandbox.Strictness = toolsVersion < .v5_3 ? .manifest_pre_53 : .default
                    cmd = Sandbox.apply(command: cmd, writableDirectories: cacheDirectories, strictness: strictness)
                }

                // Run the compiled manifest.
                var environment = ProcessEnv.vars
#if os(Windows)
                let windowsPathComponent = runtimePath.pathString.replacingOccurrences(of: "/", with: "\\")
                environment["Path"] = "\(windowsPathComponent);\(environment["Path"] ?? "")"
#endif
                let runResult = try Process.popen(arguments: cmd, environment: environment)
                fclose(jsonOutputFileDesc)
                let runOutput = try (runResult.utf8Output() + runResult.utf8stderrOutput()).spm_chuzzle()
                if let runOutput = runOutput {
                    // Append the runtime output to any compiler output we've received.
                    manifestParseResult.compilerOutput = (manifestParseResult.compilerOutput ?? "") + runOutput
                }

                // Return now if there was an error.
                if runResult.exitStatus != .terminated(code: 0) {
                    manifestParseResult.errorOutput = runOutput
                    return
                }

                // Read the JSON output that was emitted by libPackageDescription.
                guard let jsonOutput = try localFileSystem.readFileContents(jsonOutputFile).validDescription else {
                    throw StringError("the manifest's JSON output has invalid encoding")
                }
                manifestParseResult.parsedManifest = jsonOutput
            }
        }

        var manifestParseResult = ManifestParseResult()
        do {
            if localFileSystem.isFile(manifestPath) {
                try _parse(
                    path: manifestPath,
                    toolsVersion: toolsVersion,
                    manifestParseResult: &manifestParseResult
                )
            } else {
                try withTemporaryFile(suffix: ".swift") { tempFile in
                    try localFileSystem.writeFileContents(tempFile.path, bytes: ByteString(manifestContents))
                    try _parse(
                        path: tempFile.path,
                        toolsVersion: toolsVersion,
                        manifestParseResult: &manifestParseResult
                    )
                }
            }
        } catch {
            assert(manifestParseResult.parsedManifest == nil)
            manifestParseResult.errorOutput = error.localizedDescription
        }

        return manifestParseResult
    }

    /// Returns path to the sdk, if possible.
    private func sdkRoot() -> AbsolutePath? {
        if let sdkRoot = self.sdkRootCache.get() {
            return sdkRoot
        }

        var sdkRootPath: AbsolutePath? = nil
        // Find SDKROOT on macOS using xcrun.
        #if os(macOS)
        let foundPath = try? Process.checkNonZeroExit(
            args: "/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path")
        guard let sdkRoot = foundPath?.spm_chomp(), !sdkRoot.isEmpty else {
            return nil
        }
        let path = AbsolutePath(sdkRoot)
        sdkRootPath = path
        self.sdkRootCache.put(path)
        #endif

        return sdkRootPath
    }

    /// Returns the interpreter flags for a manifest.
    public func interpreterFlags(
        for toolsVersion: ToolsVersion
    ) -> [String] {
        var cmd = [String]()
        let runtimePath = self.runtimePath(for: toolsVersion)
        cmd += ["-swift-version", toolsVersion.swiftLanguageVersion.rawValue]
        cmd += ["-I", runtimePath.pathString]
      #if os(macOS)
        if let sdkRoot = resources.sdkRoot ?? self.sdkRoot() {
            cmd += ["-sdk", sdkRoot.pathString]
        }
      #endif
        cmd += ["-package-description-version", toolsVersion.description]
        return cmd
    }

    /// Returns the runtime path given the manifest version and path to libDir.
    private func runtimePath(for version: ToolsVersion) -> AbsolutePath {
        // Bin dir will be set when developing swiftpm without building all of the runtimes.
        return resources.binDir ?? resources.libDir.appending(version.runtimeSubpath)
    }

    /// Returns path to the manifest database inside the given cache directory.
    private static func manifestCacheDBPath(_ cacheDir: AbsolutePath) -> AbsolutePath {
        return cacheDir.appending(component: "manifest.db")
    }

    /// reset internal cache
    public func resetCache() throws {
        // nothing needed at this point
    }

    /// reset internal state and purge shared cache
    public func purgeCache() throws {
        try self.resetCache()
        if let manifestCacheDBPath = self.databaseCacheDir.flatMap({ Self.manifestCacheDBPath($0) }) {
            try localFileSystem.removeFileTree(manifestCacheDBPath)
        }
    }
}

extension TSCBasic.Diagnostic.Message {
    static func duplicateTargetName(targetName: String) -> Self {
        .error("duplicate target named '\(targetName)'")
    }

    static func emptyProductTargets(productName: String) -> Self {
        .error("product '\(productName)' doesn't reference any targets")
    }

    static func productTargetNotFound(productName: String, targetName: String, validTargets: [String]) -> Self {
        .error("target '\(targetName)' referenced in product '\(productName)' could not be found; valid targets are: '\(validTargets.joined(separator: "', '"))'")
    }

    static func invalidBinaryProductType(productName: String) -> Self {
        .error("invalid type for binary product '\(productName)'; products referencing only binary targets must have a type of 'library'")
    }

    static func duplicateDependency(dependencyIdentity: PackageIdentity) -> Self {
        .error("duplicate dependency '\(dependencyIdentity)'")
    }

    static func duplicateDependencyName(dependencyName: String) -> Self {
        .error("duplicate dependency named '\(dependencyName)'; consider differentiating them using the 'name' argument")
    }

    static func unknownTargetDependency(dependency: String, targetName: String, validDependencies: [String]) -> Self {
        .error("unknown dependency '\(dependency)' in target '\(targetName)'; valid dependencies are: '\(validDependencies.joined(separator: "', '"))'")
    }

    static func unknownTargetPackageDependency(packageName: String, targetName: String, validPackages: [String]) -> Self {
        .error("unknown package '\(packageName)' in dependencies of target '\(targetName)'; valid packages are: '\(validPackages.joined(separator: "', '"))'")
    }

    static func invalidBinaryLocation(targetName: String) -> Self {
        .error("invalid location for binary target '\(targetName)'")
    }

    static func invalidBinaryURLScheme(targetName: String, validSchemes: [String]) -> Self {
        .error("invalid URL scheme for binary target '\(targetName)'; valid schemes are: '\(validSchemes.joined(separator: "', '"))'")
    }

    static func unsupportedBinaryLocationExtension(targetName: String, validExtensions: [String]) -> Self {
        .error("unsupported extension for binary target '\(targetName)'; valid extensions are: '\(validExtensions.joined(separator: "', '"))'")
    }

    static func invalidLanguageTag(_ languageTag: String) -> Self {
        .error("""
            invalid language tag '\(languageTag)'; the pattern for language tags is groups of latin characters and \
            digits separated by hyphens
            """)
    }
}

/// SQLite backed persistent cache.
internal final class SQLiteManifestCache: Closable {
    let fileSystem: FileSystem
    let location: SQLite.Location
    let configuration: Configuration

    private var state = State.idle
    private let stateLock = Lock()

    private let diagnosticsEngine: DiagnosticsEngine?
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    init(location: SQLite.Location, configuration: Configuration = .init(), diagnosticsEngine: DiagnosticsEngine? = nil) {
        self.location = location
        switch self.location {
        case .path, .temporary:
            self.fileSystem = localFileSystem
        case .memory:
            self.fileSystem = InMemoryFileSystem()
        }
        self.configuration = configuration
        self.diagnosticsEngine = diagnosticsEngine
        self.jsonEncoder = JSONEncoder.makeWithDefaults()
        self.jsonDecoder = JSONDecoder.makeWithDefaults()
    }

    convenience init(path: AbsolutePath, configuration: Configuration = .init(), diagnosticsEngine: DiagnosticsEngine? = nil) {
        self.init(location: .path(path), configuration: configuration, diagnosticsEngine: diagnosticsEngine)
    }

    deinit {
        // TODO: we could wrap the failure here with diagnostics if it wasn't optional throughout
        try? self.withStateLock {
            if case .connected(let db) = self.state {
                assertionFailure("db should be closed")
                try db.close()
            }
        }
    }

    func close() throws {
        try self.withStateLock {
            if case .connected(let db) = self.state {
                try db.close()
            }
            self.state = .disconnected
        }
    }

    func put(key: ManifestLoader.ManifestCacheKey, manifest: ManifestLoader.ManifestParseResult) throws {
        do {
            let query = "INSERT OR IGNORE INTO MANIFEST_CACHE VALUES (?, ?);"
            try self.executeStatement(query) { statement -> Void in
                let data = try self.jsonEncoder.encode(manifest)
                let bindings: [SQLite.SQLiteValue] = [
                    .string(key.sha256Checksum),
                    .blob(data),
                ]
                try statement.bind(bindings)
                try statement.step()
            }
        } catch (let error as SQLite.Errors) where error == .databaseFull {
            if !self.configuration.truncateWhenFull {
                throw error
            }
            self.diagnosticsEngine?.emit(.warning("truncating manifest cache database since it reached max size of \(self.configuration.maxSizeInBytes ?? 0) bytes"))
            try self.executeStatement("DELETE FROM MANIFEST_CACHE;") { statement -> Void in
                try statement.step()
            }
            try self.put(key: key, manifest: manifest)
        } catch {
            throw error
        }
    }

    func get(key: ManifestLoader.ManifestCacheKey) throws -> ManifestLoader.ManifestParseResult? {
        let query = "SELECT value FROM MANIFEST_CACHE WHERE key == ? LIMIT 1;"
        return try self.executeStatement(query) { statement ->  ManifestLoader.ManifestParseResult? in
            try statement.bind([.string(key.sha256Checksum)])
            let data = try statement.step()?.blob(at: 0)
            return try data.flatMap {
                try self.jsonDecoder.decode(ManifestLoader.ManifestParseResult.self, from: $0)
            }
        }
    }

    private func executeStatement<T>(_ query: String, _ body: (SQLite.PreparedStatement) throws -> T) throws -> T {
        try self.withDB { db in
            let result: Result<T, Error>
            let statement = try db.prepare(query: query)
            do {
                result = .success(try body(statement))
            } catch {
                result = .failure(error)
            }
            try statement.finalize()
            switch result {
            case .failure(let error):
                throw error
            case .success(let value):
                return value
            }
        }
    }

    private func withDB<T>(_ body: (SQLite) throws -> T) throws -> T {
        let createDB = { () throws -> SQLite in
            let db = try SQLite(location: self.location, configuration: self.configuration.underlying)
            try self.createSchemaIfNecessary(db: db)
            return db
        }

        let db = try self.withStateLock { () -> SQLite in
            let db: SQLite
            switch (self.location, self.state) {
            case (.path(let path), .connected(let database)):
                if self.fileSystem.exists(path) {
                    db = database
                } else {
                    try database.close()
                    try self.fileSystem.createDirectory(path.parentDirectory, recursive: true)
                    db = try createDB()
                }
            case (.path(let path), _):
                if !self.fileSystem.exists(path) {
                    try self.fileSystem.createDirectory(path.parentDirectory, recursive: true)
                }
                db = try createDB()
            case (_, .connected(let database)):
                db = database
            case (_, _):
                db = try createDB()
            }
            self.state = .connected(db)
            return db
        }

        // FIXME: workaround linux sqlite concurrency issues causing CI failures
        #if os(Linux)
        return try self.withStateLock {
            return try body(db)
        }
        #else
        return try body(db)
        #endif
    }

    private func createSchemaIfNecessary(db: SQLite) throws {
        let table = """
            CREATE TABLE IF NOT EXISTS MANIFEST_CACHE (
                key STRING PRIMARY KEY NOT NULL,
                value BLOB NOT NULL
            );
        """

        try db.exec(query: table)
        try db.exec(query: "PRAGMA journal_mode=WAL;")
    }

    private func withStateLock<T>(_ body: () throws -> T) throws -> T {
        switch self.location {
        case .path(let path):
            if !self.fileSystem.exists(path.parentDirectory) {
                try self.fileSystem.createDirectory(path.parentDirectory)
            }
            return try self.fileSystem.withLock(on: path, type: .exclusive, body)
        case .memory, .temporary:
            return try self.stateLock.withLock(body)
        }
    }

    private enum State {
        case idle
        case connected(SQLite)
        case disconnected
    }

    struct Configuration {
        var truncateWhenFull: Bool

        fileprivate var underlying: SQLite.Configuration

        init() {
            self.underlying = .init()
            self.truncateWhenFull = true
            self.maxSizeInMegabytes = 100
            // see https://www.sqlite.org/c3ref/busy_timeout.html
            self.busyTimeoutMilliseconds = 1_000
        }

        var maxSizeInMegabytes: Int? {
            get {
                self.underlying.maxSizeInMegabytes
            }
            set {
                self.underlying.maxSizeInMegabytes = newValue
            }
        }

        var maxSizeInBytes: Int? {
            get {
                self.underlying.maxSizeInBytes
            }
            set {
                self.underlying.maxSizeInBytes = newValue
            }
        }

        var busyTimeoutMilliseconds: Int32 {
            get {
                self.underlying.busyTimeoutMilliseconds
            }
            set {
                self.underlying.busyTimeoutMilliseconds = newValue
            }
        }
    }
}
