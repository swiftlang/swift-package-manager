/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import Build
import PackageLoading
import PackageGraph
import PackageModel
import POSIX
import SourceControl
import Utility
import Workspace
import libc
import func Foundation.NSUserName

struct ChdirDeprecatedDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: AnyDiagnostic.self,
        name: "org.swift.diags.chdir-deprecated",
        defaultBehavior: .warning,
        description: {
            $0 <<< "'--chdir/-C' option is deprecated; use '--package-path' instead"
        }
    )
}

/// Diagnostic error when the tool could not find a named product.
struct ProductNotFoundDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: ProductNotFoundDiagnostic.self,
        name: "org.swift.diags.product-not-found",
        defaultBehavior: .error,
        description: { $0 <<< "no product named" <<< { "'\($0.productName)'" } }
    )

    let productName: String
}

/// Warning when someone tries to build an automatic type product using --product option.
struct ProductIsAutomaticDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: ProductIsAutomaticDiagnostic.self,
        name: "org.swift.diags.product-is-automatic",
        defaultBehavior: .warning,
        description: { $0 <<< "'--product' cannot be used with the automatic product" <<< { "'\($0.productName)'." } <<< "Building the default target instead" }
    )

    let productName: String
}

/// Diagnostic error when the tool could not find a named target.
struct TargetNotFoundDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: TargetNotFoundDiagnostic.self,
        name: "org.swift.diags.target-not-found",
        defaultBehavior: .error,
        description: { $0 <<< "no target named" <<< { "'\($0.targetName)'" } }
    )

    let targetName: String
}

private class ToolWorkspaceDelegate: WorkspaceDelegate {

    func packageGraphWillLoad(
        currentGraph: PackageGraph,
        dependencies: AnySequence<ManagedDependency>,
        missingURLs: Set<String>
    ) {
    }

    func fetchingWillBegin(repository: String) {
        print("Fetching \(repository)")
    }

    func fetchingDidFinish(repository: String, diagnostic: Diagnostic?) {
    }

    func repositoryWillUpdate(_ repository: String) {
        print("Updating \(repository)")
    }

    func repositoryDidUpdate(_ repository: String) {
    }
    
    func dependenciesUpToDate() {
        print("Everything is already up-to-date")
    }

    func cloning(repository: String) {
        print("Cloning \(repository)")
    }

    func checkingOut(repository: String, atReference reference: String, to path: AbsolutePath) {
        // FIXME: This is temporary output similar to old one, we will need to figure
        // out better reporting text.
        print("Resolving \(repository) at \(reference)")
    }

    func removing(repository: String) {
        print("Removing \(repository)")
    }

    func warning(message: String) {
        print("warning: " + message)
    }

    func managedDependenciesDidUpdate(_ dependencies: AnySequence<ManagedDependency>) {
    }
}

protocol ToolName {
    static var toolName: String { get }
}

extension ToolName {
    static func otherToolNames() -> String {
        let allTools: [ToolName.Type] = [SwiftBuildTool.self, SwiftRunTool.self, SwiftPackageTool.self, SwiftTestTool.self]
        return  allTools.filter({ $0 != self }).map({ $0.toolName }).joined(separator: ", ")
    }
}

/// Represents the persistent build manifest token.
final class BuildManifestRegenerationToken {

    /// Path to the token file.
    let tokenFile: AbsolutePath

    /// The filesystem being used.
    let fs: FileSystem = localFileSystem

    init(tokenFile: AbsolutePath) {
        self.tokenFile = tokenFile
    }

    /// Returns true if the token is valid.
    ///
    /// A valid token means we don't need to re-generate the build manifest.
    func isValid() -> Bool {
        guard fs.isFile(tokenFile) else {
            return false
        }
        guard let contents = try? fs.readFileContents(tokenFile) else {
            return false
        }
        switch contents {
        case "1\n":
            return false
        default:
            return true
        }
    }

    /// Sets the state of the token.
    func set(valid: Bool) {
        // FIXME: Error handling
        try? fs.writeFileContents(tokenFile, bytes: valid ? "0\n" : "1\n")
    }
}

public class SwiftTool<Options: ToolOptions> {
    /// The original working directory.
    let originalWorkingDirectory: AbsolutePath
    
    /// The options of this tool.
    let options: Options

    /// Path to the root package directory, nil if manifest is not found.
    let packageRoot: AbsolutePath?

