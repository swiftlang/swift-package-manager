/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

/// Triple - Helper class for working with Destination.target values
///
/// Used for parsing values such as x86_64-apple-macosx10.10 into
/// set of enums. For os/arch/abi based conditions in build plan.
///
/// @see Destination.target
/// @see https://github.com/apple/swift-llvm/blob/stable/include/llvm/ADT/Triple.h
///
public struct Triple {
    public let tripleString: String

    public let arch: Arch
    public let vendor: Vendor
    public let os: OS
    public let abi: ABI

    public enum Error: Swift.Error {
        case badFormat
        case unknownArch
        case unknownOS
    }

    public enum Arch: String {
        case x86_64
        case i686
        case powerpc64le
        case s390x
        case aarch64
        case armv7
        case arm
    }

    public enum Vendor: String {
        case unknown
        case apple
    }

    public enum OS: String {
        case darwin
        case macOS = "macosx"
        case linux
        case windows

        fileprivate static let allKnown:[OS] = [
            .darwin,
            .macOS,
            .linux,
            .windows
        ]
    }

    public enum ABI: String {
        case unknown
        case android = "androideabi"
    }

    public init(_ string: String) throws {
        let components = string.split(separator: "-").map(String.init)

        guard components.count == 3 || components.count == 4 else {
            throw Error.badFormat
        }

        guard let arch = Arch(rawValue: components[0]) else {
            throw Error.unknownArch
        }

        let vendor = Vendor(rawValue: components[1]) ?? .unknown

        guard let os = Triple.parseOS(components[2]) else {
            throw Error.unknownOS
        }

        let abiString = components.count > 3 ? components[3] : nil
        let abi = abiString.flatMap(ABI.init)

        self.tripleString = string
        self.arch = arch
        self.vendor = vendor
        self.os = os
        self.abi = abi ?? .unknown
    }

    fileprivate static func parseOS(_ string: String) -> OS? {
        for candidate in OS.allKnown {
            if string.hasPrefix(candidate.rawValue) {
                return candidate
            }
        }

        return nil
    }

    public func isDarwin() -> Bool {
        return vendor == .apple || os == .macOS || os == .darwin
    }

    public func isLinux() -> Bool {
        return os == .linux
    }

    public func isWindows() -> Bool {
        return os == .windows
    }

    /// Returns the triple string for the given platform version.
    ///
    /// This is currently meant for Apple platforms only.
    public func tripleString(forPlatformVersion version: String) -> String {
        precondition(isDarwin())
        return self.tripleString + version
    }

    public static let macOS = try! Triple("x86_64-apple-macosx")
    public static let x86_64Linux = try! Triple("x86_64-unknown-linux")
    public static let i686Linux = try! Triple("i686-unknown-linux")
    public static let ppc64leLinux = try! Triple("powerpc64le-unknown-linux")
    public static let s390xLinux = try! Triple("s390x-unknown-linux")
    public static let arm64Linux = try! Triple("aarch64-unknown-linux")
    public static let armLinux = try! Triple("armv7-unknown-linux-gnueabihf")
    public static let android = try! Triple("armv7-unknown-linux-androideabi")
    public static let windows = try! Triple("x86_64-unknown-windows-msvc")

  #if os(macOS)
    public static let hostTriple: Triple = .macOS
  #elseif os(Windows)
    public static let hostTriple: Triple = .windows
  #elseif os(Linux)
    #if arch(x86_64)
      public static let hostTriple: Triple = .x86_64Linux
    #elseif arch(i386)
      public static let hostTriple: Triple = .i686Linux
    #elseif arch(powerpc64le)
      public static let hostTriple: Triple = .ppc64leLinux
    #elseif arch(s390x)
      public static let hostTriple: Triple = .s390xLinux
    #elseif arch(arm64)
      public static let hostTriple: Triple = .arm64Linux
    #elseif arch(arm)
      public static let hostTriple: Triple = .armLinux    
    #endif
  #endif
}

extension Triple {
    /// The file extension for dynamic libraries (eg. `.dll`, `.so`, or `.dylib`)
    public var dynamicLibraryExtension: String {
        switch os {
        case .darwin, .macOS:
            return ".dylib"
        case .linux:
            return ".so"
        case .windows:
            return ".dll"
        }
    }
}
