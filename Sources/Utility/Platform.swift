/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Foundation

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
      #if os(macOS)
        getConfstr(_CS_DARWIN_USER_TEMP_DIR).map({ directories.append($0) })
        getConfstr(_CS_DARWIN_USER_CACHE_DIR).map({ directories.append($0) })
      #endif
        Platform._darwinCacheDirectories = directories
        return directories
    }
    private static var _darwinCacheDirectories: [AbsolutePath]?

    /// Returns the value of given path variable using `getconf` utility.
    ///
    /// Note: This method returns `nil` if the value is an invalid path.
    private static func getConfstr(_ name: Int32) -> AbsolutePath? {
        let len = confstr(name, nil, 0)
        let tmp = UnsafeMutableBufferPointer(start: UnsafeMutablePointer<Int8>.allocate(capacity: len), count:len)
        guard confstr(name, tmp.baseAddress, len) == len else { return nil }
        let value = String(cString: tmp.baseAddress!)
        guard value.hasSuffix(AbsolutePath.root.asString) else { return nil }
        return resolveSymlinks(AbsolutePath(value))
    }
}