    /// Helper function to get package root or throw error if it is not found.
    func getPackageRoot() throws -> AbsolutePath {
        guard let packageRoot = packageRoot else {
            throw Error.rootManifestFileNotFound
        }
        return packageRoot
    }

    /// Get the current workspace root object.
    func getWorkspaceRoot() throws -> PackageGraphRootInput {
        return try PackageGraphRootInput(packages: [getPackageRoot()])
    }

    /// Path to the build directory.
    let buildPath: AbsolutePath

    /// Reference to the argument parser.
    let parser: ArgumentParser

    /// The process set to hold the launched processes. These will be terminated on any signal
    /// received by the swift tools.
    let processSet: ProcessSet

    /// The interrupt handler.
    let interruptHandler: InterruptHandler

    /// The diagnostics engine.
    let diagnostics = DiagnosticsEngine()

    /// The execution status of the tool.
    var executionStatus: ExecutionStatus = .success

    /// Create an instance of this tool.
    ///
    /// - parameter args: The command line arguments to be passed to this tool.
    public init(toolName: String, usage: String, overview: String, args: [String], seeAlso: String? = nil) {
        // Capture the original working directory ASAP.
        originalWorkingDirectory = currentWorkingDirectory
        
        // Create the parser.
        parser = ArgumentParser(
            commandName: "swift \(toolName)",
            usage: usage,
            overview: overview,
            seeAlso: seeAlso)

        // Create the binder.
        let binder = ArgumentBinder<Options>()

        // Bind the common options.
        binder.bindArray(
            parser.add(
                option: "-Xcc", kind: [String].self, strategy: .oneByOne,
                usage: "Pass flag through to all C compiler invocations"),
            parser.add(
                option: "-Xswiftc", kind: [String].self, strategy: .oneByOne,
                usage: "Pass flag through to all Swift compiler invocations"),
            parser.add(
                option: "-Xlinker", kind: [String].self, strategy: .oneByOne,
                usage: "Pass flag through to all linker invocations"),
            to: {
                $0.buildFlags.cCompilerFlags = $1
                $0.buildFlags.swiftCompilerFlags = $2
                $0.buildFlags.linkerFlags = $3
            })
        binder.bindArray(
            option: parser.add(
                option: "-Xcxx", kind: [String].self, strategy: .oneByOne,
                usage: "Pass flag through to all C++ compiler invocations"),
            to: { $0.buildFlags.cxxCompilerFlags = $1 })

        binder.bind(
            option: parser.add(
                option: "--configuration", shortName: "-c", kind: Build.Configuration.self,
                usage: "Build with configuration (debug|release) [default: debug]"),
            to: { $0.configuration = $1 })
        
        binder.bind(
            option: parser.add(
                option: "--build-path", kind: PathArgument.self,
                usage: "Specify build/cache directory [default: ./.build]"),
            to: { $0.buildPath = $1.path })

        binder.bind(
            option: parser.add(
                option: "--chdir", shortName: "-C", kind: PathArgument.self),
            to: { $0.chdir = $1.path })
        
        binder.bind(
            option: parser.add(
                option: "--package-path", kind: PathArgument.self,
                usage: "Change working directory before any other operation"),
            to: { $0.packagePath = $1.path })

        binder.bind(
            option: parser.add(option: "--disable-prefetching", kind: Bool.self, usage: ""),
            to: { $0.shouldEnableResolverPrefetching = !$1 })

        binder.bind(
            option: parser.add(option: "--disable-sandbox", kind: Bool.self,
            usage: "Disable using the sandbox when executing subprocesses"),
            to: { $0.shouldDisableSandbox = $1 })

        binder.bind(
            option: parser.add(option: "--version", kind: Bool.self),
            to: { $0.shouldPrintVersion = $1 })

        binder.bind(
            option: parser.add(option: "--destination", kind: PathArgument.self),
            to: { $0.customCompileDestination = $1.path })

        // FIXME: We need to allow -vv type options for this.
        binder.bind(
            option: parser.add(option: "--verbose", shortName: "-v", kind: Bool.self,
                usage: "Increase verbosity of informational output"),
            to: { $0.verbosity = $1 ? 1 : 0 })

        binder.bind(
            option: parser.add(option: "--no-static-swift-stdlib", kind: Bool.self,
                usage: "Do not link Swift stdlib statically"),
            to: { $0.shouldLinkStaticSwiftStdlib = !$1 })

        binder.bind(
            option: parser.add(option: "--static-swift-stdlib", kind: Bool.self,
                usage: "Link Swift stdlib statically"),
            to: { $0.shouldLinkStaticSwiftStdlib = $1 })

        binder.bind(
            option: parser.add(option: "--enable-build-manifest-caching", kind: Bool.self,
                usage: "Enable llbuild manifest caching [Experimental]"),
            to: { $0.shouldEnableManifestCaching = $1 })

        // Let subclasses bind arguments.
        type(of: self).defineArguments(parser: parser, binder: binder)

        do {
            // Parse the result.
            let result = try parser.parse(args)

            var options = Options()
            binder.fill(result, into: &options)

            self.options = options
            // Honor package-path option is provided.
            if let packagePath = options.packagePath ?? options.chdir {
                // FIXME: This should be an API which takes AbsolutePath and maybe
                // should be moved to file system APIs with currentWorkingDirectory.
                try POSIX.chdir(packagePath.asString)
            }

            let processSet = ProcessSet()
            interruptHandler = try InterruptHandler {
                // Terminate all processes on receiving an interrupt signal.
                processSet.terminate()

                // Install the default signal handler.
                var action = sigaction()
              #if os(macOS)
                action.__sigaction_u.__sa_handler = SIG_DFL
              #else
                action.__sigaction_handler = unsafeBitCast(
                    SIG_DFL,
                    to: sigaction.__Unnamed_union___sigaction_handler.self)
              #endif
                sigaction(SIGINT, &action, nil)

                // Die with sigint.
                kill(getpid(), SIGINT)
            }
            self.processSet = processSet

        } catch {
            handle(error: error)
            SwiftTool.exit(with: .failure)
        }

        // Create local variables to use while finding build path to avoid capture self before init error.
        let customBuildPath = options.buildPath
        let packageRoot = findPackageRoot()

        self.packageRoot = packageRoot
        self.buildPath = getEnvBuildPath() ??
            customBuildPath ??
            (packageRoot ?? currentWorkingDirectory).appending(component: ".build")
        
        if options.chdir != nil {
            diagnostics.emit(data: ChdirDeprecatedDiagnostic())
        }
    }

