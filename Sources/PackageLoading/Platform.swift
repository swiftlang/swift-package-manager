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

@_implementationOnly
import Foundation

import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
import var TSCBasic.localFileSystem
import class TSCBasic.Process

private func isAndroid() -> Bool {
    (try? localFileSystem.isFile(AbsolutePath(validating: "/system/bin/toolchain"))) ?? false ||
        (try? localFileSystem.isFile(AbsolutePath(validating: "/system/bin/toybox"))) ?? false
}

public enum Platform: Equatable {
    case android
    case darwin
    case linux(LinuxFlavor)
    case windows

    /// Recognized flavors of linux.
    public enum LinuxFlavor: Equatable {
        case debian
        case fedora
    }
}

extension Platform {
    // This is not just a computed property because the ToolchainRegistryTests
    // change the value.
    public static var current: Platform? = {
        #if os(Windows)
        return .windows
        #else
        switch try? Process.checkNonZeroExit(args: "uname")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
        case "darwin"?:
            return .darwin
        case "linux"?:
            return Platform.findCurrentPlatformLinux(localFileSystem)
        default:
            return nil
        }
        #endif
    }()

    private static func findCurrentPlatformLinux(_ fileSystem: FileSystem) -> Platform? {
        do {
            if try fileSystem.isFile(AbsolutePath(validating: "/etc/debian_version")) {
                return .linux(.debian)
            }
            if try fileSystem.isFile(AbsolutePath(validating: "/system/bin/toolbox")) ||
                fileSystem.isFile(AbsolutePath(validating: "/system/bin/toybox"))
            {
                return .android
            }
            if try fileSystem.isFile(AbsolutePath(validating: "/etc/redhat-release")) ||
                fileSystem.isFile(AbsolutePath(validating: "/etc/centos-release")) ||
                fileSystem.isFile(AbsolutePath(validating: "/etc/fedora-release")) ||
                Platform.isAmazonLinux2(fileSystem)
            {
                return .linux(.fedora)
            }
        } catch {}

        return nil
    }

    private static func isAmazonLinux2(_ fileSystem: FileSystem) -> Bool {
        do {
            let release = try fileSystem.readFileContents(AbsolutePath(validating: "/etc/system-release")).cString
            return release.hasPrefix("Amazon Linux release 2")
        } catch {
            return false
        }
    }
}

extension Platform {
    /// The file extension used for a dynamic library on this platform.
    public var dynamicLibraryExtension: String {
        switch self {
        case .darwin: return ".dylib"
        case .linux, .android: return ".so"
        case .windows: return ".dll"
        }
    }

    public var executableExtension: String {
        switch self {
        case .windows: return ".exe"
        case .linux, .android, .darwin: return ""
        }
    }
}
