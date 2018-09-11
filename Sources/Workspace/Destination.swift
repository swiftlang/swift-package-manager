import Basic
import Build
import Utility
import POSIX

enum DestinationError: Swift.Error {
    /// Couldn't find the Xcode installation.
    case invalidInstallation(String)

    /// The schema version is invalid.
    case invalidSchemaVersion
}

extension DestinationError: CustomStringConvertible {
    var description: String {
        switch self {
        case .invalidSchemaVersion:
            return "unsupported destination file schema version"
        case .invalidInstallation(let problem):
            return problem
        }
    }
}

/// The compilation destination, has information about everything that's required for a certain destination.
public struct Destination {

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
    public let target: String

    /// The SDK used to compile for the destination.
    public let sdk: AbsolutePath

    /// The binDir in the containing the compilers/linker to be used for the compilation.
    public let binDir: AbsolutePath

    /// The file extension for dynamic libraries (eg. `.so` or `.dylib`)
    public let dynamicLibraryExtension: String

    /// Additional flags to be passed to the C compiler.
    public let extraCCFlags: [String]

    /// Additional flags to be passed to the Swift compiler.
    public let extraSwiftCFlags: [String]

    /// Additional flags to be passed when compiling with C++.
    public let extraCPPFlags: [String]

    /// Returns the bin directory for the host.
    ///
    /// - Parameter originalWorkingDirectory: The working directory when the program was launched.
    private static func hostBinDir(
        originalWorkingDirectory: AbsolutePath? = localFileSystem.currentWorkingDirectory
    ) -> AbsolutePath {
      #if Xcode
        // For Xcode, set bin directory to the build directory containing the fake
        // toolchain created during bootstraping. This is obviously not production ready
        // and only exists as a development utility right now.
        //
        // This also means that we should have bootstrapped with the same Swift toolchain
        // we're using inside Xcode otherwise we will not be able to load the runtime libraries.
        //
        // FIXME: We may want to allow overriding this using an env variable but that
        // doesn't seem urgent or extremely useful as of now.
        return AbsolutePath(#file).parentDirectory
            .parentDirectory.parentDirectory.appending(components: ".build", hostTargetTriple.tripleString, "debug")
      #else
        guard let cwd = originalWorkingDirectory else {
            return try! AbsolutePath(validating: CommandLine.arguments[0]).parentDirectory
        }
        return AbsolutePath(CommandLine.arguments[0], relativeTo: cwd).parentDirectory
      #endif
    }

    /// The destination describing the host OS.
    public static func hostDestination(
        _ binDir: AbsolutePath? = nil,
        originalWorkingDirectory: AbsolutePath? = localFileSystem.currentWorkingDirectory,
        environment: [String:String] = Process.env
    ) throws -> Destination {
        // Select the correct binDir.
        let binDir = binDir ?? Destination.hostBinDir(
            originalWorkingDirectory: originalWorkingDirectory)

        let sdkPath: AbsolutePath

        // Get the SDK.
        if let value = lookupExecutablePath(filename: getenv("SYSROOT")) {
            sdkPath = value
        } else {
            #if os(macOS)
            // No value in env, so search for it.
            let sdkPathStr = try Process.checkNonZeroExit(
                arguments: ["xcrun", "--sdk", "macosx", "--show-sdk-path"], environment: environment).spm_chomp()
            guard !sdkPathStr.isEmpty else {
                throw DestinationError.invalidInstallation("default SDK not found")
            }
            sdkPath = AbsolutePath(sdkPathStr)
            #else
            sdkPath = .root
            #endif
        }

        // Compute common arguments for clang and swift.
        // This is currently just frameworks path on Apple platforms.
        let commonArgs = hostTargetTriple.isDarwin ? (Destination.sdkPlatformFrameworkPath(environment: environment).map({ ["-F", $0.asString] }) ?? []) : []
        let ccArgs = hostTargetTriple.isLinux ? ["-fPIC"] : []

        return Destination(
            target: hostTargetTriple.tripleString,
            sdk: sdkPath,
            binDir: binDir,
            dynamicLibraryExtension: hostTargetTriple.dynamicLibraryExtension,
            extraCCFlags: commonArgs + ccArgs,
            extraSwiftCFlags: commonArgs,
            extraCPPFlags: hostTargetTriple.defaultCxxRuntimeLibrary.flatMap { ["-l\($0)"] } ?? []
        )
    }

    /// Returns macosx sdk platform framework path.
    public static func sdkPlatformFrameworkPath(environment: [String:String] = Process.env) -> AbsolutePath? {
        if let path = _sdkPlatformFrameworkPath {
            return path
        }
        let platformPath = try? Process.checkNonZeroExit(
            arguments: ["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"], environment: environment).spm_chomp()

        if let platformPath = platformPath, !platformPath.isEmpty {
           _sdkPlatformFrameworkPath = AbsolutePath(platformPath).appending(
                components: "Developer", "Library", "Frameworks")
        }
        return _sdkPlatformFrameworkPath
    }
    /// Cache storage for sdk platform path.
    private static var _sdkPlatformFrameworkPath: AbsolutePath? = nil

    /// Target triple for the host system.
    private static let hostTargetTriple = Triple.hostTriple
}

extension Triple {
    public var dynamicLibraryExtension: String {
        switch os {
        case .Darwin, .iOS, .macOS, .tvOS, .watchOS:
            return "dylib"
        case .FreeBSD, .Linux, .Haiku, .PS4:
            return "so"
        case .Windows:
            return "dll"
        case .unknown:
            fatalError("dynamicLibraryExtension not implemented for \(os)")
        }
    }

    public var defaultCxxRuntimeLibrary: String? {
        switch os {
        case .Darwin, .iOS, .macOS, .tvOS, .watchOS, .FreeBSD, .PS4:
            return "c++" // LLVM libc++
        case .Linux, .Haiku:
            return "stdc++" // GNU libstdc++
        case .Windows:
            return nil // Built-in with MSVC
        case .unknown:
            fatalError("defaultCxxRuntimeLibrary not implemented for \(os)")
        }
    }
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
            target: json.get("target"),
            sdk: AbsolutePath(json.get("sdk")),
            binDir: AbsolutePath(json.get("toolchain-bin-dir")),
            dynamicLibraryExtension: json.get("dynamic-library-extension"),
            extraCCFlags: json.get("extra-cc-flags"),
            extraSwiftCFlags: json.get("extra-swiftc-flags"),
            extraCPPFlags: json.get("extra-cpp-flags")
        )
    }
}