    class func defineArguments(parser: ArgumentParser, binder: ArgumentBinder<Options>) {
        fatalError("Must be implemented by subclasses")
    }

    func resolvedFilePath() throws -> AbsolutePath {
        return try getPackageRoot().appending(component: "Package.resolved")
    }

    /// Holds the currently active workspace.
    ///
    /// It is not initialized in init() because for some of the commands like package init , usage etc,
    /// workspace is not needed, infact it would be an error to ask for the workspace object
    /// for package init because the Manifest file should *not* present.
    private var _workspace: Workspace?

    /// Returns the currently active workspace.
    func getActiveWorkspace() throws -> Workspace {
        if let workspace = _workspace {
            return workspace
        }
        let delegate = ToolWorkspaceDelegate()
        let rootPackage = try getPackageRoot()
        let provider = GitRepositoryProvider(processSet: processSet)
        let workspace = Workspace(
            dataPath: buildPath,
            editablesPath: rootPackage.appending(component: "Packages"),
            pinsFile: try resolvedFilePath(),
            manifestLoader: try getManifestLoader(),
            toolsVersionLoader: ToolsVersionLoader(),
            delegate: delegate,
            repositoryProvider: provider,
            isResolverPrefetchingEnabled: options.shouldEnableResolverPrefetching
        )
        _workspace = workspace
        return workspace
    }

    /// Execute the tool.
    public func run() {
        do {
            // Setup the globals.
            verbosity = Verbosity(rawValue: options.verbosity)
            Process.verbose = verbosity != .concise
            // Call the implementation.
            try runImpl()
            if diagnostics.hasErrors {
                throw Error.hasFatalDiagnostics
            }
            // Print any non fatal diagnostics like warnings, notes.
            printDiagnostics()
        } catch {
            // Set execution status to failure in case of errors.
            executionStatus = .failure
            printDiagnostics()
            handle(error: error)
        }
        SwiftTool.exit(with: executionStatus)
    }

    private func printDiagnostics() {
        for diagnostic in diagnostics.diagnostics {
            print(diagnostic: diagnostic)
        }
    }

