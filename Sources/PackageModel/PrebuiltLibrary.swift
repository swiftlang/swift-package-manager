//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

/// A structure representing a prebuilt library to be used instead of a source dependency
public struct PrebuiltLibrary {
    /// The package identity.
    public let identity: PackageIdentity

    /// The name of the binary target the artifact corresponds to.
    public let libraryName: String

    /// The path to the extracted prebuilt artifacts
    public let path: AbsolutePath

    /// The path to the checked out source
    public let checkoutPath: AbsolutePath?

    /// The products in the library
    public let products: [String]

    /// The include path relative to the checkouts dir
    public let includePath: [RelativePath]?

    /// The C modules that need their includes directory added to the include path
    public let cModules: [String]

    public init(
        identity: PackageIdentity,
        libraryName: String,
        path: AbsolutePath,
        checkoutPath: AbsolutePath?,
        products: [String],
        includePath: [RelativePath]? = nil,
        cModules: [String] = []
    ) {
        self.identity = identity
        self.libraryName = libraryName
        self.path = path
        self.checkoutPath = checkoutPath
        self.products = products
        self.includePath = includePath
        self.cModules = cModules
    }
}

public enum PrebuiltsPlatform: String, Codable, CaseIterable {
    case macos_aarch64
    case macos_x86_64
    case windows_aarch64
    case windows_x86_64
    case ubuntu_noble_aarch64
    case ubuntu_noble_x86_64
    case ubuntu_jammy_aarch64
    case ubuntu_jammy_x86_64
    case ubuntu_focal_aarch64
    case ubuntu_focal_x86_64
    case fedora_39_aarch64
    case fedora_39_x86_64
    case amazonlinux2_aarch64
    case amazonlinux2_x86_64
    case rhel_ubi9_aarch64
    case rhel_ubi9_x86_64
    case debian_12_aarch64
    case debian_12_x86_64

    public enum Arch: String {
        case x86_64
        case aarch64
    }

    public enum OS {
        case macos
        case windows
        case linux
    }

    public var arch: Arch {
        switch self {
        case .macos_aarch64, .windows_aarch64,
            .ubuntu_noble_aarch64, .ubuntu_jammy_aarch64, .ubuntu_focal_aarch64,
            .fedora_39_aarch64,
            .amazonlinux2_aarch64,
            .rhel_ubi9_aarch64,
            .debian_12_aarch64:
            return .aarch64
        case .macos_x86_64, .windows_x86_64,
            .ubuntu_noble_x86_64, .ubuntu_jammy_x86_64, .ubuntu_focal_x86_64,
            .fedora_39_x86_64,
            .amazonlinux2_x86_64,
            .rhel_ubi9_x86_64,
            .debian_12_x86_64:
            return .x86_64
        }
    }

    public var os: OS {
        switch self {
        case .macos_aarch64, .macos_x86_64:
            return .macos
        case .windows_aarch64, .windows_x86_64:
            return .windows
        case .ubuntu_noble_aarch64, .ubuntu_noble_x86_64,
            .ubuntu_jammy_aarch64, .ubuntu_jammy_x86_64,
            .ubuntu_focal_aarch64, .ubuntu_focal_x86_64,
            .fedora_39_aarch64, .fedora_39_x86_64,
            .amazonlinux2_aarch64, .amazonlinux2_x86_64,
            .rhel_ubi9_aarch64, .rhel_ubi9_x86_64,
            .debian_12_aarch64, .debian_12_x86_64:
            return .linux
        }
    }

        /// Determine host platform based on compilation target
    public static var hostPlatform: Self? {
        let arch: Arch?
#if arch(arm64)
        arch = .aarch64
#elseif arch(x86_64)
        arch = .x86_64
#else
        arch = nil
#endif
        guard let arch else {
            return nil
        }

#if os(macOS)
        switch arch {
        case .aarch64:
            return .macos_aarch64
        case .x86_64:
            return .macos_x86_64
        }
#elseif os(Windows)
        switch arch {
        case .aarch64:
            return .windows_aarch64
        case .x86_64:
            return .windows_x86_64
        }
#elseif os(Linux)
        // Load up the os-release file into a dictionary
        guard let osData = try? String(contentsOfFile: "/etc/os-release", encoding: .utf8)
        else {
            return nil
        }
        let osLines = osData.split(separator: "\n")
        let osDict = osLines.reduce(into: [Substring: String]()) {
            (dict, line) in
            let parts = line.split(separator: "=", maxSplits: 2)
            dict[parts[0]] = parts[1...].joined(separator: "=").trimmingCharacters(in: ["\""])
        }

        switch osDict["ID"] {
        case "ubuntu":
            switch osDict["VERSION_CODENAME"] {
            case "noble":
                switch arch {
                case .aarch64:
                    return .ubuntu_noble_aarch64
                case .x86_64:
                    return .ubuntu_noble_x86_64
                }
            case "jammy":
                switch arch {
                case .aarch64:
                    return .ubuntu_jammy_aarch64
                case .x86_64:
                    return .ubuntu_jammy_x86_64
                }
            case "focal":
                switch arch {
                case .aarch64:
                    return .ubuntu_focal_aarch64
                case .x86_64:
                    return .ubuntu_focal_x86_64
                }
            default:
                return nil
            }
        case "fedora":
            switch osDict["VERSION_ID"] {
            case "39", "41":
                switch arch {
                case .aarch64:
                    return .fedora_39_aarch64
                case .x86_64:
                    return .fedora_39_x86_64
                }
            default:
                return nil
            }
        case "amzn":
            switch osDict["VERSION_ID"] {
            case "2":
                switch arch {
                case .aarch64:
                    return .amazonlinux2_aarch64
                case .x86_64:
                    return .amazonlinux2_x86_64
                }
            default:
                return nil
            }
        case "rhel":
            guard let version = osDict["VERSION_ID"] else {
                return nil
            }
            switch version.split(separator: ".")[0] {
            case "9":
                switch arch {
                case .aarch64:
                    return .rhel_ubi9_aarch64
                case .x86_64:
                    return .rhel_ubi9_x86_64
                }
            default:
                return nil
            }
        case "debian":
            switch osDict["VERSION_ID"] {
            case "12":
                switch arch {
                case .aarch64:
                    return .debian_12_aarch64
                case .x86_64:
                    return .debian_12_x86_64
                }
            default:
                return nil
            }
        default:
            return nil
        }
#else
        return nil
#endif
    }
}
