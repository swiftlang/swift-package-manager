/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility

extension ModuleProtocol {

    /// Returns the pkgConfig flags (cFlags + libs) escaping the cflags with -Xcc.
    /// FIXME: This isn't correct. We need to scan both list of flags and escape the
    /// flags (using -Xcc and -Xlinker) which can't be passed directly to swift compiler.
    public func pkgConfigSwiftcArgs() throws -> [String] {
        let pkgArgs = try pkgConfigArgs()
        return pkgArgs.cFlags.map{["-Xcc", $0]}.flatten() + pkgArgs.libs
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
            do {
                let pkgConfig = try PkgConfig(name: pkgConfigName)
                cFlags += pkgConfig.cFlags
                libs += pkgConfig.libs
            }
            catch PkgConfigError.CouldNotFindConfigFile {
                if let providers = module.providers,
                    provider = SystemPackageProvider.providerForCurrentPlatform(providers: providers) {
                    print("note: you may be able to install \(pkgConfigName) using your system-packager:\n")
                    print(provider.installText)
                }
            }
        }
        return (cFlags, libs)
    }
}

extension SystemPackageProvider {
    
    var installText: String {
        switch self {
        case .Brew(let name):
            return "    brew install \(name)\n"
        case .Apt(let name):
            return "    apt-get install \(name)\n"
        }
    }
    
    var isAvailable: Bool {
        guard let platform = Platform.currentPlatform else { return false }
        switch self {
        case .Brew(_):
            if case .Darwin = platform  {
                return true
            }
        case .Apt(_):
            if case .Linux(.Debian) = platform  {
                return true
            }
        }
        return false
    }
    
    static func providerForCurrentPlatform(providers: [SystemPackageProvider]) -> SystemPackageProvider? {
        return providers.filter{ $0.isAvailable }.first
    }
}