    /// Exit the tool with the given execution status.
    private static func exit(with status: ExecutionStatus) -> Never {
        switch status {
        case .success: POSIX.exit(0)
        case .failure: POSIX.exit(1)
        }
    }

    /// Run method implementation to be overridden by subclasses.
    func runImpl() throws {
        fatalError("Must be implemented by subclasses")
    }

    /// Resolve the dependencies.
    func resolve() throws {
        let workspace = try getActiveWorkspace()
        workspace.resolve(root: try getWorkspaceRoot(), diagnostics: diagnostics)

        // Throw if there were errors when loading the graph.
        // The actual errors will be printed before exiting.
        guard !diagnostics.hasErrors else {
            throw Error.hasFatalDiagnostics
        }
    }

    /// Fetch and load the complete package graph.
    @discardableResult
    func loadPackageGraph() throws -> PackageGraph {
        do {
            let workspace = try getActiveWorkspace()

            // Fetch and load the package graph.
            let graph = try workspace.loadPackageGraph(
                root: getWorkspaceRoot(), diagnostics: diagnostics)

            // Throw if there were errors when loading the graph.
            // The actual errors will be printed before exiting.
            guard !diagnostics.hasErrors else {
                try buildManifestRegenerationToken().set(valid: false)
                throw Error.hasFatalDiagnostics
            }
            try buildManifestRegenerationToken().set(valid: true)
            return graph
        } catch {
            try buildManifestRegenerationToken().set(valid: false)
            throw error
        }
    }

    /// Returns the user toolchain to compile the actual product.
    func getToolchain() throws -> UserToolchain {
        return try _destinationToolchain.dematerialize()
    }

    func getManifestLoader() throws -> ManifestLoader {
        return try _manifestLoader.dematerialize()
    }

    func shouldRegenerateManifest() throws -> Bool {
        // Check if we are allowed to use llbuild manifest caching.
        guard options.shouldEnableManifestCaching else {
            return true
        }
        
        // Check if we need to generate the llbuild manifest.
        let parameters: BuildParameters = try self.buildParameters()
        guard localFileSystem.isFile(parameters.llbuildManifest) else {
            return true
        }
        
        // Run the target which computes if regeneration is needed.
        let args = [try getToolchain().llbuild.asString, "-f", parameters.llbuildManifest.asString, "regenerate"]
        do {
            try Process.checkNonZeroExit(arguments: args)
        } catch {
            // Regenerate the manifest if this fails for some reason.
            warning(message: "Failed to run the regeneration check: \(error)")
            return true
        }
        return try !self.buildManifestRegenerationToken().isValid()
    }
    
    func computeLLBuildTargetName(for subset: BuildSubset) throws -> String? {
        switch subset {
        case .allExcludingTests:
            return LLBuildManifestGenerator.llbuildMainTargetName
        case .allIncludingTests:
            return LLBuildManifestGenerator.llbuildTestTargetName
        default:
            // FIXME: This is super unfortunate that we might need to load the package graph.
            return try subset.llbuildTargetName(for: loadPackageGraph(), diagnostics: diagnostics)
        }
    }
    
    func build(parameters: BuildParameters, subset: BuildSubset) throws {
        guard let llbuildTargetName = try computeLLBuildTargetName(for: subset) else {
            return
        }
        try runLLBuild(manifest: parameters.llbuildManifest, llbuildTarget: llbuildTargetName)
    }
    
    /// Build a subset of products and targets using swift-build-tool.
    func build(plan: BuildPlan, subset: BuildSubset) throws {
        guard !plan.graph.rootPackages[0].targets.isEmpty else {
            warning(message: "no targets to build in package")
            return
        }

        guard let llbuildTargetName = subset.llbuildTargetName(for: plan.graph, diagnostics: diagnostics) else {
            return
        }

        let yaml = plan.buildParameters.llbuildManifest
        // Generate the llbuild manifest.
        let llbuild = LLBuildManifestGenerator(plan, resolvedFile: try resolvedFilePath())
        try llbuild.generateManifest(at: yaml)

        // Run llbuild.
        try runLLBuild(manifest: yaml, llbuildTarget: llbuildTargetName)

        // Create backwards-compatibilty symlink to old build path.
        let oldBuildPath = buildPath.appending(component: options.configuration.dirname)
        if exists(oldBuildPath) {
            try removeFileTree(oldBuildPath)
        }
        try createSymlink(oldBuildPath, pointingAt: plan.buildParameters.buildPath, relative: true)
    }
    
