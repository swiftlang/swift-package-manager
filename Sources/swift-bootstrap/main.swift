//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import Build
import Dispatch
import Foundation
import OrderedCollections
import PackageGraph
import PackageLoading
import PackageModel
import SPMBuildCore
import TSCBasic
import XCBuildSupport

import enum TSCUtility.Diagnostics
import struct TSCUtility.Version

SwiftBootstrapBuildTool.main()

struct SwiftBootstrapBuildTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-bootstrap",
        abstract: "Bootstrapping build tool, only use in the context of bootstrapping SwiftPM itself",
        shouldDisplay: false
    )

    @Option(name: .customLong("package-path"),
            help: "Specify the package path to operate on (default current directory). This changes the working directory before any other operation",
            completion: .directory)
    public var packageDirectory: AbsolutePath?

    /// The custom .build directory, if provided.
    @Option(name: .customLong("scratch-path"), help: "Specify a custom scratch directory path (default .build)", completion: .directory)
    var _scratchDirectory: AbsolutePath?

    @Option(name: .customLong("build-path"), help: .hidden)
    var _deprecated_buildPath: AbsolutePath?

    var scratchDirectory: AbsolutePath? {
        self._scratchDirectory ?? self._deprecated_buildPath
    }

    @Option(name: .shortAndLong, help: "Build with configuration")
    public var configuration: BuildConfiguration = .debug

    @Option(name: .customLong("Xcc", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: "Pass flag through to all C compiler invocations")
    var cCompilerFlags: [String] = []

    @Option(name: .customLong("Xswiftc", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: "Pass flag through to all Swift compiler invocations")
    var swiftCompilerFlags: [String] = []

    @Option(name: .customLong("Xlinker", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: "Pass flag through to all linker invocations")
    var linkerFlags: [String] = []

    @Option(name: .customLong("Xcxx", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: "Pass flag through to all C++ compiler invocations")
    var cxxCompilerFlags: [String] = []

    @Option(name: .customLong("Xxcbuild", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: ArgumentHelp(
                "Pass flag through to the Xcode build system invocations",
                visibility: .hidden))
    public var xcbuildFlags: [String] = []

    @Option(name: .customLong("Xmanifest", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: ArgumentHelp("Pass flag to the manifest build invocation",
                               visibility: .hidden))
    public var manifestFlags: [String] = []

    @Option(
      name: .customLong("arch"),
      help: ArgumentHelp("Build the package for the these architectures", visibility: .hidden))
    public var architectures: [String] = []

    /// The verbosity of informational output.
    @Flag(name: .shortAndLong, help: "Increase verbosity to include informational output")
    public var verbose: Bool = false

    /// The verbosity of informational output.
    @Flag(name: [.long, .customLong("vv")], help: "Increase verbosity to include debug output")
    public var veryVerbose: Bool = false

    /// Whether to use the integrated Swift driver rather than shelling out
    /// to a separate process.
    @Flag()
    public var useIntegratedSwiftDriver: Bool = false

    private var buildSystem: BuildSystemProvider.Kind {
        #if os(macOS)
        // Force the Xcode build system if we want to build more than one arch.
        return self.architectures.count > 1 ? .xcode : .native
        #else
        // Force building with the native build system on other platforms than macOS.
        return .native
        #endif
    }

    public var buildFlags: BuildFlags {
        BuildFlags(
            cCompilerFlags: self.cCompilerFlags,
            cxxCompilerFlags: self.cxxCompilerFlags,
            swiftCompilerFlags: self.swiftCompilerFlags,
            linkerFlags: self.linkerFlags,
            xcbuildFlags: self.xcbuildFlags
        )
    }

    private var logLevel: Basics.Diagnostic.Severity {
        if self.verbose {
            return .info
        } else if self.veryVerbose {
            return .debug
        } else {
            return .warning
        }
    }

    public init() {}

    public func run() throws {
        do {
            let fileSystem = localFileSystem

            let observabilityScope = ObservabilitySystem { _, diagnostics in
                if diagnostics.severity >= logLevel {
                    print(diagnostics)
                }
            }.topScope

            guard let cwd = fileSystem.currentWorkingDirectory else {
                observabilityScope.emit(error: "couldn't determine the current working directory")
                throw ExitCode.failure
            }

            guard let packagePath = packageDirectory ?? localFileSystem.currentWorkingDirectory else {
                throw StringError("unknown package path")
            }

            let scratchDirectory =
                try BuildSystemUtilities.getEnvBuildPath(workingDir: cwd) ??
                self.scratchDirectory ??
                packagePath.appending(".build")

            let builder = try Builder(
                fileSystem: localFileSystem,
                observabilityScope: observabilityScope,
                logLevel: self.logLevel
            )
            try builder.build(
                packagePath: packagePath,
                scratchDirectory: scratchDirectory,
                buildSystem: self.buildSystem,
                configuration: self.configuration,
                architectures: self.architectures,
                buildFlags: self.buildFlags,
                manifestBuildFlags: self.manifestFlags,
                useIntegratedSwiftDriver: self.useIntegratedSwiftDriver
            )
        } catch _ as Diagnostics {
            throw ExitCode.failure
        }
    }

    struct Builder {
        let identityResolver: IdentityResolver
        let hostToolchain: UserToolchain
        let destinationToolchain: UserToolchain
        let fileSystem: FileSystem
        let observabilityScope: ObservabilityScope
        let logLevel: Basics.Diagnostic.Severity

        static let additionalSwiftBuildFlags = [
            "-Xfrontend", "-disable-implicit-concurrency-module-import",
            "-Xfrontend", "-disable-implicit-string-processing-module-import"
        ]

        init(fileSystem: FileSystem, observabilityScope: ObservabilityScope, logLevel: Basics.Diagnostic.Severity) throws {
            guard let cwd = fileSystem.currentWorkingDirectory else {
                throw ExitCode.failure
            }

            self.identityResolver = DefaultIdentityResolver()
            self.hostToolchain = try UserToolchain(destination: Destination.hostDestination(originalWorkingDirectory: cwd))
            self.destinationToolchain = hostToolchain // TODO: support destinations?
            self.fileSystem = fileSystem
            self.observabilityScope = observabilityScope
            self.logLevel = logLevel
        }

        func build(
            packagePath:  AbsolutePath,
            scratchDirectory: AbsolutePath,
            buildSystem: BuildSystemProvider.Kind,
            configuration: BuildConfiguration,
            architectures: [String],
            buildFlags: BuildFlags,
            manifestBuildFlags: [String],
            useIntegratedSwiftDriver: Bool
        ) throws {
            let buildSystem = try createBuildSystem(
                packagePath: packagePath,
                scratchDirectory: scratchDirectory,
                buildSystem: buildSystem,
                configuration: configuration,
                architectures: architectures,
                buildFlags: buildFlags,
                manifestBuildFlags: manifestBuildFlags,
                useIntegratedSwiftDriver: useIntegratedSwiftDriver,
                logLevel: logLevel
            )
            try buildSystem.build(subset: .allExcludingTests)
        }

        func createBuildSystem(
            packagePath: AbsolutePath,
            scratchDirectory: AbsolutePath,
            buildSystem: BuildSystemProvider.Kind,
            configuration: BuildConfiguration,
            architectures: [String],
            buildFlags: BuildFlags,
            manifestBuildFlags: [String],
            useIntegratedSwiftDriver: Bool,
            logLevel: Basics.Diagnostic.Severity
        ) throws -> BuildSystem {

            var buildFlags = buildFlags
            buildFlags.swiftCompilerFlags += Self.additionalSwiftBuildFlags

            let dataPath = scratchDirectory.appending(
                component: self.destinationToolchain.triple.platformBuildPathComponent(buildSystem: buildSystem)
            )

            let buildParameters = try BuildParameters(
                dataPath: dataPath,
                configuration: configuration,
                toolchain: self.destinationToolchain,
                hostTriple: self.hostToolchain.triple,
                destinationTriple: self.destinationToolchain.triple,
                flags: buildFlags,
                architectures: architectures,
                useIntegratedSwiftDriver: useIntegratedSwiftDriver,
                isXcodeBuildSystemEnabled: buildSystem == .xcode,
                verboseOutput: logLevel <= .info
            )

            let manifestLoader = createManifestLoader(manifestBuildFlags: manifestBuildFlags)

            let packageGraphLoader = {
                try self.loadPackageGraph(packagePath: packagePath, manifestLoader: manifestLoader)

            }

            switch buildSystem {
            case .native:
                return BuildOperation(
                    buildParameters: buildParameters,
                    cacheBuildManifest: false,
                    packageGraphLoader: packageGraphLoader,
                    additionalFileRules: [],
                    pkgConfigDirectories: [],
                    outputStream: TSCBasic.stdoutStream,
                    logLevel: logLevel,
                    fileSystem: self.fileSystem,
                    observabilityScope: self.observabilityScope
                )
            case .xcode:
                return try XcodeBuildSystem(
                    buildParameters: buildParameters,
                    packageGraphLoader: packageGraphLoader,
                    outputStream: TSCBasic.stdoutStream,
                    logLevel: logLevel,
                    fileSystem: self.fileSystem,
                    observabilityScope: self.observabilityScope
                )
            }
        }

        func createManifestLoader(manifestBuildFlags: [String]) -> ManifestLoader {
            var extraManifestFlags = manifestBuildFlags + Self.additionalSwiftBuildFlags
            if self.logLevel <= .info {
                extraManifestFlags.append("-v")
            }

            return ManifestLoader(
                toolchain: self.hostToolchain,
                isManifestSandboxEnabled: false,
                extraManifestFlags: extraManifestFlags
            )
        }

        func loadPackageGraph(packagePath: AbsolutePath, manifestLoader: ManifestLoader) throws -> PackageGraph {
            let rootPackageRef = PackageReference(identity: .init(path: packagePath), kind: .root(packagePath))
            let rootPackageManifest =  try tsc_await { self.loadManifest(manifestLoader: manifestLoader, package: rootPackageRef, completion: $0) }

            var loadedManifests = [PackageIdentity: Manifest]()
            loadedManifests[rootPackageRef.identity] = rootPackageManifest

            // Compute the transitive closure of available dependencies.
            let input = loadedManifests.map { identity, manifest in KeyedPair(manifest, key: identity) }
            _ = try topologicalSort(input) { pair in
                let dependenciesRequired = pair.item.dependenciesRequired(for: .everything)
                let dependenciesToLoad = dependenciesRequired.map{ $0.createPackageRef() }.filter { !loadedManifests.keys.contains($0.identity) }
                let dependenciesManifests = try temp_await { self.loadManifests(manifestLoader: manifestLoader, packages: dependenciesToLoad, completion: $0) }
                dependenciesManifests.forEach { loadedManifests[$0.key] = $0.value }
                return dependenciesRequired.compactMap { dependency in
                    loadedManifests[dependency.identity].flatMap {
                        KeyedPair($0, key: dependency.identity)
                    }
                }
            }

            let packageGraphRoot = PackageGraphRoot(
                input: .init(packages: [packagePath]),
                manifests: [packagePath: rootPackageManifest]
            )

            return try PackageGraph.load(
                root: packageGraphRoot,
                identityResolver: identityResolver,
                externalManifests: loadedManifests.reduce(into: OrderedCollections.OrderedDictionary<PackageIdentity, (manifest: Manifest, fs: FileSystem)>()) { partial, item in
                    partial[item.key] = (manifest: item.value, fs: self.fileSystem)
                },
                binaryArtifacts: [:],
                fileSystem: fileSystem,
                observabilityScope: observabilityScope
            )
        }

        func loadManifests(
            manifestLoader: ManifestLoader,
            packages: [PackageReference],
            completion: @escaping (Result<[PackageIdentity: Manifest], Error>) -> Void
        ) {
            let sync = DispatchGroup()
            let manifestsLock = NSLock()
            var manifests = [PackageIdentity: Manifest]()
            Set(packages).forEach { package in
                sync.enter()
                self.loadManifest(manifestLoader: manifestLoader, package: package) { result in
                    defer { sync.leave() }
                    switch result {
                    case .success(let manifest):
                        manifestsLock.withLock {
                            manifests[package.identity] = manifest
                        }
                    case .failure(let error):
                        return completion(.failure(error))
                    }
                }
            }

            sync.notify(queue: .sharedConcurrent) {
                completion(.success(manifestsLock.withLock { manifests }))
            }
        }

        func loadManifest(
            manifestLoader: ManifestLoader,
            package: PackageReference,
            completion: @escaping (Result<Manifest, Error>) -> Void
        ) {
            do {
                let packagePath = try AbsolutePath(validating: package.locationString) // FIXME
                let manifestPath = packagePath.appending(component: Manifest.filename)
                let manifestToolsVersion = try ToolsVersionParser.parse(manifestPath: manifestPath, fileSystem: fileSystem)
                manifestLoader.load(
                    manifestPath: manifestPath,
                    manifestToolsVersion: manifestToolsVersion,
                    packageIdentity: package.identity,
                    packageKind: package.kind,
                    packageLocation: package.locationString,
                    packageVersion: .none,
                    identityResolver: identityResolver,
                    fileSystem: fileSystem,
                    observabilityScope: observabilityScope,
                    delegateQueue: .sharedConcurrent,
                    callbackQueue: .sharedConcurrent,
                    completion: completion
                )
            } catch {
                completion(.failure(error))
            }
        }        
    }
}

// TODO: move to shared area
extension AbsolutePath: ExpressibleByArgument {
    public init?(argument: String) {
        if let cwd = localFileSystem.currentWorkingDirectory {
            guard let path = try? AbsolutePath(validating: argument, relativeTo: cwd) else {
                return nil
            }
            self = path
        } else {
            guard let path = try? AbsolutePath(validating: argument) else {
                return nil
            }
            self = path
        }
    }

    public static var defaultCompletionKind: CompletionKind {
        // This type is most commonly used to select a directory, not a file.
        // Specify '.file()' in an argument declaration when necessary.
        .directory
    }
}

extension BuildConfiguration: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}
