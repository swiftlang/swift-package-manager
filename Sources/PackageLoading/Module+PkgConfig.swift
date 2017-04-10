/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import Utility

/// Wrapper struct containing result of a pkgConfig query.
public struct PkgConfigResult {

    /// The name of the pkgConfig file.
    public let pkgConfigName: String

    /// The cFlags from pkgConfig.
    public let cFlags: [String]

    /// The library flags from pkgConfig.
    public let libs: [String]

    /// Available provider, if any.
    public let provider: SystemPackageProvider?

    /// Any error encountered during operation.
    public let error: Swift.Error?

    /// If the pc file was not found.
    public var couldNotFindConfigFile: Bool {
        switch error {
            case PkgConfigError.couldNotFindConfigFile?: return true
            default: return false
        }
    }

    /// Create a successful result with given cflags and libs.
    fileprivate init(pkgConfigName: String, cFlags: [String], libs: [String]) {
        self.pkgConfigName = pkgConfigName
        self.cFlags = cFlags
        self.libs = libs
        self.error = nil
        self.provider = nil
    }

    /// Create an error result.
    fileprivate init(pkgConfigName: String, error: Swift.Error, provider: SystemPackageProvider?) {
        self.cFlags = []
        self.libs = []
        self.error = error
        self.provider = provider
        self.pkgConfigName = pkgConfigName
    }
}

/// Get pkgConfig result for a CTarget.
public func pkgConfigArgs(for target: CTarget, fileSystem: FileSystem = localFileSystem) -> PkgConfigResult? {
    // If there is no pkg config name defined, we're done.
    guard let pkgConfigName = target.pkgConfig else { return nil }
    // Compute additional search paths for the provider, if any.
    let provider = target.providers?.first { $0.isAvailable }
    let additionalSearchPaths = provider?.pkgConfigSearchPath() ?? []
    // Get the pkg config flags.
    do {
        let pkgConfig = try PkgConfig(
            name: pkgConfigName,
            additionalSearchPaths: additionalSearchPaths,
            fileSystem: fileSystem)
        // Run the whitelist checker.
        try whitelist(pcFile: pkgConfigName, flags: (pkgConfig.cFlags, pkgConfig.libs))
        // Remove any default flags which compiler adds automatically.
        let (cFlags, libs) = removeDefaultFlags(cFlags: pkgConfig.cFlags, libs: pkgConfig.libs)
        return PkgConfigResult(pkgConfigName: pkgConfigName, cFlags: cFlags, libs: libs)
    } catch {
        return PkgConfigResult(pkgConfigName: pkgConfigName, error: error, provider: provider)
    }
}

extension SystemPackageProvider {
    public var installText: String {
        switch self {
        case .brewItem(let packages):
            return "    brew install \(packages.joined(separator: " "))\n"
        case .aptItem(let packages):
            return "    apt-get install \(packages.joined(separator: " "))\n"
        }
    }

    /// Check if the provider is available for the current platform.
    var isAvailable: Bool {
        guard let platform = Platform.currentPlatform else { return false }
        switch self {
        case .brewItem:
            if case .darwin = platform {
                return true
            }
        case .aptItem:
            if case .linux(.debian) = platform {
                return true
            }
        }
        return false
    }

    func pkgConfigSearchPath() -> [AbsolutePath] {
        switch self {
        case .brewItem(let packages):
            // Homebrew can have multiple versions of the same package. The
            // user can choose another version than the latest by running
            // ``brew switch NAME VERSION``, so we shouldn't assume to link
            // to the latest version. Instead use the version as symlinked
            // in /usr/local/opt/(NAME)/lib/pkgconfig.
            struct Static {
                static let value = { try? Process.checkNonZeroExit(args: "brew", "--prefix").chomp() }()
            }
            guard let brewPrefix = Static.value else { return [] }
            return packages.map({ AbsolutePath(brewPrefix).appending(components: "opt", $0, "lib", "pkgconfig") })
        case .aptItem:
            return []
        }
    }

    // FIXME: Get rid of this method once we move on to new Build code.
    static func providerForCurrentPlatform(providers: [SystemPackageProvider]) -> SystemPackageProvider? {
        return providers.first(where: { $0.isAvailable })
    }
}

/// Filters the flags with allowed arguments so unexpected arguments are not passed to
/// compiler/linker. List of allowed flags:
/// cFlags: -I, -F
/// libs: -L, -l, -F, -framework
func whitelist(pcFile: String, flags: (cFlags: [String], libs: [String])) throws {
    // Returns an array of flags which doesn't match any filter.
    func filter(flags: [String], filters: [String]) -> [String] {
        var filtered = [String]()
        var it = flags.makeIterator()
        while let flag = it.next() {
            guard let filter = filters.filter({ flag.hasPrefix($0) }).first else {
                filtered += [flag]
                continue
            }
            // If the flag and its value are separated, skip next flag.
            if flag == filter {
                guard it.next() != nil else {
                   fatalError("Expected associated value")
                }
            }
        }
        return filtered
    }
    let filtered = filter(flags: flags.cFlags, filters: ["-I", "-F"]) +
        filter(flags: flags.libs, filters: ["-L", "-l", "-F", "-framework"])
    guard filtered.isEmpty else {
        throw PkgConfigError.nonWhitelistedFlags("Non whitelisted flags found: \(filtered) in pc file \(pcFile)")
    }
}

/// Remove the default flags which are already added by the compiler.
///
/// This behavior is similar to pkg-config cli tool and helps avoid conflicts between
/// sdk and default search paths in macOS.
func removeDefaultFlags(cFlags: [String], libs: [String]) -> ([String], [String]) {
    /// removes a flag from given array of flags.
    func remove(flag: (String, String), from flags: [String]) -> [String] {
        var result = [String]()
        var it = flags.makeIterator()
        while let curr = it.next() {
            switch curr {
            case flag.0:
                // Check for <flag><space><value> style.
                guard let val = it.next() else {
                    fatalError("Expected associated value")
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
    return (remove(flag: ("-I", "/usr/include"), from: cFlags), remove(flag: ("-L", "/usr/lib"), from: libs))
}
