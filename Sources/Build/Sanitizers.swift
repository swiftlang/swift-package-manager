/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */
import Basic
import Utility

/// A set of enabled runtime sanitizers.
public struct EnabledSanitizers {
    public enum Sanitizer: String {
        case address
        case thread
    }

    /// A set of enabled sanitizers.
    private let sanitizers: Set<Sanitizer>

    /// OS identification
    private let triple: Triple

    /// Runtime verbosity level
    private let verbose: Bool

    public init(from list: [Sanitizer] = [], triple: Triple = Triple.hostTriple, verbose: Bool = false) {
        self.sanitizers = Set(list)
        self.triple = triple
        self.verbose = verbose
    }

    /// Return an established short name for a sanitizer, e.g. "asan".
    private func shortname(_ sanitizer: Sanitizer) -> String {
        switch sanitizer {
        case .address: return "asan"
        case .thread: return "tsan"
        }
    }

    /// Return a dictionary with the sanitizer-specific list of additional
    /// environment variables that have to be injected during runtime.
    public func addRuntimeEnvironment(baseEnvironment: [String: String], toolchain: Toolchain) -> [String: String] {
      #if os(macOS)
        return macosAddRuntimeEnvironment(baseEnvironment: baseEnvironment, toolchain: toolchain)
      #else
        return [:]
      #endif
    }

    private func macosAddRuntimeEnvironment(baseEnvironment: [String: String], toolchain: Toolchain) -> [String: String] {
        var env: [String: String] = [:]
        var insertLibs: [String] = []

        if let existingLibs = baseEnvironment["DYLD_INSERT_LIBRARIES"] {
            if existingLibs.count != 0 {
                insertLibs = [existingLibs]
            }
        }

        for sanitizer in sanitizers {
            let libPath = sanitizerLibrary(clangPath: toolchain.clangCompiler, for: sanitizer)
            insertLibs.append(libPath.asString)
        }

        env["DYLD_INSERT_LIBRARIES"] = insertLibs.joined(separator: ":")

        if verbose {
            env["DYLD_PRINT_LIBRARIES"] = "1"
        }

        return env
    }

    /// Sanitization flags for the C family compiler (C/C++)
    public func compileCFlags() -> [String] {
        return sanitizers.map({ "-fsanitize=\($0.rawValue)" })
    }

    /// Sanitization flags for the Swift compiler.
    public func compileSwiftFlags() -> [String] {
        return sanitizers.map({ "-sanitize=\($0.rawValue)" })
    }

    /// Sanitization flags for the Swift linker and compiler are the same so far.
    public func linkSwiftFlags() -> [String] {
        return compileSwiftFlags()
    }

    /// The sanitizer library is part of clang, but it is possible
    /// to fetch a proper version of it by going through the `swift` symlink.
    private func sanitizerLibrary(clangPath clang: AbsolutePath, for sanitizer: Sanitizer) -> AbsolutePath {
        return clang.appending(RelativePath("../../lib/swift/clang/lib/\(osName())/libclang_rt.\(shortname(sanitizer))_osx_dynamic.dylib"))
    }

    /// Operating system short name for the filesystem path.
    private func osName() -> String {
        switch triple.os {
        case .darwin, .macOS: return "darwin"
        case .linux: return "linux"
        }
    }

}

// StringEnumArgument conformance to help with command line parsing
extension EnabledSanitizers.Sanitizer: StringEnumArgument {
    public static let completion: ShellCompletion = .values([
        (address.rawValue, "enable Address sanitizer"),
        (thread.rawValue, "enable Thread sanitizer"),
    ])
}
