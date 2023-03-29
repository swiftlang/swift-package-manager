//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
@_implementationOnly import Foundation
import PackageModel
import TSCBasic
import enum TSCUtility.Diagnostics
import struct TSCUtility.Version

public enum ManifestParseError: Swift.Error, Equatable {
    /// The manifest is empty, or at least from SwiftPM's perspective it is.
    case emptyManifest(path: AbsolutePath)
    /// The manifest contains invalid format.
    case invalidManifestFormat(String, diagnosticFile: AbsolutePath?)
    // TODO: Test this error.
    case invalidManifestFormat(String, diagnosticFile: AbsolutePath?, compilerCommandLine: [String]?)

    /// The manifest was successfully loaded by swift interpreter but there were runtime issues.
    case runtimeManifestErrors([String])

    /// The manifest loader specified import restrictions that the given manifest violated.
    case importsRestrictedModules([String])

    /// The JSON payload received from executing the manifest has an unsupported version, usually indicating an invalid mix-and-match of SwiftPM and PackageDescription libraries.
    case unsupportedVersion(version: Int, underlyingError: String? = nil)
}

// used to output the errors via the observability system
extension ManifestParseError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .emptyManifest(let manifestPath):
            return "'\(manifestPath)' is empty"
        case .invalidManifestFormat(let error, _, let compilerCommandLine):
            let suffix: String
            if let compilerCommandLine {
                suffix = " (compiled with: \(compilerCommandLine))"
            } else {
                suffix = ""
            }
            return "Invalid manifest\(suffix)\n\(error)"
        case .runtimeManifestErrors(let errors):
            return "invalid manifest (evaluation failed)\n\(errors.joined(separator: "\n"))"
        case .importsRestrictedModules(let modules):
            return "invalid manifest, imports restricted modules: \(modules.joined(separator: ", "))"
        case .unsupportedVersion(let version, let underlyingError):
            let message = "serialized JSON uses unsupported version \(version), indicating use of a mismatched PackageDescription library"
            if let underlyingError {
                return "\(message), underlying error: \(underlyingError)"
            }
            return message
        }
    }
}

// MARK: - ManifestLoaderProtocol

/// Protocol for the manifest loader interface.
public protocol ManifestLoaderProtocol {
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
    ///   - fileSystem: File system to load from.
    ///   - observabilityScope: Observability scope to emit diagnostics.
    ///   - delegateQueue: The dispatch queue to call delegate handlers on.
    ///   - callbackQueue: The dispatch queue to perform completion handler on.
    ///   - completion: The completion handler .
    func load(
        manifestPath: AbsolutePath,
        manifestToolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        packageVersion: (version: Version?, revision: String?)?,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    )

    /// Reset any internal cache held by the manifest loader.
    func resetCache(observabilityScope: ObservabilityScope)

    /// Reset any internal cache held by the manifest loader and purge any entries in a shared cache
    func purgeCache(observabilityScope: ObservabilityScope)
}

public protocol ManifestLoaderDelegate {
    func willLoad(manifest: AbsolutePath)
    func willParse(manifest: AbsolutePath)
}

// loads a manifest given a package root path
// this will first find the most appropriate manifest file in the package directory
// bases on the toolchain's tools-version and proceed to load that manifest
extension ManifestLoaderProtocol {
    public func load(
        packagePath: AbsolutePath,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        packageVersion: (version: Version?, revision: String?)?,
        currentToolsVersion: ToolsVersion,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        do {
            // find the manifest path and parse it's tools-version
            let manifestPath = try ManifestLoader.findManifest(packagePath: packagePath, fileSystem: fileSystem, currentToolsVersion: currentToolsVersion)
            let manifestToolsVersion = try ToolsVersionParser.parse(manifestPath: manifestPath, fileSystem: fileSystem)
            // validate the manifest tools-version against the toolchain tools-version
            try manifestToolsVersion.validateToolsVersion(currentToolsVersion, packageIdentity: packageIdentity, packageVersion: packageVersion?.version?.description ?? packageVersion?.revision)

            self.load(
                manifestPath: manifestPath,
                manifestToolsVersion: manifestToolsVersion,
                packageIdentity: packageIdentity,
                packageKind: packageKind,
                packageLocation: packageLocation,
                packageVersion: packageVersion,
                identityResolver: identityResolver,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope,
                delegateQueue: delegateQueue,
                callbackQueue: callbackQueue,
                completion: completion
            )
        } catch {
            callbackQueue.async {
                completion(.failure(error))
            }
        }
    }
}