    func runLLBuild(manifest: AbsolutePath, llbuildTarget: String) throws {
        assert(localFileSystem.isFile(manifest), "llbuild manifest not present: \(manifest.asString)")
        
        // Create a temporary directory for the build process.
        let tempDirName = "org.swift.swiftpm.\(NSUserName())"
        let tempDir = Basic.determineTempDirectory().appending(component: tempDirName)
        try localFileSystem.createDirectory(tempDir, recursive: true)

        // Run the swift-build-tool with the generated manifest.
        var args = [String]()

      #if os(macOS)
        // If enabled, use sandbox-exec on macOS. This provides some safety
        // against arbitrary code execution. We only allow the permissions which
        // are absolutely necessary for performing a build.
        if !options.shouldDisableSandbox {
            let allowedDirectories = [
                tempDir,
                buildPath,
                BuildParameters.swiftpmTestCache
            ].map(resolveSymlinks)
            args += ["sandbox-exec", "-p", sandboxProfile(allowedDirectories: allowedDirectories)]
        }
      #endif

        args += [try getToolchain().llbuild.asString, "-f", manifest.asString, llbuildTarget]
        if verbosity != .concise {
            args.append("-v")
        }

        // Create the environment for llbuild.
        var env = Process.env
        // We override the temporary directory so tools assuming full access to
        // the tmp dir can create files here freely, provided they respect this
        // variable.
        env["TMPDIR"] = tempDir.asString

        // Run llbuild and print output on standard streams.
        let process = Process(arguments: args, environment: env, redirectOutput: false)
        try process.launch()
        try processSet.add(process)
        let result = try process.waitUntilExit()

        guard result.exitStatus == .terminated(code: 0) else {
            throw ProcessResult.Error.nonZeroExit(result)
        }
    }

    func buildManifestRegenerationToken() throws -> BuildManifestRegenerationToken {
        return try _buildManifestRegenerationToken.dematerialize()
    }
    private lazy var _buildManifestRegenerationToken: Result<BuildManifestRegenerationToken, AnyError> = {
        return Result(anyError: {
            let buildParameters = try self.buildParameters()
            return BuildManifestRegenerationToken(tokenFile: buildParameters.regenerateManifestToken)
        })
    }()

    /// Return the build parameters.
    func buildParameters() throws -> BuildParameters {
        return try _buildParameters.dematerialize()
    }
    private lazy var _buildParameters: Result<BuildParameters, AnyError> = {
        return Result(anyError: {
            let toolchain = try self.getToolchain()
            let triple = try Triple(toolchain.destination.target)

            return BuildParameters(
                dataPath: buildPath.appending(component: toolchain.destination.target),
                configuration: options.configuration,
                toolchain: toolchain,
                destinationTriple: triple,
                flags: options.buildFlags,
                shouldLinkStaticSwiftStdlib: options.shouldLinkStaticSwiftStdlib,
                shouldEnableManifestCaching: options.shouldEnableManifestCaching
            )
        })
    }()

    /// Lazily compute the destination toolchain.
    private lazy var _destinationToolchain: Result<UserToolchain, AnyError> = {
        // Create custom toolchain if present.
        if let customDestination = self.options.customCompileDestination {
            return Result(anyError: {
                try UserToolchain(destination: Destination(fromFile: customDestination))
            })
        }
        // Otherwise use the host toolchain.
        return self._hostToolchain
    }()

    /// Lazily compute the host toolchain used to compile the package description.
    private lazy var _hostToolchain: Result<UserToolchain, AnyError> = {
        return Result(anyError: {
            try UserToolchain(destination: Destination.hostDestination(
                        originalWorkingDirectory: self.originalWorkingDirectory))
        })
    }()

    private lazy var _manifestLoader: Result<ManifestLoader, AnyError> = {
        return Result(anyError: {
            try ManifestLoader(
                // Always use the host toolchain's resources for parsing manifest.
                resources: self._hostToolchain.dematerialize().manifestResources,
                isManifestSandboxEnabled: !self.options.shouldDisableSandbox
            )
        })
    }()

    /// An enum indicating the execution status of run commands.
    enum ExecutionStatus {
        case success
        case failure
    }
}

