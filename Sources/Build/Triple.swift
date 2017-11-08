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
        case armv7
        case s390x
    }

    public enum Vendor: String {
        case unknown
        case apple
    }

    public enum OS: String {
        case darwin
        case macOS = "macosx"
        case linux

        fileprivate static let allKnown:[OS] = [
            .darwin,
            .macOS,
            .linux
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

    public static let macOS = try! Triple("x86_64-apple-macosx10.10")
    public static let linux = try! Triple("x86_64-unknown-linux")
    public static let android = try! Triple("armv7-unknown-linux-androideabi")

  #if os(macOS)
    public static let hostTriple: Triple = .macOS
  #elseif os(Linux) && arch(s390x)
    public static let hostTriple: Triple = try! Triple("s390x-unknown-linux")
  #else
    public static let hostTriple: Triple = .linux
  #endif
}
