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
    public let osVersion: Version?
    public let abi: ABI

    private let tripleStringHasABI: Bool

    public enum Error: Swift.Error {
        case badFormat
        case unknownOS
    }

    public enum Arch: String {
        case unknown

        case arm
        case arm64
        case arm64_32
        case i386
        case x86_64
        case powerpc64
        case powerpc64le
        case s390x

        // TODO: Split out into a separate SubArch enum?
        case armv7
        case armv7k
        case armv7s
    }

    public enum Vendor: String {
        case unknown

        /// Indicates Apple Inc., the vendor of iOS, macOS, tvOS, and watchOS.
        case apple

        /// Indicates the legacy, vendor-neutral "PC" vendor.
        case pc

        /// Indicates Sony Computer Entertainment, Inc., the vendor of PS4 OS.
        case scei
    }

    public enum OS: String, CaseIterable {
        case unknown

        case Darwin = "darwin"
        case FreeBSD = "freebsd"
        case Haiku = "haiku"
        case iOS = "ios"
        case Linux = "linux"
        case macOS = "macosx"
        case PS4 = "ps4"
        case tvOS = "tvos"
        case watchOS = "watchos"
        case Windows = "windows"

        fileprivate static let allKnown: [OS] = OS.allCases.filter { $0 != .unknown }
    }

    public struct Version {
        let major: Int
        let minor: Int
        let patch: Int

        public init(major: UInt) {
            self.major = Int(major)
            self.minor = -1
            self.patch = -1
        }

        public init(major: UInt, minor: UInt) {
            self.major = Int(major)
            self.minor = Int(minor)
            self.patch = -1
        }

        public init(major: UInt, minor: UInt, patch: UInt) {
            self.major = Int(major)
            self.minor = Int(minor)
            self.patch = Int(patch)
        }

        public init(_ string: String) throws {
            let rawComponents = string.split(separator: ".").map(String.init)
            let components = try rawComponents.map { s -> Int in
                guard let i = UInt.init(s) else { throw Error.badFormat }
                return Int(i)
            }
            self.major = components.count > 0 ? components[0] : 0
            self.minor = components.count > 1 ? components[1] : -1
            self.patch = components.count > 2 ? components[2] : -1
        }

        public var stringValue: String {
            return [major, minor, patch].compactMap { $0 >= 0 ? String($0) : nil }.joined(separator: ".")
        }
    }

    /// The value for the target triple's ABI field.
    public enum ABI: String {
        case unknown

        /// The ABI used by the Android operating system for all architectures except 32-bit ARM.
        case android

        /// The ABI used by the Android operating system for the 32-bit ARM architecture.
        case androideabi

        /// The ABI used by Cygwin, a Unix-like environment for Windows.
        case cygnus

        /// The ABI used by GNU/Linux operating systems for most architectures except 32-bit ARM.
        case gnu

        /// The ABI used by GNU/Linux operating systems for the 32-bit ARM architecture, with software floating-point instructions.
        case gnueabi

        /// The ABI used by GNU/Linux operating systems for the 32-bit ARM architecture, with hardware floating-point instructions.
        case gnueabihf

        /// The ABI used by Microsoft Visual C/C++ on Windows.
        case msvc

        /// The ABI used for the simulator variants of Apple platforms.
        case simulator
    }

    /// Initializes a triple directly from raw components.
    ///
    /// You should generally use the `Triple.create` family of methods instead, unless you need something extremely specific.
    public init(arch: Arch = .unknown, vendor: Vendor = .unknown, os: OS = .unknown, osVersion: Version? = nil, abi: ABI? = nil) {
        self.tripleString = [arch.stringValue(for: vendor, os: os), vendor.rawValue, os.rawValue + (osVersion?.stringValue ?? ""), abi?.rawValue].compactMap({ $0 }).joined(separator: "-")
        self.arch = arch
        self.vendor = vendor
        self.os = os
        self.osVersion = osVersion
        self.tripleStringHasABI = abi != nil
        self.abi = abi ?? .unknown
    }

    public init(_ string: String, strict: Bool = true) throws {
        if !strict {
            // TODO: Implement tolerant parsing where more fields can be optional
            throw Error.badFormat
        }

        let components = string.split(separator: "-").map(String.init)

        guard components.count == 3 || components.count == 4 else {
            throw Error.badFormat
        }

        let arch = Arch(rawValue: components[0]) ?? .unknown
        let vendor = Vendor(rawValue: components[1]) ?? .unknown

        guard let (os, osVersion) = try Triple.parseOS(components[2]) else {
            throw Error.unknownOS
        }

        self.tripleStringHasABI = components.count > 3

        let abiString = tripleStringHasABI ? components[3] : nil
        let abi = abiString.flatMap(ABI.init)

        self.tripleString = string
        self.arch = arch
        self.vendor = vendor
        self.os = os
        self.osVersion = osVersion
        self.abi = abi ?? .unknown
    }

    fileprivate static func parseOS(_ string: String) throws -> (OS, Version?)? {
        // Exact match?
        if let os = OS(rawValue: string) {
            return (os, nil)
        }

        // Look for an OS name plus version number
        for candidate in OS.allKnown {
            if string.hasPrefix(candidate.rawValue) {
                // Assume the rest of the string is a version number
                return (candidate, try Version(String(string.dropFirst(candidate.rawValue.count))))
            }
        }

        return nil
    }

    // TODO: The "current" triple is not necessarily the desired host triple,
    // i.e. in cases of 32-bit code running on a 64-bit OS, or other sorts of
    // emulation layers, but this is good enough for now in most cases.
    public static let hostTriple = Triple.current
}

