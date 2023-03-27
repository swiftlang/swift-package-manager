//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import TSCBasic
import enum TSCUtility.Platform

/// Wrapper struct containing result of a pkgConfig query.
public struct PkgConfigResult {

    /// The name of the pkgConfig file.
    public let pkgConfigName: String

    /// The cFlags from pkgConfig.
    public let cFlags: [String]

    /// The library flags from pkgConfig.
    public let libs: [String]

    /// Available provider, if any.
    public let provider: SystemPackageProviderDescription?

    /// Any error encountered during operation.
    public let error: Swift.Error?

    /// If the pc file was not found.
    public var couldNotFindConfigFile: Bool {
        switch error {
            case PkgConfigError.couldNotFindConfigFile?: return true
            default: return false
        }
    }

    /// Create a result.
    fileprivate init(
        pkgConfigName: String,
        cFlags: [String] = [],
        libs: [String] = [],
        error: Swift.Error? = nil,
        provider: SystemPackageProviderDescription? = nil
    ) {
        self.cFlags = cFlags
        self.libs = libs
        self.error = error
        self.provider = provider
        self.pkgConfigName = pkgConfigName
    }
}

/// Get pkgConfig result for a system library target.
public func pkgConfigArgs(
    for target: SystemLibraryTarget,
    pkgConfigDirectories: [AbsolutePath],
    brewPrefix: AbsolutePath? = .none,
    fileSystem: FileSystem,
    observabilityScope: ObservabilityScope
) throws -> [PkgConfigResult] {
    // If there is no pkg config name defined, we're done.
    guard let pkgConfigNames = target.pkgConfig else { return [] }

    // Compute additional search paths for the provider, if any.
    let provider = target.providers?.first { $0.isAvailable }

    let additionalSearchPaths: [AbsolutePath]
    // Give priority to `pkgConfigDirectories` passed as an argument to this function.
    if let providerSearchPaths = try provider?.pkgConfigSearchPath(brewPrefixOverride: brewPrefix) {
        additionalSearchPaths = pkgConfigDirectories + providerSearchPaths
    } else {
        additionalSearchPaths = pkgConfigDirectories
    }

    var ret: [PkgConfigResult] = []
    // Get the pkg config flags.
    for pkgConfigName in pkgConfigNames.components(separatedBy: " ") {
        let result: PkgConfigResult
        do {
            let pkgConfig = try PkgConfig(
                name: pkgConfigName,
                additionalSearchPaths: additionalSearchPaths,
                brewPrefix: brewPrefix,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope
            )

            // Run the allow list checker.
            let filtered = try allowlist(pcFile: pkgConfigName, flags: (pkgConfig.cFlags, pkgConfig.libs))

            // Remove any default flags which compiler adds automatically.
            let (cFlags, libs) = try removeDefaultFlags(cFlags: filtered.cFlags, libs: filtered.libs)

            // Set the error if there are any disallowed flags.
            var error: Swift.Error?
            if !filtered.disallowed.isEmpty {
                error = PkgConfigError.prohibitedFlags(filtered.disallowed.joined(separator: ", "))
            }

            result = PkgConfigResult(
                pkgConfigName: pkgConfigName,
                cFlags: cFlags,
                libs: libs,
                error: error,
                provider: provider
            )
        } catch {
            result = PkgConfigResult(pkgConfigName: pkgConfigName, error: error, provider: provider)
        }

        // If there is no pc file on system and we have an available provider, emit a warning.
        if let provider = result.provider, result.couldNotFindConfigFile {
            observabilityScope.emit(
                warning: "you may be able to install \(result.pkgConfigName) using your system-packager:\n\(provider.installText)"
            )
        } else if let error = result.error {
            observabilityScope.emit(
                warning: "\(error)",
                metadata: .pkgConfig(pcFile: result.pkgConfigName, targetName: target.name)
            )
        }

        ret.append(result)
    }
    return ret
}

extension SystemPackageProviderDescription {
    public var installText: String {
        switch self {
        case .brew(let packages):
            return "    brew install \(packages.joined(separator: " "))\n"
        case .apt(let packages):
            return "    apt-get install \(packages.joined(separator: " "))\n"
        case .yum(let packages):
            return "    yum install \(packages.joined(separator: " "))\n"
        case .nuget(let packages):
            return "    nuget install \(packages.joined(separator: " "))\n"
        }
    }

    /// Check if the provider is available for the current platform.
    var isAvailable: Bool {
        guard let platform = Platform.current else { return false }
        switch self {
        case .brew:
            if case .darwin = platform {
                return true
            }
        case .apt:
            if case .linux(.debian) = platform {
                return true
            }
            if case .android = platform {
                return true
            }
        case .yum:
            if case .linux(.fedora) = platform {
                return true
            }
        case .nuget:
            switch platform {
            case .darwin, .windows, .linux:
                return true
            case .android:
                return false
            }
        }
        return false
    }

