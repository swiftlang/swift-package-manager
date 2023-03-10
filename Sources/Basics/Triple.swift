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

import protocol Foundation.CustomNSError
import var Foundation.NSLocalizedDescriptionKey
import TSCBasic

/// Triple - Helper class for working with Destination.target values
///
/// Used for parsing values such as x86_64-apple-macosx10.10 into
/// set of enums. For os/arch/abi based conditions in build plan.
///
/// @see Destination.target
/// @see https://github.com/apple/swift-llvm/blob/stable/include/llvm/ADT/Triple.h
///
public struct Triple: Encodable, Equatable, Sendable {
    public let tripleString: String

    public let arch: Arch
    public let vendor: Vendor
    public let os: OS
    public let abi: ABI
    public let osVersion: String?
    public let abiVersion: String?

    public enum Error: Swift.Error {
        case badFormat(triple: String)
        case unknownArch(arch: String)
        case unknownOS(os: String)
    }

    public enum Arch: String, Encodable, Sendable {
        case x86_64
        case x86_64h
        case i686
        case powerpc
        case powerpc64le
        case s390x
        case aarch64
        case amd64
        case armv7
        case armv6
        case armv5
        case arm
        case arm64
        case arm64e
        case wasm32
        case riscv64
        case mips
        case mipsel
        case mips64
        case mips64el
    }

    public enum Vendor: String, Encodable, Sendable {
        case unknown
        case apple
    }

    public enum OS: String, Encodable, CaseIterable, Sendable {
        case darwin
        case macOS = "macosx"
        case linux
        case windows
        case wasi
        case openbsd
    }

    public enum ABI: Encodable, Equatable, RawRepresentable, Sendable {
        case unknown
        case android
        case other(name: String)

        public init?(rawValue: String) {
            if rawValue.hasPrefix(ABI.android.rawValue) {
                self = .android
            } else if let version = rawValue.firstIndex(where: { $0.isNumber }) {
                self = .other(name: String(rawValue[..<version]))
            } else {
                self = .other(name: rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .android: return "android"
            case .other(let name): return name
            case .unknown: return "unknown"
            }
        }

        public static func == (lhs: ABI, rhs: ABI) -> Bool {
            switch (lhs, rhs) {
            case (.unknown, .unknown):
                return true
            case (.android, .android):
                return true
            case (.other(let lhsName), .other(let rhsName)):
                return lhsName == rhsName
            default:
                return false
            }
        }
    }

    public init(_ string: String) throws {
        let components = string.split(separator: "-").map(String.init)

        guard components.count == 3 || components.count == 4 else {
            throw Error.badFormat(triple: string)
        }

        guard let arch = Arch(rawValue: components[0]) else {
            throw Error.unknownArch(arch: components[0])
        }

        let vendor = Vendor(rawValue: components[1]) ?? .unknown

        guard let os = Triple.parseOS(components[2]) else {
            throw Error.unknownOS(os: components[2])
        }

        let osVersion = Triple.parseVersion(components[2])

        let abi = components.count > 3 ? Triple.ABI(rawValue: components[3]) : nil
        let abiVersion = components.count > 3 ? Triple.parseVersion(components[3]) : nil

        self.tripleString = string
        self.arch = arch
        self.vendor = vendor
        self.os = os
        self.osVersion = osVersion
        self.abi = abi ?? .unknown
        self.abiVersion = abiVersion
    }

    fileprivate static func parseOS(_ string: String) -> OS? {
        var candidates = OS.allCases.map { (name: $0.rawValue, value: $0) }
        // LLVM target triples support this alternate spelling as well.
        candidates.append((name: "macos", value: .macOS))
        return candidates.first(where: { string.hasPrefix($0.name) })?.value
    }

    fileprivate static func parseVersion(_ string: String) -> String? {
        let candidate = String(string.drop(while: { $0.isLetter }))
        if candidate != string && !candidate.isEmpty {
            return candidate
        }

        return nil
    }

    public func isAndroid() -> Bool {
        os == .linux && abi == .android
    }

    public func isDarwin() -> Bool {
        vendor == .apple || os == .macOS || os == .darwin
    }

    public func isLinux() -> Bool {
        os == .linux
    }

    public func isWindows() -> Bool {
        os == .windows
    }

    public func isWASI() -> Bool {
        os == .wasi
    }

    public func isOpenBSD() -> Bool {
        os == .openbsd
    }

    /// Returns the triple string for the given platform version.
    ///
    /// This is currently meant for Apple platforms only.
    public func tripleString(forPlatformVersion version: String) -> String {
        precondition(isDarwin())
        return String(self.tripleString.dropLast(self.osVersion?.count ?? 0)) + version
    }

    public static let macOS = try! Triple("x86_64-apple-macosx")

    /// Determine the versioned host triple using the Swift compiler.
    public static func getHostTriple(usingSwiftCompiler swiftCompiler: AbsolutePath) -> Triple {
        // Call the compiler to get the target info JSON.
        let compilerOutput: String
        do {
            let result = try Process.popen(args: swiftCompiler.pathString, "-print-target-info")
            compilerOutput = try result.utf8Output().spm_chomp()
        } catch {
            // FIXME: Remove the macOS special-casing once the latest version of Xcode comes with
            // a Swift compiler that supports -print-target-info.
            #if os(macOS)
            return .macOS
            #else
            fatalError("Failed to get target info (\(error))")
            #endif
        }
        // Parse the compiler's JSON output.
        let parsedTargetInfo: JSON
        do {
            parsedTargetInfo = try JSON(string: compilerOutput)
        } catch {
            fatalError("Failed to parse target info (\(error)).\nRaw compiler output: \(compilerOutput)")
        }
        // Get the triple string from the parsed JSON.
        let tripleString: String
        do {
            tripleString = try parsedTargetInfo.get("target").get("triple")
        } catch {
            fatalError("Target info does not contain a triple string (\(error)).\nTarget info: \(parsedTargetInfo)")
        }
        // Parse the triple string.
        do {
            return try Triple(tripleString)
        } catch {
            fatalError("Failed to parse triple string (\(error)).\nTriple string: \(tripleString)")
        }
    }

    public static func == (lhs: Triple, rhs: Triple) -> Bool {
        lhs.arch == rhs.arch && lhs.vendor == rhs.vendor && lhs.os == rhs.os && lhs.abi == rhs.abi && lhs
            .osVersion == rhs.osVersion && lhs.abiVersion == rhs.abiVersion
    }
}

extension Triple {
    /// The file prefix for dynamic libraries
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
        case .linux, .openbsd:
            return ".so"
        case .windows:
            return ".dll"
        case .wasi:
            return ".wasm"
        }
    }

    public var executableExtension: String {
        switch os {
        case .darwin, .macOS:
            return ""
        case .linux, .openbsd:
            return ""
        case .wasi:
            return ".wasm"
        case .windows:
            return ".exe"
        }
    }

    /// The file extension for static libraries.
    public var staticLibraryExtension: String {
        ".a"
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

extension Triple.Error: CustomNSError {
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: "\(self)"]
    }
}

extension Triple.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .badFormat(let triple):
            return "couldn't parse triple string \(triple)"
        case .unknownArch(let arch):
            return "unknown architecture \(arch)"
        case .unknownOS(let os):
            return "unknown OS \(os)"
        }
    }
}