extension Triple {
    /// Creates a triple with the given architecture, OS and OS version.
    /// The vendor and ABI fields are determined automatically.
    public static func create(arch: Arch, os: OS, osVersion: Version? = nil) -> Triple {
        let vendor: Vendor = {
            switch os {
            case .Darwin, .iOS, .macOS, .tvOS, .watchOS:
                return .apple
            case .PS4:
                return .scei
            case .Haiku where arch == .i386:
                return .pc
            case .FreeBSD, .Haiku, .Linux, .Windows, .unknown:
                return .unknown
            }
        }()
        let abi: ABI? = {
            if [.i386, .x86_64].contains(arch) && [.iOS, .tvOS, .watchOS].contains(os) {
                return .simulator
            }
            if os == .Linux {
                return arch.isArm32 ? .gnueabi : .gnu
            }
            if os == .Windows {
                return .msvc
            }
            return nil
        }()
        return Triple(arch: arch, vendor: vendor, os: os, osVersion: osVersion, abi: abi)
    }

    /// Creates an Android triple for the given architecture and OS version.
    /// The ABI is determined automatically based on the architecture.
    public static func createAndroid(arch: Arch, osVersion: Version? = nil) -> Triple {
        return Triple(arch: arch, os: .Linux, osVersion: osVersion, abi: Arch.current.isArm32 ? .androideabi : .android)
    }

    /// Creates a Cygwin triple for the given architecture and OS version.
    /// The ABI is set to `cygnus`.
    public static func createCygwin(arch: Arch, osVersion: Version? = nil) -> Triple {
        return Triple(arch: arch, vendor: .unknown, os: .Windows, osVersion: osVersion, abi: .cygnus)
    }

    /// Returns the "current" triple, that is,
    /// the triple that the running code was compiled for.
    public static var current: Triple {
        if OS.isAndroid {
            return createAndroid(arch: Arch.current)
        }
        if OS.isCygwin {
            return createCygwin(arch: Arch.current)
        }
        return create(arch: Arch.current, os: OS.current)
    }

    public var isDarwin: Bool {
        return os.isDarwin
    }

    public var isLinux: Bool {
        return os == .Linux
    }

    public var isWindows: Bool {
        return os == .Windows
    }

    /// Returns the triple with its OS version component replaced with the given version.
    public func withOSVersion(_ osVersion: Version? = nil) -> Triple {
        return Triple(arch: arch, vendor: vendor, os: os, osVersion: osVersion, abi: tripleStringHasABI ? abi : nil)
    }
}

extension Triple.OS {
    /// Returns the "current" OS, that is,
    /// the OS that the running code was compiled for.
    public static var current: Triple.OS {
        // https://github.com/apple/swift/blob/master/lib/Basic/LangOptions.cpp
        #if os(macOS)
        return .macOS
        #elseif os(tvOS)
        return .tvOS
        #elseif os(watchOS)
        return .watchOS
        #elseif os(iOS)
        return .iOS
        #elseif os(Linux) || os(Android)
        return .Linux // for Android, that's indicated in the environment field
        #elseif os(FreeBSD)
        return .FreeBSD
        #elseif os(Windows) || os(Cygwin)
        return .Windows // for Cygwin, that's indicated in the environment field
        #elseif os(PS4)
        return .PS4
        #elseif os(Haiku)
        return .Haiku
        #else
        return .unknown
        #endif
    }

    fileprivate static var isAndroid: Bool {
        #if os(Android)
        return true
        #else
        return false
        #endif
    }

    fileprivate static var isCygwin: Bool {
        #if os(Cygwin)
        return true
        #else
        return false
        #endif
    }

    /// Returns whether the current OS is Darwin or is based on Darwin.
    public var isDarwin: Bool {
        return [.Darwin, .iOS, .macOS, .tvOS, .watchOS].contains(self)
    }
}

extension Triple.Arch {
    /// Returns the "current" architecture, that is,
    /// the architecture that the running code was compiled for.
    public static var current: Triple.Arch {
        // https://github.com/apple/swift/blob/master/lib/Basic/LangOptions.cpp
        #if arch(arm)
        return .arm // We can't know the ARM subarch
        #elseif arch(arm64)
        return .arm64
        #elseif arch(arm64_32)
        return .arm64_32
        #elseif arch(i386)
        return .i386
        #elseif arch(x86_64)
        return .x86_64
        #elseif arch(powerpc64)
        return .powerpc64
        #elseif arch(powerpc64le)
        return .powerpc64le
        #elseif arch(s390x)
        return .s390x
        #else
        return .unknown
        #endif
    }

    public var isArm32: Bool {
        return [.arm, .armv7, .armv7k, .armv7s].contains(self)
    }

    /// Returns the string representation of the architecture,
    /// which can vary by vendor and OS.
    public func stringValue(for vendor: Triple.Vendor, os: Triple.OS) -> String {
        if self == .arm64 && vendor != .apple {
            return "aarch64"
        }
        if self == .i386 && os == .Haiku {
            return "i586"
        }
        return rawValue
    }
}
