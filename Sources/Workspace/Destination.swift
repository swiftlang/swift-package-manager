import TSCBasic
import TSCUtility
import Build
import SPMBuildCore

public enum DestinationError: Swift.Error {
    /// Couldn't find the Xcode installation.
    case invalidInstallation(String)

    /// The schema version is invalid.
    case invalidSchemaVersion
}

extension DestinationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidSchemaVersion:
            return "unsupported destination file schema version"
        case .invalidInstallation(let problem):
            return problem
        }
    }
}

/// The compilation destination, has information about everything that's required for a certain destination.
public struct Destination: Encodable, Equatable {

    /// The clang/LLVM triple describing the target OS and architecture.
    ///
    /// The triple has the general format <arch><sub>-<vendor>-<sys>-<abi>, where:
    ///  - arch = x86_64, i386, arm, thumb, mips, etc.
    ///  - sub = for ex. on ARM: v5, v6m, v7a, v7m, etc.
    ///  - vendor = pc, apple, nvidia, ibm, etc.
    ///  - sys = none, linux, win32, darwin, cuda, etc.
    ///  - abi = eabi, gnu, android, macho, elf, etc.
    ///
    /// for more information see //https://clang.llvm.org/docs/CrossCompilation.html
    public var target: Triple?

    /// The architectures to build for. We build for host architecture if this is empty.
    public var archs: [String] = []

    /// The SDK used to compile for the destination.
    public var sdk: AbsolutePath?

    /// The binDir in the containing the compilers/linker to be used for the compilation.
    public var binDir: AbsolutePath

    /// Additional flags to be passed to the C compiler.
    public let extraCCFlags: [String]

    /// Additional flags to be passed to the Swift compiler.
    public let extraSwiftCFlags: [String]

    /// Additional flags to be passed when compiling with C++.
    public let extraCPPFlags: [String]

    /// Creates a compilation destination with the specified properties.
    public init(
      target: Triple? = nil,
      sdk: AbsolutePath?,
      binDir: AbsolutePath,
      extraCCFlags: [String] = [],
      extraSwiftCFlags: [String] = [],
      extraCPPFlags: [String] = []
    ) {
      self.target = target
      self.sdk = sdk
      self.binDir = binDir
      self.extraCCFlags = extraCCFlags
      self.extraSwiftCFlags = extraSwiftCFlags
      self.extraCPPFlags = extraCPPFlags
    }

    /// Returns the bin directory for the host.
    ///
    /// - Parameter originalWorkingDirectory: The working directory when the program was launched.
    private static func hostBinDir(
        originalWorkingDirectory: AbsolutePath? = localFileSystem.currentWorkingDirectory
    ) -> AbsolutePath {
        guard let cwd = originalWorkingDirectory else {
            return try! AbsolutePath(validating: CommandLine.arguments[0]).parentDirectory
        }
        return AbsolutePath(CommandLine.arguments[0], relativeTo: cwd).parentDirectory
    }

    /// The destination describing the host OS.
    public static func hostDestination(
        _ binDir: AbsolutePath? = nil,
        originalWorkingDirectory: AbsolutePath? = localFileSystem.currentWorkingDirectory,
        environment: [String:String] = ProcessEnv.vars
    ) throws -> Destination {
        // Select the correct binDir.
        let customBinDir = ProcessEnv
            .vars["SWIFTPM_CUSTOM_BINDIR"]
            .flatMap{ try? AbsolutePath(validating: $0) }
        let binDir = customBinDir ?? binDir ?? Destination.hostBinDir(
            originalWorkingDirectory: originalWorkingDirectory)

        let sdkPath: AbsolutePath?
#if os(macOS)
        // Get the SDK.
        if let value = lookupExecutablePath(filename: ProcessEnv.vars["SDKROOT"]) {
            sdkPath = value
        } else {
            // No value in env, so search for it.
            let sdkPathStr = try Process.checkNonZeroExit(
                arguments: ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"], environment: environment).spm_chomp()
            guard !sdkPathStr.isEmpty else {
                throw DestinationError.invalidInstallation("default SDK not found")
            }
            sdkPath = AbsolutePath(sdkPathStr)
        }
#else
        sdkPath = nil
#endif

        // Compute common arguments for clang and swift.
        var extraCCFlags: [String] = []
        var extraSwiftCFlags: [String] = []
#if os(macOS)
        if let sdkPaths = Destination.sdkPlatformFrameworkPaths(environment: environment) {
            extraCCFlags += ["-F", sdkPaths.fwk.pathString]
            extraSwiftCFlags += ["-F", sdkPaths.fwk.pathString]
            extraSwiftCFlags += ["-I", sdkPaths.lib.pathString]
            extraSwiftCFlags += ["-L", sdkPaths.lib.pathString]
        }
#endif

#if !os(Windows)
        extraCCFlags += ["-fPIC"]
#endif

        var extraCPPFlags: [String] = []
#if os(macOS)
        extraCPPFlags += ["-lc++"]
#elseif os(Windows)
        extraCPPFlags += []
#else
        extraCPPFlags += ["-lstdc++"]
#endif

        return Destination(
            target: nil,
            sdk: sdkPath,
            binDir: binDir,
            extraCCFlags: extraCCFlags,
            extraSwiftCFlags: extraSwiftCFlags,
            extraCPPFlags: extraCPPFlags
        )
    }

    /// Returns macosx sdk platform framework path.
    public static func sdkPlatformFrameworkPaths(
        environment: [String: String] = ProcessEnv.vars
    ) -> (fwk: AbsolutePath, lib: AbsolutePath)? {
        if let path = _sdkPlatformFrameworkPath {
            return path
        }
        let platformPath = try? Process.checkNonZeroExit(
            arguments: ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-platform-path"],
            environment: environment).spm_chomp()

        if let platformPath = platformPath, !platformPath.isEmpty {
            // For XCTest framework.
            let fwk = AbsolutePath(platformPath).appending(
                components: "Developer", "Library", "Frameworks")

            // For XCTest Swift library.
            let lib = AbsolutePath(platformPath).appending(
                components: "Developer", "usr", "lib")

            _sdkPlatformFrameworkPath = (fwk, lib)
        }
        return _sdkPlatformFrameworkPath
    }
    /// Cache storage for sdk platform path.
    private static var _sdkPlatformFrameworkPath: (fwk: AbsolutePath, lib: AbsolutePath)? = nil
}

extension Destination {

    /// Load a Destination description from a JSON representation from disk.
    public init(fromFile path: AbsolutePath, fileSystem: FileSystem = localFileSystem) throws {
        let json = try JSON(bytes: fileSystem.readFileContents(path))
        try self.init(json: json)
    }
}

extension Destination: JSONMappable {

    /// The current schema version.
    static let schemaVersion = 1

    public init(json: JSON) throws {

        // Check schema version.
        guard try json.get("version") == Destination.schemaVersion else {
            throw DestinationError.invalidSchemaVersion
        }

        try self.init(
            target: Triple(json.get("target")),
            sdk: AbsolutePath(json.get("sdk")),
            binDir: AbsolutePath(json.get("toolchain-bin-dir")),
            extraCCFlags: json.get("extra-cc-flags"),
            extraSwiftCFlags: json.get("extra-swiftc-flags"),
            extraCPPFlags: json.get("extra-cpp-flags")
        )
    }
}
