/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import Foundation

/// Recognized Platform types.
public enum Platform: Equatable {
    case android
    case darwin
    case linux(LinuxFlavor)

    /// Recognized flavors of linux.
    public enum LinuxFlavor: Equatable {
        case debian
        case fedora
    }

    /// Lazily checked current platform.
    public static var currentPlatform = Platform._findCurrentPlatform(localFileSystem)
    /// Attempt to match `uname` with recognized platforms.
    public static func _findCurrentPlatform(_ fs: FileSystem) -> Platform? {
        guard let uname = try? Process.checkNonZeroExit(args: "uname").spm_chomp().lowercased() else { return nil }
        switch uname {
        case "darwin":
            return .darwin
        case "linux":
            return Platform._findCurrentPlatformLinux(fs)
        default:
            return nil
        }
    }

    public static func _findCurrentPlatformLinux(_ fs: FileSystem) -> Platform? {
        if fs.isFile(AbsolutePath("/etc/debian_version")) {
            return .linux(.debian)
        }
        if fs.isFile(AbsolutePath("/system/bin/toolbox")) ||
           fs.isFile(AbsolutePath("/system/bin/toybox")) {
            return .android
        }
        if fs.isFile(AbsolutePath("/etc/redhat-release")) ||
           fs.isFile(AbsolutePath("/etc/centos-release")) ||
           fs.isFile(AbsolutePath("/etc/fedora-release")) ||
           Platform.isAmazonLinux2(fs) {
            return .linux(.fedora)
        }

        return nil
    }

    private static func isAmazonLinux2(_ fs: FileSystem) -> Bool {
        do {
            let release = try fs.readFileContents(AbsolutePath("/etc/system-release")).cString
            return release.hasPrefix("Amazon Linux release 2")
        } catch {
            return false
        }
    }

    /// Returns the cache directories used in Darwin.
    public static func darwinCacheDirectories() -> [AbsolutePath] {
        if let value = Platform._darwinCacheDirectories {
            return value
        }
        var directories = [AbsolutePath]()
        // Compute the directories.
        directories.append(AbsolutePath("/private/var/tmp"))
        (try? TSCBasic.determineTempDirectory()).map{ directories.append($0) }
      #if os(macOS)
        getConfstr(_CS_DARWIN_USER_TEMP_DIR).map({ directories.append($0) })
        getConfstr(_CS_DARWIN_USER_CACHE_DIR).map({ directories.append($0) })
      #endif
        Platform._darwinCacheDirectories = directories
        return directories
    }
    private static var _darwinCacheDirectories: [AbsolutePath]?

#if os(macOS)
    /// Returns the value of given path variable using `getconf` utility.
    ///
    /// - Note: This method returns `nil` if the value is an invalid path.
    private static func getConfstr(_ name: Int32) -> AbsolutePath? {
        let len = confstr(name, nil, 0)
        let tmp = UnsafeMutableBufferPointer(start: UnsafeMutablePointer<Int8>.allocate(capacity: len), count:len)
        defer { tmp.deallocate() }
        guard confstr(name, tmp.baseAddress, len) == len else { return nil }
        let value = String(cString: tmp.baseAddress!)
        guard value.hasSuffix(AbsolutePath.root.pathString) else { return nil }
        return resolveSymlinks(AbsolutePath(value))
    }
#endif
}