    func pkgConfigSearchPath(brewPrefixOverride: AbsolutePath?) throws -> [AbsolutePath] {
        switch self {
        case .brew(let packages):
            let brewPrefix: String
            if let brewPrefixOverride {
                brewPrefix = brewPrefixOverride.pathString
            } else {
                // Homebrew can have multiple versions of the same package. The
                // user can choose another version than the latest by running
                // ``brew switch NAME VERSION``, so we shouldn't assume to link
                // to the latest version. Instead use the version as symlinked
                // in /usr/local/opt/(NAME)/lib/pkgconfig.
                struct Static {
                    static let value = { try? TSCBasic.Process.checkNonZeroExit(args: "brew", "--prefix").spm_chomp() }()
                }
                if let value = Static.value {
                    brewPrefix = value
                } else {
                    return []
                }
            }
            return try packages.map({ try AbsolutePath(validating: brewPrefix).appending(components: "opt", $0, "lib", "pkgconfig") })
        case .apt:
            return []
        case .yum:
            return []
        case .nuget:
            return []
        }
    }

    // FIXME: Get rid of this method once we move on to new Build code.
    static func providerForCurrentPlatform(providers: [SystemPackageProviderDescription]) -> SystemPackageProviderDescription? {
        return providers.first(where: { $0.isAvailable })
    }
}

/// Filters the flags with allowed arguments so unexpected arguments are not passed to
/// compiler/linker. List of allowed flags:
/// cFlags: -I, -F
/// libs: -L, -l, -F, -framework, -w
public func allowlist(
    pcFile: String,
    flags: (cFlags: [String], libs: [String])
) throws -> (cFlags: [String], libs: [String], disallowed: [String]) {
    // Returns a tuple with the array of allowed flag and the array of disallowed flags.
    func filter(flags: [String], filters: [String]) throws -> (allowed: [String], disallowed: [String]) {
        var allowed = [String]()
        var disallowed = [String]()
        var it = flags.makeIterator()
        while let flag = it.next() {
            guard let filter = filters.filter({ flag.hasPrefix($0) }).first else {
                disallowed += [flag]
                continue
            }

          // Warning suppression flag has no arguments and is not suffixed.
          guard !flag.hasPrefix("-w") || flag == "-w" else {
            disallowed += [flag]
            continue
          }

            // If the flag and its value are separated, skip next flag.
            if flag == filter && flag != "-w" {
                guard let associated = it.next() else {
                    throw InternalError("Expected associated value")
                }
                if flag == "-framework" {
                    allowed += [flag, associated]
                    continue
                }
            }
            allowed += [flag]
        }
        return (allowed, disallowed)
    }

    let filteredCFlags = try filter(flags: flags.cFlags, filters: ["-I", "-F"])
    let filteredLibs = try filter(flags: flags.libs, filters: ["-L", "-l", "-F", "-framework", "-w"])

    return (filteredCFlags.allowed, filteredLibs.allowed, filteredCFlags.disallowed + filteredLibs.disallowed)
}

/// Remove the default flags which are already added by the compiler.
///
/// This behavior is similar to pkg-config cli tool and helps avoid conflicts between
/// sdk and default search paths in macOS.
public func removeDefaultFlags(cFlags: [String], libs: [String]) throws -> ([String], [String]) {
    /// removes a flag from given array of flags.
    func remove(flag: (String, String), from flags: [String]) throws -> [String] {
        var result = [String]()
        var it = flags.makeIterator()
        while let curr = it.next() {
            switch curr {
            case flag.0:
                // Check for <flag><space><value> style.
                guard let val = it.next() else {
                    throw InternalError("Expected associated value")
                }
                // If we found a match, don't add these flags and just skip.
                if val == flag.1 { continue }
                // Otherwise add both the flags.
                result.append(curr)
                result.append(val)

            case flag.0 + flag.1:
                // Check for <flag><value> style.
                continue

            default:
                // Otherwise just append this flag.
                result.append(curr)
            }
        }
        return result
    }
    return (
        try remove(flag: ("-I", "/usr/include"), from: cFlags),
        try remove(flag: ("-L", "/usr/lib"), from: libs)
    )
}

extension ObservabilityMetadata {
    public static func pkgConfig(pcFile: String, targetName: String) -> Self {
        var metadata = ObservabilityMetadata()
        metadata.pcFile = "\(pcFile).pc"
        metadata.targetName = targetName
        return metadata
    }
}

extension ObservabilityMetadata {
    public var pcFile: String? {
        get {
            self[pcFileKey.self]
        }
        set {
            self[pcFileKey.self] = newValue
        }
    }

    enum pcFileKey: Key {
        typealias Value = String
    }
}
