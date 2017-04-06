/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

public enum Platform {
    case darwin
    case linux(LinuxFlavor)

    public enum LinuxFlavor {
        case debian
    }

    // Lazily return current platform.
    public static var currentPlatform = Platform.findCurrentPlatform()
    private static func findCurrentPlatform() -> Platform? {
        guard let uname = try? Process.checkNonZeroExit(args: "uname").chomp().lowercased() else { return nil }
        switch uname {
        case "darwin":
            return .darwin
        case "linux":
            if isFile(AbsolutePath("/etc/debian_version")) {
                return .linux(.debian)
            }
        default:
            return nil
        }
        return nil
    }

    /// Returns the cache directories used in Darwin.
    public static func darwinCacheDirectories() -> [AbsolutePath] {
        if let value = Platform._darwinCacheDirectories {
            return value
        }
        var directories = [AbsolutePath]()
        // Compute the directories.
        directories.append(AbsolutePath("/private/var/tmp"))
        directories.append(Basic.determineTempDirectory())
        getconfPath(forVariable: "DARWIN_USER_TEMP_DIR").map({ directories.append($0) })
        getconfPath(forVariable: "DARWIN_USER_CACHE_DIR").map({ directories.append($0) })
        Platform._darwinCacheDirectories = directories
        return directories
    }
    private static var _darwinCacheDirectories: [AbsolutePath]?

    /// Returns the value of given path variable using `getconf` utility.
    ///
    /// Note: This method returns `nil` if the value is an invalid path.
    private static func getconfPath(forVariable variable: String) -> AbsolutePath? {
        do {
            let value = try Process.checkNonZeroExit(args: "getconf", variable).chomp()
            // Value must be a valid path.
            guard value.hasSuffix(AbsolutePath.root.asString) else { return nil }
            return resolveSymlinks(AbsolutePath(value))
        } catch {
            return nil
        }
    }
}
