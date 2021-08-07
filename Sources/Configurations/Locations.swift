/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

//import Basics
//import Foundation
//import TSCBasic
//import TSCUtility

/*
extension FileSystem {

    func mirrorsFilePath() throws -> AbsolutePath {
        // Look for the override in the environment.
        if let envPath = ProcessEnv.vars["SWIFTPM_MIRROR_CONFIG"] {
            return try AbsolutePath(validating: envPath)
        }

        // Otherwise, use the default path.
        if let multiRootPackageDataFile = options.multirootPackageDataFile {
            return multiRootPackageDataFile.appending(components: "xcshareddata", "swiftpm", "config")
        }
        return try getPackageRoot().appending(components: ".swiftpm", "config")
    }

    func netrcFilePath() throws -> AbsolutePath? {
        guard options.netrc ||
                options.netrcFilePath != nil ||
                options.netrcOptional else { return nil }

        let resolvedPath: AbsolutePath = options.netrcFilePath ?? AbsolutePath("\(NSHomeDirectory())/.netrc")
        guard localFileSystem.exists(resolvedPath) else {
            if !options.netrcOptional {
                diagnostics.emit(error: "Cannot find mandatory .netrc file at \(resolvedPath.pathString).  To make .netrc file optional, use --netrc-optional flag.")
                throw ExitCode.failure
            } else {
                diagnostics.emit(warning: "Did not find optional .netrc file at \(resolvedPath.pathString).")
                return nil
            }
        }
        return resolvedPath
    }


    private func getConfigPath(fileSystem: FileSystem) throws -> AbsolutePath? {
        if let explicitConfigPath = options.configPath {
            // Create the explicit config path if necessary
            if !fileSystem.exists(explicitConfigPath) {
                try fileSystem.createDirectory(explicitConfigPath, recursive: true)
            }
            return explicitConfigPath
        }

        do {
            return try fileSystem.getOrCreateSwiftPMConfigDirectory()
        } catch {
            self.diagnostics.emit(warning: "Failed creating default config locations, \(error)")
            return nil
        }
    }

}
*/
