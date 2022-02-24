/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import Foundation
import PackageModel
import TSCBasic
import struct TSCUtility.Triple
import enum TSCUtility.Diagnostics
import var TSCUtility.verbosity

public enum ManifestParseError: Swift.Error, Equatable {
    /// The manifest contains invalid format.
    case invalidManifestFormat(String, diagnosticFile: AbsolutePath?)

    /// The manifest was successfully loaded by swift interpreter but there were runtime issues.
    case runtimeManifestErrors([String])
}

// used to output the errors via the observability system
extension ManifestParseError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidManifestFormat(let error, _):
            return "Invalid manifest\n\(error)"
        case .runtimeManifestErrors(let errors):
            return "Invalid manifest (evaluation failed)\n\(errors.joined(separator: "\n"))"
        }
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
    ///   - fileSystem: File system to load from.
    ///   - observabilityScope: Observability scope to emit diagnostics.
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
        observabilityScope: ObservabilityScope,
        on queue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    )

    /// Reset any internal cache held by the manifest loader.
    func resetCache() throws

    /// Reset any internal cache held by the manifest loader and purge any entries in a shared cache
    func purgeCache() throws
}

public extension ManifestLoaderProtocol {
    var supportedArchiveExtensions: [String] { ["zip"] }
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

    private let toolchain: ToolchainConfiguration
    private let serializedDiagnostics: Bool
    private let isManifestSandboxEnabled: Bool
    private let delegate: ManifestLoaderDelegate?
    private let extraManifestFlags: [String]

    private let databaseCacheDir: AbsolutePath?

    private let sdkRootCache = ThreadSafeBox<AbsolutePath>()

    private let concurrencySemaphore: DispatchSemaphore

    public init(
        toolchain: ToolchainConfiguration,
        serializedDiagnostics: Bool = false,
        isManifestSandboxEnabled: Bool = true,
        cacheDir: AbsolutePath? = nil,
        delegate: ManifestLoaderDelegate? = nil,
        extraManifestFlags: [String] = []
    ) {
        self.toolchain = toolchain
        self.serializedDiagnostics = serializedDiagnostics
        self.isManifestSandboxEnabled = isManifestSandboxEnabled
        self.delegate = delegate
        self.extraManifestFlags = extraManifestFlags

        self.databaseCacheDir = cacheDir.map(resolveSymlinks)

        self.concurrencySemaphore = DispatchSemaphore(value: Concurrency.maxOperations)
    }