/// An enum representing what subset of the package to build.
enum BuildSubset {
    /// Represents the subset of all products and non-test targets.
    case allExcludingTests

    /// Represents the subset of all products and targets.
    case allIncludingTests

    /// Represents a specific product.
    case product(String)

    /// Represents a specific target.
    case target(String)
}

extension SwiftTool: BuildPlanDelegate {
    public func warning(message: String) {
        // FIXME: Coloring would be nice.
        print("warning: " + message)
    }
}

extension BuildSubset {
    /// Returns the name of the llbuild target that corresponds to the build subset.
    func llbuildTargetName(for graph: PackageGraph, diagnostics: DiagnosticsEngine) -> String? {
        switch self {
        case .allExcludingTests:
            return LLBuildManifestGenerator.llbuildMainTargetName
        case .allIncludingTests:
            return LLBuildManifestGenerator.llbuildTestTargetName
        case .product(let productName):
            guard let product = graph.allProducts.first(where: { $0.name == productName }) else {
                diagnostics.emit(data: ProductNotFoundDiagnostic(productName: productName))
                return nil
            }
            // If the product is automatic, we build the main target because automatic products
            // do not produce a binary right now.
            if product.type == .library(.automatic) {
                diagnostics.emit(data: ProductIsAutomaticDiagnostic(productName: productName))
                return LLBuildManifestGenerator.llbuildMainTargetName
            }
            return product.llbuildTargetName
        case .target(let targetName):
            guard let target = graph.allTargets.first(where: { $0.name == targetName }) else {
                diagnostics.emit(data: TargetNotFoundDiagnostic(targetName: targetName))
                return nil
            }
            return target.llbuildTargetName
        }
    }
}

/// Returns path of the nearest directory containing the manifest file w.r.t
/// current working directory.
private func findPackageRoot() -> AbsolutePath? {
    // FIXME: It would be nice to move this to a generalized method which takes path and predicate and
    // finds the lowest path for which the predicate is true.
    var root = currentWorkingDirectory
    while !isFile(root.appending(component: Manifest.filename)) {
        root = root.parentDirectory
        guard !root.isRoot else {
            return nil
        }
    }
    return root
}

private func getEnvBuildPath() -> AbsolutePath? {
    // Don't rely on build path from env for SwiftPM's own tests.
    guard POSIX.getenv("IS_SWIFTPM_TEST") == nil else { return nil }
    guard let env = POSIX.getenv("SWIFT_BUILD_PATH") else { return nil }
    return AbsolutePath(env, relativeTo: currentWorkingDirectory)
}

/// Returns the sandbox profile to be used when parsing manifest on macOS.
private func sandboxProfile(allowedDirectories: [AbsolutePath]) -> String {
    let stream = BufferedOutputByteStream()
    stream <<< "(version 1)" <<< "\n"
    // Deny everything by default.
    stream <<< "(deny default)" <<< "\n"
    // Import the system sandbox profile.
    stream <<< "(import \"system.sb\")" <<< "\n"
    // Allow reading all files.
    stream <<< "(allow file-read*)" <<< "\n"
    // These are required by the Swift compiler.
    stream <<< "(allow process*)" <<< "\n"
    stream <<< "(allow sysctl*)" <<< "\n"
    // Allow writing in temporary locations.
    stream <<< "(allow file-write*" <<< "\n"
    for directory in Platform.darwinCacheDirectories() {
        // For compiler module cache.
        stream <<< "    (regex #\"^\(directory.asString)/org\\.llvm\\.clang.*\")" <<< "\n"
        // For archive tool.
        stream <<< "    (regex #\"^\(directory.asString)/ar.*\")" <<< "\n"
        // For xcrun cache.
        stream <<< "    (regex #\"^\(directory.asString)/xcrun.*\")" <<< "\n"
        // For autolink files.
        stream <<< "    (regex #\"^\(directory.asString)/.*\\.(swift|c)-[0-9a-f]+\\.autolink\")" <<< "\n"
    }
    for directory in allowedDirectories {
        stream <<< "    (subpath \"\(directory.asString)\")" <<< "\n"
    }
    stream <<< ")" <<< "\n"
    return stream.bytes.asString!
}

extension Build.Configuration: StringEnumArgument {
    public static var completion: ShellCompletion = .values([
        (debug.rawValue, "build with DEBUG configuration"),
        (release.rawValue, "build with RELEASE configuration"),
    ])
}
