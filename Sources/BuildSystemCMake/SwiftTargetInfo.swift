// swift-tools-version: 6.0
import Foundation

/// Decoded output from `swift -print-target-info`
public struct SwiftTargetInfo: Decodable {
    public struct Target: Decodable {
        public let triple: String?
        public let unversionedTriple: String?
        public let moduleTriple: String?
        public let swiftRuntimeCompatibilityVersion: String?
        public let librariesRequireRPath: Bool?
    }

    public struct Paths: Decodable {
        public let runtimeLibraryPaths: [String]?
        public let runtimeLibraryImportPaths: [String]?
        public let runtimeResourcePath: String?
    }

    public let target: Target?
    public let paths: Paths?
    public let compilerVersion: String?
}

/// Maps Swift target info to CMake platform variables
public struct CMakePlatformMapper {

    public struct PlatformConfig {
        public var systemName: String?
        public var systemProcessor: String?
        public var sysroot: String?
        public var osxSysroot: String?
        public var osxArchitectures: String?
        public var osxDeploymentTarget: String?
        public var compilerTarget: String?
        public var findRootPath: String?
        public var androidNdk: String?
        public var androidArchAbi: String?
        public var androidApi: String?
        public var msvcRuntimeLibrary: String?

        public init() {}
    }

    /// Map Swift triple and SDK info to CMake cache variables
    public static func mapPlatform(triple: String, sysroot: String?, runtimePaths: [String]?) -> PlatformConfig {
        var config = PlatformConfig()
        config.compilerTarget = triple

        let lowerTriple = triple.lowercased()

        // Apple platforms
        if lowerTriple.contains("-apple-ios") {
            config.systemName = "iOS"
            if lowerTriple.contains("simulator") {
                config.osxSysroot = "iphonesimulator"
            } else {
                config.osxSysroot = "iphoneos"
            }
            // Extract architecture
            if let arch = extractArchitecture(from: triple) {
                config.osxArchitectures = arch
            }

        } else if lowerTriple.contains("-apple-tvos") {
            config.systemName = "tvOS"
            if lowerTriple.contains("simulator") {
                config.osxSysroot = "appletvsimulator"
            } else {
                config.osxSysroot = "appletvos"
            }
            if let arch = extractArchitecture(from: triple) {
                config.osxArchitectures = arch
            }

        } else if lowerTriple.contains("-apple-watchos") {
            config.systemName = "watchOS"
            if lowerTriple.contains("simulator") {
                config.osxSysroot = "watchsimulator"
            } else {
                config.osxSysroot = "watchos"
            }
            if let arch = extractArchitecture(from: triple) {
                config.osxArchitectures = arch
            }

        } else if lowerTriple.contains("-apple-visionos") {
            config.systemName = "visionOS"
            if lowerTriple.contains("simulator") {
                config.osxSysroot = "xrsimulator"
            } else {
                config.osxSysroot = "xros"
            }
            if let arch = extractArchitecture(from: triple) {
                config.osxArchitectures = arch
            }

        } else if lowerTriple.contains("-apple-macosx") || lowerTriple.contains("-apple-darwin") {
            config.systemName = "Darwin"
            if let sysroot = sysroot {
                config.osxSysroot = sysroot
            }
            if let arch = extractArchitecture(from: triple) {
                config.osxArchitectures = arch
            }

        // Linux variants
        } else if lowerTriple.contains("-linux-android") {
            config.systemName = "Android"
            // Extract Android ABI from triple
            if lowerTriple.starts(with: "aarch64") {
                config.androidArchAbi = "arm64-v8a"
            } else if lowerTriple.starts(with: "armv7") {
                config.androidArchAbi = "armeabi-v7a"
            } else if lowerTriple.starts(with: "x86_64") {
                config.androidArchAbi = "x86_64"
            } else if lowerTriple.starts(with: "i686") {
                config.androidArchAbi = "x86"
            }

            // Look for NDK in environment
            if let ndk = ProcessInfo.processInfo.environment["ANDROID_NDK_HOME"] ??
                         ProcessInfo.processInfo.environment["ANDROID_NDK"] {
                config.androidNdk = ndk
            }

            // Default to API level 21 (minimum for 64-bit)
            config.androidApi = "21"

        } else if lowerTriple.contains("-unknown-linux") || lowerTriple.contains("-linux-gnu") {
            config.systemName = "Linux"
            if let sysroot = sysroot {
                config.sysroot = sysroot
                config.findRootPath = sysroot
            }
            if let arch = extractArchitecture(from: triple) {
                config.systemProcessor = arch
            }

        // WASI
        } else if lowerTriple.contains("-wasi") {
            config.systemName = "WASI"
            if let sysroot = sysroot {
                config.sysroot = sysroot
            }

        // Windows
        } else if lowerTriple.contains("-windows") {
            config.systemName = "Windows"
            if lowerTriple.contains("msvc") {
                config.msvcRuntimeLibrary = "MultiThreadedDLL"
            }
            if let arch = extractArchitecture(from: triple) {
                config.systemProcessor = arch
            }
        }

        return config
    }

    /// Convert PlatformConfig to CMake -D flags
    public static func toCMakeDefines(_ config: PlatformConfig) -> [String: String] {
        var defines: [String: String] = [:]

        if let systemName = config.systemName {
            defines["CMAKE_SYSTEM_NAME"] = systemName
        }
        if let systemProcessor = config.systemProcessor {
            defines["CMAKE_SYSTEM_PROCESSOR"] = systemProcessor
        }
        if let sysroot = config.sysroot {
            defines["CMAKE_SYSROOT"] = sysroot
        }
        if let osxSysroot = config.osxSysroot {
            defines["CMAKE_OSX_SYSROOT"] = osxSysroot
        }
        if let osxArchitectures = config.osxArchitectures {
            defines["CMAKE_OSX_ARCHITECTURES"] = osxArchitectures
        }
        if let osxDeploymentTarget = config.osxDeploymentTarget {
            defines["CMAKE_OSX_DEPLOYMENT_TARGET"] = osxDeploymentTarget
        }
        if let compilerTarget = config.compilerTarget {
            defines["CMAKE_C_COMPILER_TARGET"] = compilerTarget
            defines["CMAKE_CXX_COMPILER_TARGET"] = compilerTarget
        }
        if let findRootPath = config.findRootPath {
            defines["CMAKE_FIND_ROOT_PATH"] = findRootPath
        }
        if let androidNdk = config.androidNdk {
            defines["CMAKE_ANDROID_NDK"] = androidNdk
        }
        if let androidArchAbi = config.androidArchAbi {
            defines["CMAKE_ANDROID_ARCH_ABI"] = androidArchAbi
        }
        if let androidApi = config.androidApi {
            defines["CMAKE_ANDROID_API"] = androidApi
        }
        if let msvcRuntimeLibrary = config.msvcRuntimeLibrary {
            defines["CMAKE_MSVC_RUNTIME_LIBRARY"] = msvcRuntimeLibrary
        }

        return defines
    }

    private static func extractArchitecture(from triple: String) -> String? {
        let components = triple.split(separator: "-")
        guard let arch = components.first else { return nil }

        let archString = String(arch)

        // Normalize architecture names
        switch archString.lowercased() {
        case "x86_64", "amd64":
            return "x86_64"
        case "aarch64", "arm64":
            return "arm64"
        case "armv7", "armv7a", "armv7l":
            return "armv7"
        case "i386", "i686":
            return "i386"
        default:
            return archString
        }
    }
}
