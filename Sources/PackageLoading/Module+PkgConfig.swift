/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import POSIX
import PackageModel
import Utility

extension Module {
    /// Returns the pkgConfig flags (cFlags + libs) escaping the cflags with -Xcc.
    //
    // FIXME: This isn't correct. We need to scan both list of flags and escape
    // the flags (using -Xcc and -Xlinker) which can't be passed directly to
    // swift compiler.
    public func pkgConfigSwiftcArgs() throws -> [String] {
        let pkgArgs = try pkgConfigArgs()
        return pkgArgs.cFlags.flatMap{ ["-Xcc", $0] } + pkgArgs.libs
    }

    /// Finds cFlags and link flags for all the CModule i.e. System Module
    /// dependencies of a module for which a pkgConfigName is provided in the
    /// manifest file. Also prints the help text in case the .pc file
    /// for that System Module is not found.
    /// Note: The flags are exactly what one would get from pkg-config without
    /// any escaping like -Xcc or -Xlinker which is needed for swift compiler.
    public func pkgConfigArgs() throws -> (cFlags: [String], libs: [String]) {
        var cFlags = [String]()
        var libs = [String]()
        try recursiveDependencies.forEach { module in
            guard case let module as CModule = module, let pkgConfigName = module.pkgConfig else {
                return
            }
            var pkgConfigProviderSearchPaths = [AbsolutePath]()
            if let providers = module.providers,
                let provider = SystemPackageProvider.providerForCurrentPlatform(providers: providers),
                let providerSearchPath = provider.pkgConfigSearchPath() {
                pkgConfigProviderSearchPaths.append(providerSearchPath)
            }
            do {
                let pkgConfig = try PkgConfig(name: pkgConfigName.asString, additionalSearchPaths: pkgConfigProviderSearchPaths)
                cFlags += pkgConfig.cFlags
                libs += pkgConfig.libs
                try whitelist(pcFile: pkgConfigName.asString, flags: (cFlags, libs))
            }
            catch PkgConfigError.couldNotFindConfigFile {
                if let providers = module.providers,
                    let provider = SystemPackageProvider.providerForCurrentPlatform(providers: providers) {
                    print("note: you may be able to install \(pkgConfigName.asString) using your system-packager:\n")
                    print(provider.installText)
                }
            }
        }
        return removeDefaultFlags(cFlags: cFlags, libs: libs)
    }
}

private extension SystemPackageProvider {
    var installText: String {
        switch self {
        case .Brew(let name):
            return "    brew install \(name)\n"
        case .Apt(let name):
            return "    apt-get install \(name)\n"
        }
    }

    /// Check if the provider is available for the current platform.
    var isAvailable: Bool {
        guard let platform = Platform.currentPlatform else { return false }
        switch self {
        case .Brew(_):
            if case .darwin = platform  {
                return true
            }
        case .Apt(_):
            if case .linux(.debian) = platform  {
                return true
            }
        }
        return false
    }

    func pkgConfigSearchPath() -> AbsolutePath? {
        switch self {
        case .Brew(let name):
            // Homebrew can have multiple versions of the same package. The
            // user can choose another version than the latest by running
            // ``brew switch NAME VERSION``, so we shouldn't assume to link
            // to the latest version. Instead use the version as symlinked
            // in /usr/local/opt/(NAME)/lib/pkgconfig.
            struct Static {
                static let value = { try? Utility.popen(["brew", "--prefix"]).chomp() }()
            }
            guard let brewPrefix = Static.value else {
                return nil
            }
            return AbsolutePath(brewPrefix).appending(components: "opt", name, "lib", "pkgconfig")
        case .Apt:
            return nil
        }
    }

    static func providerForCurrentPlatform(providers: [SystemPackageProvider]) -> SystemPackageProvider? {
        return providers.filter{ $0.isAvailable }.first
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
                guard let _ = it.next() else {
                   fatalError("Expected associated value") 
                }
            }
        }
        return filtered
    }
    let filtered = filter(flags: flags.cFlags, filters: ["-I", "-F"]) + filter(flags: flags.libs, filters: ["-L", "-l", "-F", "-framework"])
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