    // deprecated 8/2021
    @available(*, deprecated, message: "use non-deprecated constructor instead")
    public convenience init(
        manifestResources: ToolchainConfiguration,
        serializedDiagnostics: Bool = false,
        isManifestSandboxEnabled: Bool = true,
        cacheDir: AbsolutePath? = nil,
        delegate: ManifestLoaderDelegate? = nil,
        extraManifestFlags: [String] = []
    ) {
        self.init(
            toolchain: manifestResources,
            serializedDiagnostics: serializedDiagnostics,
            isManifestSandboxEnabled: isManifestSandboxEnabled,
            cacheDir: cacheDir,
            delegate: delegate,
            extraManifestFlags: extraManifestFlags
        )
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
    // deprecated 8/2021
    @available(*, deprecated, message: "use workspace API instead")
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
            let toolchain = ToolchainConfiguration(swiftCompiler: swiftCompiler, swiftCompilerFlags: swiftCompilerFlags)
            let loader = ManifestLoader(toolchain: toolchain)
            let toolsVersion = try ToolsVersionLoader().load(at: path, fileSystem: fileSystem)
            let packageLocation = fileSystem.isFile(path) ? path.parentDirectory : path
            let packageIdentity = try identityResolver.resolveIdentity(for: packageLocation)
            loader.load(
                at: path,
                packageIdentity: packageIdentity,
                packageKind: .root(packageLocation),
                packageLocation: packageLocation.pathString,
                version: nil,
                revision: nil,
                toolsVersion: toolsVersion,
                identityResolver: identityResolver,
                fileSystem: fileSystem,
                observabilityScope: ObservabilitySystem(diagnosticEngine: diagnostics ?? DiagnosticsEngine()).topScope,
                on: queue,
                completion: completion
            )
        } catch {
            return completion(.failure(error))
        }
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
        observabilityScope: ObservabilityScope,
        on queue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        do {
            let manifestPath = try Manifest.path(atPackagePath: path, fileSystem: fileSystem)
            self.loadFile(
                at: manifestPath,
                packageIdentity: packageIdentity,
                packageKind: packageKind,
                packageLocation: packageLocation,
                version: version,
                revision: revision,
                toolsVersion: toolsVersion,
                identityResolver: identityResolver,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope,
                on: queue,
                completion: completion
            )
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
        observabilityScope: ObservabilityScope,
        on queue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        // Inform the delegate.
        queue.async {
            self.delegate?.willLoad(manifest: path)
        }

        // Validate that the file exists.
        guard fileSystem.isFile(path) else {
            return completion(.failure(PackageModel.Package.Error.noManifest(at: path, version: version?.description)))
        }

        // wrap completion handler for concurrency control
        let completion = { (result: Result<Manifest, Error>) in
            self.concurrencySemaphore.signal()
            queue.async {
                completion(result)
            }
        }
        // concurrency control
        self.concurrencySemaphore.wait()
        self.parseAndCacheManifest(
            at: path,
            packageIdentity: packageIdentity,
            packageKind: packageKind,
            version: version,
            toolsVersion: toolsVersion,
            identityResolver: identityResolver,
            delegateQueue: queue,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        ) { parseResult in
            do {
                let parsedManifest = try parseResult.get()
                // Convert legacy system packages to the current target‐based model.
                var products = parsedManifest.products
                var targets = parsedManifest.targets
                if products.isEmpty, targets.isEmpty,
                   fileSystem.isFile(path.parentDirectory.appending(component: moduleMapFilename)) {
                    try products.append(ProductDescription(
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
                    displayName: parsedManifest.name,
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

                try self.validate(manifest, toolsVersion: toolsVersion, observabilityScope: observabilityScope)

                if observabilityScope.errorsReported {
                    throw Diagnostics.fatalError
                }

                completion(.success(manifest))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Validate the provided manifest.
    private func validate(_ manifest: Manifest, toolsVersion: ToolsVersion, observabilityScope: ObservabilityScope) throws {
        try self.validateTargets(manifest, observabilityScope: observabilityScope)
        try self.validateProducts(manifest, observabilityScope: observabilityScope)
        try self.validateDependencies(manifest, toolsVersion: toolsVersion, observabilityScope: observabilityScope)

        // Checks reserved for tools version 5.2 features
        if toolsVersion >= .v5_2 {
            try self.validateTargetDependencyReferences(manifest, observabilityScope: observabilityScope)
            try self.validateBinaryTargets(manifest, observabilityScope: observabilityScope)
        }
    }

    private func validateTargets(_ manifest: Manifest, observabilityScope: ObservabilityScope) throws {
        let duplicateTargetNames = manifest.targets.map({ $0.name }).spm_findDuplicates()
        for name in duplicateTargetNames {
            observabilityScope.emit(.duplicateTargetName(targetName: name))
        }
    }

    private func validateProducts(_ manifest: Manifest, observabilityScope: ObservabilityScope) throws {
        for product in manifest.products {
            // Check that the product contains targets.
            guard !product.targets.isEmpty else {
                observabilityScope.emit(.emptyProductTargets(productName: product.name))
                continue
            }

            // Check that the product references existing targets.
            for target in product.targets {
                if !manifest.targetMap.keys.contains(target) {
                    observabilityScope.emit(.productTargetNotFound(productName: product.name, targetName: target, validTargets: manifest.targetMap.keys.sorted()))
                }
            }

            // Check that products that reference only binary targets don't define a type.
            let areTargetsBinary = product.targets.allSatisfy { manifest.targetMap[$0]?.type == .binary }
            if areTargetsBinary && product.type != .library(.automatic) {
                observabilityScope.emit(.invalidBinaryProductType(productName: product.name))
            }
        }
    }

    private func validateDependencies(
        _ manifest: Manifest,
        toolsVersion: ToolsVersion,
        observabilityScope: ObservabilityScope
    ) throws {
        let dependenciesByIdentity = Dictionary(grouping: manifest.dependencies, by: { dependency in
            dependency.identity
        })

        let duplicateDependencyIdentities = dependenciesByIdentity
            .lazy
            .filter({ $0.value.count > 1 })
            .map({ $0.key })

        for identity in duplicateDependencyIdentities {
            observabilityScope.emit(.duplicateDependency(dependencyIdentity: identity))
        }

        if toolsVersion >= .v5_2 {
            let duplicateDependencies = try duplicateDependencyIdentities.flatMap{ identifier -> [PackageDependency] in
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
                observabilityScope.emit(.duplicateDependencyName(dependencyName: name))
            }
        }
    }

    private func validateBinaryTargets(_ manifest: Manifest, observabilityScope: ObservabilityScope) throws {
        // Check that binary targets point to the right file type.
        for target in manifest.targets where target.type == .binary {
            if target.isLocal {
                guard let path = target.path else {
                    observabilityScope.emit(.invalidBinaryLocation(targetName: target.name))
                    continue
                }

                guard let path = path.spm_chuzzle(), !path.isEmpty else {
                    observabilityScope.emit(.invalidLocalBinaryPath(path: path, targetName: target.name))
                    continue
                }

                guard let relativePath = try? RelativePath(validating: path) else {
                    observabilityScope.emit(.invalidLocalBinaryPath(path: path, targetName: target.name))
                    continue
                }

                let validExtensions = self.supportedArchiveExtensions + BinaryTarget.Kind.allCases.filter{ $0 != .unknown }.map { $0.fileExtension }
                guard let fileExtension = relativePath.extension, validExtensions.contains(fileExtension) else {
                    observabilityScope.emit(.unsupportedBinaryLocationExtension(
                        targetName: target.name,
                        validExtensions: validExtensions
                    ))
                    continue
                }
            } else if target.isRemote {
                guard let url = target.url else {
                    observabilityScope.emit(.invalidBinaryLocation(targetName: target.name))
                    continue
                }

                guard let url = url.spm_chuzzle(), !url.isEmpty else {
                    observabilityScope.emit(.invalidBinaryURL(url: url, targetName: target.name))
                    continue
                }

                guard let url = URL(string: url) else {
                    observabilityScope.emit(.invalidBinaryURL(url: url, targetName: target.name))
                    continue
                }

                let validSchemes = ["https"]
                guard url.scheme.map({ validSchemes.contains($0) }) ?? false else {
                    observabilityScope.emit(.invalidBinaryURLScheme(
                        targetName: target.name,
                        validSchemes: validSchemes
                    ))
                    continue
                }

                guard self.supportedArchiveExtensions.contains(url.pathExtension) else {
                    observabilityScope.emit(.unsupportedBinaryLocationExtension(
                        targetName: target.name,
                        validExtensions: self.supportedArchiveExtensions
                    ))
                    continue
                }

            } else {
                observabilityScope.emit(.invalidBinaryLocation(targetName: target.name))
                continue
            }


        }
    }

    /// Validates that product target dependencies reference an existing package.
    private func validateTargetDependencyReferences(_ manifest: Manifest, observabilityScope: ObservabilityScope) throws {
        for target in manifest.targets {
            for targetDependency in target.dependencies {
                switch targetDependency {
                case .target:
                    // If this is a target dependency, we don't need to check anything.
                    break
                case .product(_, let packageName, _, _):
                    if manifest.packageDependency(referencedBy: targetDependency) == nil {
                        observabilityScope.emit(.unknownTargetPackageDependency(
                            packageName: packageName ?? "unknown package name",
                            targetName: target.name,
                            validPackages: manifest.dependencies.map { $0.nameForTargetDependencyResolutionOnly }
                        ))
                    }
                case .byName(let name, _):
                    // Don't diagnose root manifests so we can emit a better diagnostic during package loading.
                    if !manifest.packageKind.isRoot &&
                       !manifest.targetMap.keys.contains(name) &&
                       manifest.packageDependency(referencedBy: targetDependency) == nil
                    {
                        observabilityScope.emit(.unknownTargetDependency(
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
    private func parseManifest(
        _ result: EvaluationResult,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        toolsVersion: ToolsVersion,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws -> ManifestJSONParser.Result {
        // Throw now if we weren't able to parse the manifest.
        guard let manifestJSON = result.manifestJSON, !manifestJSON.isEmpty else {
            let errors = result.errorOutput ?? result.compilerOutput ?? "Missing or empty JSON output from manifest compilation for \(packageIdentity)"
            throw ManifestParseError.invalidManifestFormat(errors, diagnosticFile: result.diagnosticFile)
        }

        // We should not have any fatal error at this point.
        guard result.errorOutput == nil else {
            throw InternalError("unexpected error output: \(result.errorOutput!)")
        }

        // We might have some non-fatal output (warnings/notes) from the compiler even when
        // we were able to parse the manifest successfully.
        if let compilerOutput = result.compilerOutput {
            // FIXME: Temporary workaround to filter out debug output from integrated Swift driver. [rdar://73710910]
            if !(compilerOutput.hasPrefix("<unknown>:0: remark: new Swift driver at") && compilerOutput.hasSuffix("will be used")) {
                let metadata = result.diagnosticFile.map { diagnosticFile -> ObservabilityMetadata in
                    var metadata = ObservabilityMetadata()
                    metadata.manifestLoadingDiagnosticFile = diagnosticFile
                    return metadata
                }
                observabilityScope.emit(warning: compilerOutput, metadata: metadata)

                // FIXME: (diagnostics) deprecate in favor of the metadata version ^^ when transitioning manifest loader to Observability APIs
                //observabilityScope.emit(.warning(ManifestLoadingDiagnostic(output: compilerOutput, diagnosticFile: result.diagnosticFile)))
            }
        }

        return try ManifestJSONParser.parse(
            v4: manifestJSON,
            toolsVersion: toolsVersion,
            packageKind: packageKind,
            identityResolver: identityResolver,
            fileSystem: fileSystem
        )
    }

    /// Represents behavior that can be deferred until a more appropriate time.
    internal struct DelayableAction<T> {
        var target: T?
        var action: ((T) -> Void)?

        func perform() {
            if let value = target, let cleanup = action {
                cleanup(value)
            }
        }

        mutating func delay() -> DelayableAction {
            let next = DelayableAction(target: target, action: action)
            target = nil
            action = nil
            return next
        }
    }

    private func parseAndCacheManifest(
        at path: AbsolutePath,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        version: Version?,
        toolsVersion: ToolsVersion,
        identityResolver: IdentityResolver,
        delegateQueue: DispatchQueue,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        completion: @escaping (Result<ManifestJSONParser.Result, Error>) -> Void
    ) {
        let cache = self.databaseCacheDir.map { cacheDir -> SQLiteBackedCache<EvaluationResult> in
            let path = Self.manifestCacheDBPath(cacheDir)
            var configuration = SQLiteBackedCacheConfiguration()
            // FIXME: expose as user-facing configuration
            configuration.maxSizeInMegabytes = 100
            configuration.truncateWhenFull = true
            return SQLiteBackedCache<EvaluationResult>(
                tableName: "MANIFEST_CACHE",
                location: .path(path),
                configuration: configuration
            )
        }

        var closeAfterRead = DelayableAction(target: cache) { cache in
            do {
                try cache.close()
            } catch {
                observabilityScope.emit(warning: "failed closing cache: \(error)")
            }
        }
        defer { closeAfterRead.perform() }

        let key : CacheKey
        do {
            key = try CacheKey(
                packageIdentity: packageIdentity,
                manifestPath: path,
                toolsVersion: toolsVersion,
                env: ProcessEnv.vars,
                swiftpmVersion: SwiftVersion.currentVersion.displayString,
                fileSystem: fileSystem
            )
        } catch {
            return completion(.failure(error))
        }

        do {
            // try to get it from the cache
            if let result = try cache?.get(key: key.sha256Checksum), let manifestJSON = result.manifestJSON, !manifestJSON.isEmpty {
                observabilityScope.emit(debug: "loading manifest for '\(packageIdentity)' v. \(version?.description ?? "unknown") from cache")
                return completion(.success(try self.parseManifest(
                    result,
                    packageIdentity: packageIdentity,
                    packageKind: packageKind,
                    toolsVersion: toolsVersion,
                    identityResolver: identityResolver,
                    fileSystem: fileSystem,
                    observabilityScope: observabilityScope
                )))
            }
        } catch {
            observabilityScope.emit(warning: "failed loading cached manifest for '\(key.packageIdentity)': \(error)")
        }

        // delay closing cache until after write.
        let closeAfterWrite = closeAfterRead.delay()

        // shells out and compiles the manifest, finally output a JSON
        observabilityScope.emit(debug: "evaluating manifest for '\(packageIdentity)' v. \(version?.description ?? "unknown") ")
        self.evaluateManifest(
            packageIdentity: key.packageIdentity,
            manifestPath: key.manifestPath,
            manifestContents: key.manifestContents,
            toolsVersion: key.toolsVersion,
            delegateQueue: delegateQueue
        ) { result in
            do {
                defer { closeAfterWrite.perform() }
                
                let evaluationResult = try result.get()
                // only cache successfully parsed manifests
                let parseManifest = try self.parseManifest(
                    evaluationResult,
                    packageIdentity: packageIdentity,
                    packageKind: packageKind,
                    toolsVersion: toolsVersion,
                    identityResolver: identityResolver,
                    fileSystem: fileSystem,
                    observabilityScope: observabilityScope
                )

                do {
                    // FIXME: (diagnostics) pass in observability scope when we have one
                    try cache?.put(key: key.sha256Checksum, value: evaluationResult)
                } catch {
                    observabilityScope.emit(warning: "failed storing manifest for '\(key.packageIdentity)' in cache: \(error)")
                }

                completion(.success(parseManifest))
            } catch {
                completion(.failure(error))
            }
        }
    }

    internal struct CacheKey: Hashable {
        let packageIdentity: PackageIdentity
        let manifestPath: AbsolutePath
        let manifestContents: [UInt8]
        let toolsVersion: ToolsVersion
        let env: EnvironmentVariables
        let swiftpmVersion: String
        let sha256Checksum: String

        init (packageIdentity: PackageIdentity,
              manifestPath: AbsolutePath,
              toolsVersion: ToolsVersion,
              env: EnvironmentVariables,
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
            env: EnvironmentVariables,
            swiftpmVersion: String
        ) throws -> String {
            let stream = BufferedOutputByteStream()
            stream <<< packageIdentity
            stream <<< manifestContents
            stream <<< toolsVersion.description
            for (key, value) in env.sorted(by: { $0.key > $1.key }) {
                stream <<< key <<< value
            }
            stream <<< swiftpmVersion
            return stream.bytes.sha256Checksum
        }
    }

    internal struct EvaluationResult: Codable {
        /// The path to the diagnostics file (.dia).
        ///
        /// This is only present if serialized diagnostics are enabled.
        var diagnosticFile: AbsolutePath?

        /// The output from compiler, if any.
        ///
        /// This would contain the errors and warnings produced when loading the manifest file.
        var compilerOutput: String?

        /// The manifest in JSON format.
        var manifestJSON: String?

        /// Any non-compiler error that might have occurred during manifest loading.
        ///
        /// For e.g., we could have failed to spawn the process or create temporary file.
        var errorOutput: String? {
            didSet {
                assert(self.manifestJSON == nil)
            }
        }

        var hasErrors: Bool {
            return self.manifestJSON == nil
        }
    }

    /// Compiler the manifest at the given path and retrieve the JSON.
    fileprivate func evaluateManifest(
        packageIdentity: PackageIdentity,
        manifestPath: AbsolutePath,
        manifestContents: [UInt8],
        toolsVersion: ToolsVersion,
        delegateQueue: DispatchQueue,
        completion: @escaping (Result<EvaluationResult, Error>) -> Void
    ) {
        do {
            if localFileSystem.isFile(manifestPath) {
                self.evaluateManifest(
                    at: manifestPath,
                    packageIdentity: packageIdentity,
                    toolsVersion: toolsVersion,
                    delegateQueue:  delegateQueue,
                    completion: completion
                )
            } else {
                try withTemporaryFile(suffix: ".swift") { tempFile, cleanupTempFile in
                    try localFileSystem.writeFileContents(tempFile.path, bytes: ByteString(manifestContents))
                    self.evaluateManifest(
                        at: tempFile.path,
                        packageIdentity: packageIdentity,
                        toolsVersion: toolsVersion,
                        delegateQueue: delegateQueue
                    ) { result in
                        cleanupTempFile(tempFile)
                        completion(result)
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    /// Helper method for evaluating the manifest.
    func evaluateManifest(
        at manifestPath: AbsolutePath,
        packageIdentity: PackageIdentity,
        toolsVersion: ToolsVersion,
        delegateQueue: DispatchQueue,
        completion: @escaping (Result<EvaluationResult, Error>) -> Void
    ) {
        // The compiler has special meaning for files with extensions like .ll, .bc etc.
        // Assert that we only try to load files with extension .swift to avoid unexpected loading behavior.
        guard manifestPath.extension == "swift" else {
            return completion(.failure(InternalError("Manifest files must contain .swift suffix in their name, given: \(manifestPath).")))
        }

        var evaluationResult = EvaluationResult()

        delegateQueue.async {
            self.delegate?.willParse(manifest: manifestPath)
        }

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
        cmd += [self.toolchain.swiftCompilerPath.pathString]

        let macOSPackageDescriptionPath: AbsolutePath
        // if runtimePath is set to "PackageFrameworks" that means we could be developing SwiftPM in Xcode
        // which produces a framework for dynamic package products.
        if runtimePath.extension == "framework" {
            cmd += [
                "-F", runtimePath.parentDirectory.pathString,
                "-framework", "PackageDescription",
                "-Xlinker", "-rpath", "-Xlinker", runtimePath.parentDirectory.pathString,
            ]

            macOSPackageDescriptionPath = runtimePath.appending(component: "PackageDescription")
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
            macOSPackageDescriptionPath = runtimePath.appending(component: "libPackageDescription.dylib")
        }

        // Use the same minimum deployment target as the PackageDescription library (with a fallback of 10.15).
#if os(macOS)
        let triple = Self._hostTriple.memoize {
            Triple.getHostTriple(usingSwiftCompiler: self.toolchain.swiftCompilerPath)
        }

        do {
            let version = try Self._packageDescriptionMinimumDeploymentTarget.memoize {
                (try MinimumDeploymentTarget.computeMinimumDeploymentTarget(of: macOSPackageDescriptionPath, platform: .macOS))?.versionString ?? "10.15"
            }
            cmd += ["-target", "\(triple.tripleString(forPlatformVersion: version))"]
        } catch {
            return completion(.failure(error))
        }
#endif

        // Add any extra flags required as indicated by the ManifestLoader.
        cmd += self.toolchain.swiftCompilerFlags

        cmd += self.interpreterFlags(for: toolsVersion)
        if let moduleCachePath = moduleCachePath {
            cmd += ["-module-cache-path", moduleCachePath.pathString]
        }

        // Add the arguments for emitting serialized diagnostics, if requested.
        if self.serializedDiagnostics, let databaseCacheDir = self.databaseCacheDir {
            let diaDir = databaseCacheDir.appending(component: "ManifestLoading")
            let diagnosticFile = diaDir.appending(component: "\(packageIdentity).dia")
            do {
                try localFileSystem.createDirectory(diaDir, recursive: true)
                cmd += ["-Xfrontend", "-serialize-diagnostics-path", "-Xfrontend", diagnosticFile.pathString]
                evaluationResult.diagnosticFile = diagnosticFile
            } catch {
                return completion(.failure(error))
            }
        }

        cmd += [manifestPath.pathString]

        cmd += self.extraManifestFlags

        do {
            try withTemporaryDirectory { tmpDir, cleanupTmpDir in
                // Set path to compiled manifest executable.
    #if os(Windows)
                let executableSuffix = ".exe"
    #else
                let executableSuffix = ""
    #endif
                let compiledManifestFile = tmpDir.appending(component: "\(packageIdentity)-manifest\(executableSuffix)")
                cmd += ["-o", compiledManifestFile.pathString]

                // Compile the manifest.
                Process.popen(arguments: cmd, environment: toolchain.swiftCompilerEnvironment, queue: delegateQueue) { result in
                    var cleanupIfError = DelayableAction(target: tmpDir, action: cleanupTmpDir)
                    defer { cleanupIfError.perform() }

                    let compilerResult : ProcessResult
                    do {
                        compilerResult = try result.get()
                        evaluationResult.compilerOutput = try (compilerResult.utf8Output() + compilerResult.utf8stderrOutput()).spm_chuzzle()
                    } catch {
                        return completion(.failure(error))
                    }

                    // Return now if there was an error.
                    if compilerResult.exitStatus != .terminated(code: 0) {
                        return completion(.success(evaluationResult))
                    }

                    // Pass an open file descriptor of a file to which the JSON representation of the manifest will be written.
                    let jsonOutputFile = tmpDir.appending(component: "\(packageIdentity)-output.json")
                    guard let jsonOutputFileDesc = fopen(jsonOutputFile.pathString, "w") else {
                        return completion(.failure(StringError("couldn't create the manifest's JSON output file")))
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

                    do {
                        let packageDirectory = manifestPath.parentDirectory.pathString
                        let contextModel = ContextModel(packageDirectory: packageDirectory)
                        cmd += ["-context", try contextModel.encode()]
                    } catch {
                        return completion(.failure(error))
                    }

                    // If enabled, run command in a sandbox.
                    // This provides some safety against arbitrary code execution when parsing manifest files.
                    // We only allow the permissions which are absolutely necessary.
                    if self.isManifestSandboxEnabled {
                        let cacheDirectories = [self.databaseCacheDir, moduleCachePath].compactMap{ $0 }
                        let strictness: Sandbox.Strictness = toolsVersion < .v5_3 ? .manifest_pre_53 : .default
                        cmd = Sandbox.apply(command: cmd, strictness: strictness, writableDirectories: cacheDirectories)
                    }

                    // Run the compiled manifest.
                    var environment = ProcessEnv.vars
        #if os(Windows)
                    let windowsPathComponent = runtimePath.pathString.replacingOccurrences(of: "/", with: "\\")
                    environment["Path"] = "\(windowsPathComponent);\(environment["Path"] ?? "")"
        #endif

                    let cleanupAfterRunning = cleanupIfError.delay()
                    Process.popen(arguments: cmd, environment: environment, queue: delegateQueue) { result in
                        defer { cleanupAfterRunning.perform() }
                        fclose(jsonOutputFileDesc)
                        
                        do {
                            let runResult = try result.get()
                            if let runOutput = try (runResult.utf8Output() + runResult.utf8stderrOutput()).spm_chuzzle() {
                                // Append the runtime output to any compiler output we've received.
                                evaluationResult.compilerOutput = (evaluationResult.compilerOutput ?? "") + runOutput
                            }

                            // Return now if there was an error.
                            if runResult.exitStatus != .terminated(code: 0) {
                                // TODO: should this simply be an error?
                                // return completion(.failure(ProcessResult.Error.nonZeroExit(runResult)))
                                evaluationResult.errorOutput = evaluationResult.compilerOutput
                                return completion(.success(evaluationResult))
                            }

                            // Read the JSON output that was emitted by libPackageDescription.
                            let jsonOutput: String = try localFileSystem.readFileContents(jsonOutputFile)
                            evaluationResult.manifestJSON = jsonOutput
                            
                            completion(.success(evaluationResult))
                        } catch {
                            completion(.failure(error))
                        }
                    }
                }
            }
        } catch {
            return completion(.failure(error))
        }
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
        // if runtimePath is set to "PackageFrameworks" that means we could be developing SwiftPM in Xcode
        // which produces a framework for dynamic package products.
        if runtimePath.extension == "framework" {
            cmd += ["-I", runtimePath.parentDirectory.parentDirectory.pathString]
        } else {
            cmd += ["-I", runtimePath.pathString]
        }
      #if os(macOS)
        if let sdkRoot = self.toolchain.sdkRootPath ?? self.sdkRoot() {
            cmd += ["-sdk", sdkRoot.pathString]
        }
      #endif
        cmd += ["-package-description-version", toolsVersion.description]
        return cmd
    }

    /// Returns the runtime path given the manifest version and path to libDir.
    private func runtimePath(for version: ToolsVersion) -> AbsolutePath {
        let manifestAPIDir = self.toolchain.swiftPMLibrariesLocation.manifestAPI
        if localFileSystem.exists(manifestAPIDir) {
            return manifestAPIDir
        }

        // FIXME: how do we test this?
        // Fall back on the old location (this would indicate that we're using an old toolchain).
        return self.toolchain.swiftPMLibrariesLocation.manifestAPI.parentDirectory.appending(version.runtimeSubpath)
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

extension Basics.Diagnostic {
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

    static func invalidBinaryURL(url: String, targetName: String) -> Self {
        .error("invalid URL '\(url)' for binary target '\(targetName)'")
    }

    static func invalidLocalBinaryPath(path: String, targetName: String) -> Self {
        .error("invalid local path '\(path)' for binary target '\(targetName)', path expected to be relative to package root.")
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

private extension TargetDescription {
    var isRemote: Bool { url != nil }
    var isLocal: Bool { path != nil }
}
