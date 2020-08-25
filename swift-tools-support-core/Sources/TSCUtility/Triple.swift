/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic

/// Triple - Helper class for working with Destination.target values
///
/// Used for parsing values such as x86_64-apple-macosx10.10 into
/// set of enums. For os/arch/abi based conditions in build plan.
///
/// @see Destination.target
/// @see https://github.com/apple/swift-llvm/blob/stable/include/llvm/ADT/Triple.h
///
public struct Triple: Encodable, Equatable {
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

    public enum Arch: String, Encodable {
        case x86_64
        case x86_64h
        case i686
        case powerpc64le
        case s390x
        case aarch64
        case armv7
        case arm
        case arm64
        case arm64e
        case wasm32
    }

    public enum Vendor: String, Encodable {
        case unknown
        case apple
    }

    public enum OS: String, Encodable, CaseIterable {
        case darwin
        case macOS = "macosx"
        case linux
        case windows
        case wasi
    }

    public enum ABI: String, Encodable {
        case unknown
        case android
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

        let abi = components.count > 3 ? Triple.parseABI(components[3]) : nil

        self.tripleString = string
        self.arch = arch
        self.vendor = vendor
        self.os = os
        self.abi = abi ?? .unknown
    }

    fileprivate static func parseOS(_ string: String) -> OS? {
        for candidate in OS.allCases where string.hasPrefix(candidate.rawValue) {
            return candidate
        }

        return nil
    }

    fileprivate static func parseABI(_ string: String) -> ABI? {
        if string.hasPrefix(ABI.android.rawValue) {
            return ABI.android
        }
        return nil
    }

    public func isAndroid() -> Bool {
        return os == .linux && abi == .android
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

    public func isWASI() -> Bool {
        return os == .wasi
    }

    /// Returns the triple string for the given platform version.
    ///
    /// This is currently meant for Apple platforms only.
    public func tripleString(forPlatformVersion version: String) -> String {
        precondition(isDarwin())
        return self.tripleString + version
    }

    public static let macOS = try! Triple("x86_64-apple-macosx")

    /// Determine the host triple using the Swift compiler.
    public static func getHostTriple(usingSwiftCompiler swiftCompiler: AbsolutePath) -> Triple {
        do {
            let result = try Process.popen(args: swiftCompiler.pathString, "-print-target-info")
            let output = try result.utf8Output().spm_chomp()
            let targetInfo = try JSON(string: output)
            let tripleString: String = try targetInfo.get("target").get("unversionedTriple")
            return try Triple(tripleString)
        } catch {
            // FIXME: Remove the macOS special-casing once the latest version of Xcode comes with
            // a Swift compiler that supports -print-target-info.
          #if os(macOS)
            return .macOS
          #else
            fatalError("could not determine host triple: \(error)")
          #endif
        }
    }
}

extension Triple {
    /// The file prefix for dynamcic libraries
    public var dynamicLibraryPrefix: String {
        switch os {
        case .windows:
            return ""
        default:
            return "lib"
        }
    }

    /// The file extension for dynamic libraries (eg. `.dll`, `.so`, or `.dylib`)
    public var dynamicLibraryExtension: String {
        switch os {
        case .darwin, .macOS:
            return ".dylib"
        case .linux:
            return ".so"
        case .windows:
            return ".dll"
        case .wasi:
            fatalError("WebAssembly/WASI doesn't support dynamic library yet")
        }
    }

    public var executableExtension: String {
      switch os {
      case .darwin, .macOS:
        return ""
      case .linux:
        return ""
      case .wasi:
        return ""
      case .windows:
        return ".exe"
      }
    }
    
    /// The file extension for static libraries.
    public var staticLibraryExtension: String {
        return ".a"
    }

    /// The file extension for Foundation-style bundle.
    public var nsbundleExtension: String {
        switch os {
        case .darwin, .macOS:
            return ".bundle"
        default:
            // See: https://github.com/apple/swift-corelibs-foundation/blob/master/Docs/FHS%20Bundles.md
            return ".resources"
        }
    }
}