// MARK: - ManifestLoader

/// Utility class for loading manifest files.
///
/// This class is responsible for reading the manifest data and produce a
/// properly formed `PackageModel.Manifest` object. It currently does so by
/// interpreting the manifest source using Swift -- that produces a JSON
/// serialized form of the manifest (as implemented by `PackageDescription`'s
/// `atexit()` handler) which is then deserialized and loaded.
public final class ManifestLoader: ManifestLoaderProtocol {
    private let toolchain: UserToolchain
    private let serializedDiagnostics: Bool
    private let isManifestSandboxEnabled: Bool
    private let delegate: ManifestLoaderDelegate?
    private let extraManifestFlags: [String]
    private let restrictImports: (startingToolsVersion: ToolsVersion, allowedImports: [String])?

    private let databaseCacheDir: AbsolutePath?

    private let sdkRootCache = ThreadSafeBox<AbsolutePath>()

    /// DispatchSemaphore to restrict concurrent manifest evaluations
    private let concurrencySemaphore: DispatchSemaphore
    /// OperationQueue to park pending lookups
    private let evaluationQueue: OperationQueue

    public init(
        toolchain: UserToolchain,
        serializedDiagnostics: Bool = false,
        isManifestSandboxEnabled: Bool = true,
        cacheDir: AbsolutePath? = nil,
        delegate: ManifestLoaderDelegate? = nil,
        extraManifestFlags: [String] = [],
        restrictImports: (startingToolsVersion: ToolsVersion, allowedImports: [String])? = .none
    ) {
        self.toolchain = toolchain
        self.serializedDiagnostics = serializedDiagnostics
        self.isManifestSandboxEnabled = isManifestSandboxEnabled
        self.delegate = delegate
        self.extraManifestFlags = extraManifestFlags
        self.restrictImports = restrictImports

        self.databaseCacheDir = try? cacheDir.map(resolveSymlinks)

        // this queue and semaphore is used to limit the amount of concurrent manifest loading taking place
        self.evaluationQueue = OperationQueue()
        self.evaluationQueue.name = "org.swift.swiftpm.manifest-loader"
        self.evaluationQueue.maxConcurrentOperationCount = Concurrency.maxOperations
        self.concurrencySemaphore = DispatchSemaphore(value: Concurrency.maxOperations)
    }

