/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
 This file defines support functions for resources tied to the installed
 location of the containing product binary.
*/

import libc
import POSIX

public final class Resources {
    /// The registered path of the main executable.
    private static var registeredMainExecutablePath: String? = nil

    /// Initialize the resources support.
    ///
    /// This function should be called from the module defining the executable
    /// using code like the following:
    ///
    ///     public var globalSymbolInMainBinary = 0
    ///     Resources.initialize(&globalSymbolInMainBinary)
    ///
    /// - Parameter globalSymbolInMainBinary: The address of a (public) symbol
    ///   defined in main binary. The actual contents of the symbol are
    ///   irrelevant, this is just used in order to be able to locate the main
    ///   binary path.
    public static func initialize(inout globalSymbolInMainBinary: Int) {
        precondition(Resources.registeredMainExecutablePath == nil, "resources already initialized")
        precondition(Resources._resourcePaths == nil, "resource paths already computed")

#if os(Linux)
        // Infer the path from argv[0].
        if !Process.arguments.isEmpty {
            Resources.registeredMainExecutablePath = try! Process.arguments[0].abspath()
        }
#else
        // Look up the information from dlopen.
        //
        // FIXME: There are even-more-platform-dependent ways to do this more
        // efficiently on most platforms, but they require access to more features
        // than are exposed via libc.
        var dlinfo = Dl_info()
        if dladdr(&globalSymbolInMainBinary, &dlinfo) != 0 {
            if let path = String.fromCString(dlinfo.dli_fname) {
                Resources.registeredMainExecutablePath = try? realpath(path)
            }
        }
#endif
    }

    /// Get the expected install path.
    public static var installPath: String {
        // Compute the resource paths, if not cached.
        if _resourcePaths == nil {
            _resourcePaths = computeResourcesPaths()
        }
        return _resourcePaths!.install
    }

    /// Get the expected path containing executables.
    public static var executablesPath: String? {
        // Compute the resource paths, if not cached.
        if _resourcePaths == nil {
            _resourcePaths = computeResourcesPaths()
        }
        return _resourcePaths!.executable
    }
    
    /// Get the runtime library path.
    public static var runtimeLibPath: String {
        return Path.join(installPath, "lib", "swift", "pm")
    }
    
    /// Compute the paths for resources.
    private static func computeResourcesPaths() -> (install: String, executable: String?) {
        // If there is an override in the environment, honor it (this is used for testing).
        if let installPath = POSIX.getenv("SPM_INSTALL_PATH") {
            return (install: installPath, executable: Path.join(installPath, "bin"))
        }
        
        // If we have an executable path, the install path is one directory up.
        if let mainExecPath = Resources.registeredMainExecutablePath {
            return (install: Path.join(mainExecPath, "..", "..").normpath, executable: Path.join(mainExecPath, "..").normpath)
        }

        // Otherwise, we give up. Assume we are installed in /usr.
        return (install: "/usr", executable: nil)
    }
    private static var _resourcePaths: (install: String, executable: String?)?
    
    /// Get the main executable path, if registered.
    public static func getMainExecutable() -> String? {
        return registeredMainExecutablePath
    }
    
    /// Search for an executable, searching adjacent to the main executable, if
    /// known, before searching the PATH.
    ///
    /// - Returns: The absolute path to the found executable, or the provided
    ///   name if not found in any location.
    public static func findExecutable(name: String) -> String {
        // If we have an executable path, look adjacent to it first.
        if let executablesPath = executablesPath {
            let p = Path.join(executablesPath, name)
            if p.exists {
                return p
            }
        }

        // FIXME: Otherwise, search PATH.
        
        return name
    }
}