    public func load(
        manifestPath: AbsolutePath,
        manifestToolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        packageVersion: (version: Version?, revision: String?)?,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        // Inform the delegate.
        delegateQueue.async {
            self.delegate?.willLoad(manifest: manifestPath)
        }

        // Validate that the file exists.
        guard fileSystem.isFile(manifestPath) else {
            return callbackQueue.async {
                completion(.failure(PackageModel.Package.Error.noManifest(at: manifestPath, version: packageVersion?.version)))
            }
        }

        self.loadAndCacheManifest(
            at: manifestPath,
            toolsVersion: manifestToolsVersion,
            packageIdentity: packageIdentity,
            packageKind: packageKind,
            packageVersion: packageVersion?.version,
            identityResolver: identityResolver,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
            delegateQueue: delegateQueue,
            callbackQueue: callbackQueue
        ) { parseResult in
            do {
                dispatchPrecondition(condition: .onQueue(callbackQueue))

                let parsedManifest = try parseResult.get()
                // Convert legacy system packages to the current target‐based model.
                var products = parsedManifest.products
                var targets = parsedManifest.targets
                if products.isEmpty, targets.isEmpty,
                   fileSystem.isFile(manifestPath.parentDirectory.appending(component: moduleMapFilename)) {
                    try products.append(ProductDescription(
                        name: parsedManifest.name,
                        type: .library(.automatic),
                        targets: [parsedManifest.name])
                    )
                    targets.append(try TargetDescription(
                        name: parsedManifest.name,
                        group: .excluded, // access to only public APIs is allowed for system libs
                        path: "",
                        type: .system,
                        pkgConfig: parsedManifest.pkgConfig,
                        providers: parsedManifest.providers
                    ))
                }

                let manifest = Manifest(
                    displayName: parsedManifest.name,
                    path: manifestPath,
                    packageKind: packageKind,
                    packageLocation: packageLocation,
                    defaultLocalization: parsedManifest.defaultLocalization,
                    platforms: parsedManifest.platforms,
                    version: packageVersion?.version,
                    revision: packageVersion?.revision,
                    toolsVersion: manifestToolsVersion,
                    pkgConfig: parsedManifest.pkgConfig,
                    providers: parsedManifest.providers,
                    cLanguageStandard: parsedManifest.cLanguageStandard,
                    cxxLanguageStandard: parsedManifest.cxxLanguageStandard,
                    swiftLanguageVersions: parsedManifest.swiftLanguageVersions,
                    dependencies: parsedManifest.dependencies,
                    products: products,
                    targets: targets
                )
                completion(.success(manifest))
            } catch {
                callbackQueue.async {
                    completion(.failure(error))
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
            throw ManifestParseError.invalidManifestFormat(errors, diagnosticFile: result.diagnosticFile, compilerCommandLine: result.compilerCommandLine)
        }

        // We should not have any fatal error at this point.
        guard result.errorOutput == nil else {
            throw InternalError("unexpected error output: \(result.errorOutput!)")
        }

        // We might have some non-fatal output (warnings/notes) from the compiler even when
        // we were able to parse the manifest successfully.
        if let compilerOutput = result.compilerOutput {
            let metadata = result.diagnosticFile.map { diagnosticFile -> ObservabilityMetadata in
                var metadata = ObservabilityMetadata()
                metadata.manifestLoadingDiagnosticFile = diagnosticFile
                return metadata
            }
            observabilityScope.emit(warning: compilerOutput, metadata: metadata)
        }

        return try ManifestJSONParser.parse(
            v4: manifestJSON,
            toolsVersion: toolsVersion,
            packageKind: packageKind,
            identityResolver: identityResolver,
            fileSystem: fileSystem
        )
    }

    private func loadAndCacheManifest(
        at path: AbsolutePath,
        toolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageVersion: Version?,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue,
        callbackQueue: DispatchQueue,
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

        let closingCompletion = { (result: Result<ManifestJSONParser.Result, Error>) in
            do {
                try cache?.close()
            } catch {
                observabilityScope.emit(warning: "failed closing cache: \(error)")
            }

            callbackQueue.async {
                completion(result)
            }
        }

        let key : CacheKey
        do {
            key = try CacheKey(
                packageIdentity: packageIdentity,
                manifestPath: path,
                toolsVersion: toolsVersion,
                env: ProcessEnv.vars,
                swiftpmVersion: SwiftVersion.current.displayString,
                fileSystem: fileSystem
            )
        } catch {
            return closingCompletion(.failure(error))
        }

        do {
            // try to get it from the cache
            if let result = try cache?.get(key: key.sha256Checksum), let manifestJSON = result.manifestJSON, !manifestJSON.isEmpty {
                observabilityScope.emit(debug: "loading manifest for '\(packageIdentity)' v. \(packageVersion?.description ?? "unknown") from cache")
                let parsedManifest = try self.parseManifest(
                    result,
                    packageIdentity: packageIdentity,
                    packageKind: packageKind,
                    toolsVersion: toolsVersion,
                    identityResolver: identityResolver,
                    fileSystem: fileSystem,
                    observabilityScope: observabilityScope
                )
                return closingCompletion(.success(parsedManifest))
            }
        } catch {
            observabilityScope.emit(warning: "failed loading cached manifest for '\(key.packageIdentity)': \(error)")
        }

        // shells out and compiles the manifest, finally output a JSON
        observabilityScope.emit(debug: "evaluating manifest for '\(packageIdentity)' v. \(packageVersion?.description ?? "unknown")")
        do {
            try self.evaluateManifest(
                packageIdentity: key.packageIdentity,
                manifestPath: key.manifestPath,
                manifestContents: key.manifestContents,
                toolsVersion: key.toolsVersion,
                delegateQueue: delegateQueue,
                callbackQueue: callbackQueue
            ) { result in
                dispatchPrecondition(condition: .onQueue(callbackQueue))

                do {
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

                    return closingCompletion(.success(parseManifest))
                } catch {
                    return closingCompletion(.failure(error))
                }
            }
        } catch {
            return closingCompletion(.failure(error))
        }
    }

    private func validateImports(
        manifestPath: AbsolutePath,
        toolsVersion: ToolsVersion,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void) {
            // If there are no import restrictions, we do not need to validate.
            guard let restrictImports = restrictImports, toolsVersion >= restrictImports.startingToolsVersion else {
                return callbackQueue.async {
                    completion(.success(()))
                }
            }

            // Allowed are the expected defaults, plus anything allowed by the configured restrictions.
            let allowedImports = ["PackageDescription", "Swift",
                                  "SwiftOnoneSupport", "_SwiftConcurrencyShims"] + restrictImports.allowedImports

            // wrap the completion to free concurrency control semaphore
            let completion: (Result<Void, Error>) -> Void = { result in
                self.concurrencySemaphore.signal()
                callbackQueue.async {
                    completion(result)
                }
            }

            // we must not block the calling thread (for concurrency control) so nesting this in a queue
            self.evaluationQueue.addOperation {
                do {
                    // park the evaluation thread based on the max concurrency allowed
                    self.concurrencySemaphore.wait()

                    let importScanner = SwiftcImportScanner(swiftCompilerEnvironment: self.toolchain.swiftCompilerEnvironment,
                                                            swiftCompilerFlags: self.extraManifestFlags,
                                                            swiftCompilerPath: self.toolchain.swiftCompilerPathForManifests)

                    importScanner.scanImports(manifestPath, callbackQueue: callbackQueue) { result in
                        do {
                            let imports = try result.get().filter { !allowedImports.contains($0) }
                            guard imports.isEmpty else {
                                throw ManifestParseError.importsRestrictedModules(imports)
                            }
                        } catch {
                            completion(.failure(error))
                        }
                    }
                }
            }
        }

    /// Compiler the manifest at the given path and retrieve the JSON.
    fileprivate func evaluateManifest(
        packageIdentity: PackageIdentity,
        manifestPath: AbsolutePath,
        manifestContents: [UInt8],
        toolsVersion: ToolsVersion,
        delegateQueue: DispatchQueue,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<EvaluationResult, Error>) -> Void
    ) throws {
        let manifestPreamble: ByteString
        if toolsVersion >= .v5_8 {
            manifestPreamble = ByteString()
        } else {
            manifestPreamble = ByteString("import Foundation\n")
        }

        do {
            try withTemporaryDirectory { tempDir, cleanupTempDir in
                let manifestTempFilePath = tempDir.appending("manifest.swift")
                try localFileSystem.writeFileContents(manifestTempFilePath, bytes: ByteString(manifestPreamble.contents + manifestContents))

                #if os(Windows)
                // On Windows, we seem to have issues with the VFS overlay, so let's disable it for now.
                let effectiveManifestPath = manifestTempFilePath
                let vfsOverlayTempFilePath: AbsolutePath? = nil
                #else
                let effectiveManifestPath = manifestPath
                let vfsOverlayTempFilePath = tempDir.appending("vfs.yaml")
                try VFSOverlay(roots: [
                    VFSOverlay.File(name: manifestPath.pathString, externalContents: manifestTempFilePath.pathString)
                ]).write(to: vfsOverlayTempFilePath, fileSystem: localFileSystem)
                #endif

                validateImports(manifestPath: manifestTempFilePath, toolsVersion: toolsVersion, callbackQueue: callbackQueue) { result in
                    dispatchPrecondition(condition: .onQueue(callbackQueue))

                    do {
                        try result.get()

                        try self.evaluateManifest(
                            at: effectiveManifestPath,
                            vfsOverlayPath: vfsOverlayTempFilePath,
                            packageIdentity: packageIdentity,
                            toolsVersion: toolsVersion,
                            delegateQueue: delegateQueue,
                            callbackQueue: callbackQueue
                        ) { result in
                            dispatchPrecondition(condition: .onQueue(callbackQueue))
                            cleanupTempDir(tempDir)
                            completion(result)
                        }
                    } catch {
                        cleanupTempDir(tempDir)
                        callbackQueue.async {
                            completion(.failure(error))
                        }
                    }
                }
            }
        } catch {
            callbackQueue.async {
                completion(.failure(error))
            }
        }
    }

    /// Helper method for evaluating the manifest.
    func evaluateManifest(
        at manifestPath: AbsolutePath,
        vfsOverlayPath: AbsolutePath? = nil,
        packageIdentity: PackageIdentity,
        toolsVersion: ToolsVersion,
        delegateQueue: DispatchQueue,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<EvaluationResult, Error>) -> Void
    ) throws {
        // The compiler has special meaning for files with extensions like .ll, .bc etc.
        // Assert that we only try to load files with extension .swift to avoid unexpected loading behavior.
        guard manifestPath.extension == "swift" else {
            return callbackQueue.async {
                completion(.failure(InternalError("Manifest files must contain .swift suffix in their name, given: \(manifestPath).")))
            }
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
        let runtimePath = self.toolchain.swiftPMLibrariesLocation.manifestLibraryPath

        // FIXME: Workaround for the module cache bug that's been haunting Swift CI
        // <rdar://problem/48443680>
        let moduleCachePath = try (ProcessEnv.vars["SWIFTPM_MODULECACHE_OVERRIDE"] ?? ProcessEnv.vars["SWIFTPM_TESTS_MODULECACHE"]).flatMap{ try AbsolutePath(validating: $0) }

        var cmd: [String] = []
        cmd += [self.toolchain.swiftCompilerPathForManifests.pathString]

        if let vfsOverlayPath {
            cmd += ["-vfsoverlay", vfsOverlayPath.pathString]
        }

        // if runtimePath is set to "PackageFrameworks" that means we could be developing SwiftPM in Xcode
        // which produces a framework for dynamic package products.
        if runtimePath.extension == "framework" {
            cmd += [
                "-F", runtimePath.parentDirectory.pathString,
                "-framework", "PackageDescription",
                "-Xlinker", "-rpath", "-Xlinker", runtimePath.parentDirectory.pathString,
            ]
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
        }

        // Use the same minimum deployment target as the PackageDescription library (with a fallback of 10.15).
#if os(macOS)
        let version = self.toolchain.swiftPMLibrariesLocation.manifestLibraryMinimumDeploymentTarget.versionString
        cmd += ["-target", "\(self.toolchain.triple.tripleString(forPlatformVersion: version))"]
#endif

        // Add any extra flags required as indicated by the ManifestLoader.
        cmd += self.toolchain.swiftCompilerFlags

        cmd += self.interpreterFlags(for: toolsVersion)
        if let moduleCachePath {
            cmd += ["-module-cache-path", moduleCachePath.pathString]
        }

        // Add the arguments for emitting serialized diagnostics, if requested.
        if self.serializedDiagnostics, let databaseCacheDir = self.databaseCacheDir {
            let diaDir = databaseCacheDir.appending("ManifestLoading")
            let diagnosticFile = diaDir.appending("\(packageIdentity).dia")
            do {
                try localFileSystem.createDirectory(diaDir, recursive: true)
                cmd += ["-Xfrontend", "-serialize-diagnostics-path", "-Xfrontend", diagnosticFile.pathString]
                evaluationResult.diagnosticFile = diagnosticFile
            } catch {
                return callbackQueue.async {
                    completion(.failure(error))
                }
            }
        }

        cmd += [manifestPath.pathString]

        cmd += self.extraManifestFlags

        // wrap the completion to free concurrency control semaphore
        let completion: (Result<EvaluationResult, Error>) -> Void = { result in
            self.concurrencySemaphore.signal()
            completion(result)
        }

        // we must not block the calling thread (for concurrency control) so nesting this in a queue
        self.evaluationQueue.addOperation {
            do {
                // park the evaluation thread based on the max concurrency allowed
                self.concurrencySemaphore.wait()
                // run the evaluation
                try withTemporaryDirectory { tmpDir, cleanupTmpDir in
                    // Set path to compiled manifest executable.
                    #if os(Windows)
                    let executableSuffix = ".exe"
                    #else
                    let executableSuffix = ""
                    #endif
                    let compiledManifestFile = tmpDir.appending("\(packageIdentity)-manifest\(executableSuffix)")
                    cmd += ["-o", compiledManifestFile.pathString]

                    evaluationResult.compilerCommandLine = cmd

                    // Compile the manifest.
                    TSCBasic.Process.popen(arguments: cmd, environment: self.toolchain.swiftCompilerEnvironment, queue: callbackQueue) { result in
                        dispatchPrecondition(condition: .onQueue(callbackQueue))

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
                        let jsonOutputFile = tmpDir.appending("\(packageIdentity)-output.json")
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
                            do {
                                cmd = try Sandbox.apply(command: cmd, strictness: strictness, writableDirectories: cacheDirectories)
                            } catch {
                                return completion(.failure(error))
                            }
                        }

                        // Run the compiled manifest.
                        var environment = ProcessEnv.vars
                        #if os(Windows)
                        let windowsPathComponent = runtimePath.pathString.replacingOccurrences(of: "/", with: "\\")
                        environment["Path"] = "\(windowsPathComponent);\(environment["Path"] ?? "")"
                        #endif

                        let cleanupAfterRunning = cleanupIfError.delay()
                        TSCBasic.Process.popen(arguments: cmd, environment: environment, queue: callbackQueue) { result in
                            dispatchPrecondition(condition: .onQueue(callbackQueue))

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
                return callbackQueue.async {
                    completion(.failure(error))
                }
            }
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
        let foundPath = try? TSCBasic.Process.checkNonZeroExit(
            args: "/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path")
        guard let sdkRoot = foundPath?.spm_chomp(), !sdkRoot.isEmpty else {
            return nil
        }
        if let path = try? AbsolutePath(validating: sdkRoot) {
            sdkRootPath = path
            self.sdkRootCache.put(path)
        }
        #endif

        return sdkRootPath
    }

    /// Returns the interpreter flags for a manifest.
    public func interpreterFlags(
        for toolsVersion: ToolsVersion
    ) -> [String] {
        var cmd = [String]()
        let runtimePath = self.toolchain.swiftPMLibrariesLocation.manifestLibraryPath
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

    /// Returns path to the manifest database inside the given cache directory.
    private static func manifestCacheDBPath(_ cacheDir: AbsolutePath) -> AbsolutePath {
        return cacheDir.appending("manifest.db")
    }

    /// reset internal cache
    public func resetCache(observabilityScope: ObservabilityScope) {
        // nothing needed at this point
    }

    /// reset internal state and purge shared cache
    public func purgeCache(observabilityScope: ObservabilityScope) {
        self.resetCache(observabilityScope: observabilityScope)

        guard let manifestCacheDBPath = self.databaseCacheDir.flatMap({ Self.manifestCacheDBPath($0) }) else {
            return
        }

        guard localFileSystem.exists(manifestCacheDBPath) else {
            return
        }

        do {
            try localFileSystem.removeFileTree(manifestCacheDBPath)
        } catch {
            observabilityScope.emit(error: "Error purging manifests cache at '\(manifestCacheDBPath)': \(error))")
        }
    }
}

extension ManifestLoader {
    struct CacheKey: Hashable {
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
}

extension ManifestLoader {
    struct EvaluationResult: Codable {
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

        /// The command line used to compile the manifest
        var compilerCommandLine: [String]?

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
}

extension ManifestLoader {
    /// Represents behavior that can be deferred until a more appropriate time.
    struct DelayableAction<T> {
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
}
