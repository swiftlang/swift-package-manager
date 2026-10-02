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
import ArgumentParser
import Foundation
import Subprocess

@main
struct CMakeBuilder: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Configures and builds the SDL CMake project."
    )

    @Option(help: "The directory the CMake build is configured and run in.")
    var outputDir: String

    @Option(help: "The SDK root directory")
    var sdk: String

    @Option(help: "The triple to build")
    var triple: Triple

    @Argument(help: "The directory containing the project's CMakeLists.txt.")
    var sourceDir: String

    func run() async throws {
        if !FileManager.default.fileExists(atPath: outputDir) {
            try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }

        if !FileManager.default.fileExists(atPath: outputDir + "/build.ninja") {
            try await configure(sourceDir: sourceDir, outputDir: outputDir)
        }

        try await build(outputDir: outputDir)
    }

    // Do the build of the static library (skipping tests and utilities)
    func build(outputDir: String) async throws {
        var arguments = [
            "--build", outputDir,
            "--target", "SDL3-static"
        ]

        if let env = triple.env, env.hasPrefix("android") {
            arguments.append("SDL3-jar")
        }

        _ = try await Subprocess.run(
            .name("cmake"),
            arguments: .init(arguments),
            // Needed to build for Android
            environment: .inherit.updating(["JDK_JAVAC_OPTIONS": "--release 17"]),
            output: .currentStandardOutput,
            error: .currentStandardError
        )

        if !FileManager.default.fileExists(atPath: outputDir + "/SDL3.jar") {
            try FileManager.default.copyItem(atPath: outputDir + "/SDL3-3.4.17.jar", toPath: outputDir + "/SDL3.jar")
        }
    }

    // Run the configure step of the CMake build
    func configure(sourceDir: String, outputDir: String) async throws {
        var arguments = [
            "-G", "Ninja",
            "-S", sourceDir,
            "-B", outputDir,
            "-DSDL_STATIC=ON",
            "-Wno-author",
        ]

        if let toolchainFile = try generateToolchain(outputDir: outputDir) {
            arguments += [
                "--toolchain", toolchainFile,
            ]
        }

        if let env = triple.env, env.hasPrefix("android"), let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] {
            arguments += [
                "-DSDL_ANDROID_HOME=\(androidHome)"
            ]
        }

        let result = try await Subprocess.run(
            .name("cmake"),
            arguments: .init(arguments),
            output: .currentStandardOutput,
            error: .currentStandardError
        )
        guard result.terminationStatus.isSuccess else {
            print("ouch!!!")
            throw CMakeError.configureError(result.terminationStatus)
        }
    }
    
    // Generate the toolchain for the build
    func generateToolchain(outputDir: String) throws -> String? {
        let contents: String

        if triple.vendor == "apple", triple.os.hasPrefix("macos") {
            // Building for host, don't need a toolchain file
            return nil
        } else if triple.os == "windows" {
            return nil
        } else if triple.os == "linux" {
            if let env = triple.env {
                let version = env[env.index(env.startIndex, offsetBy: 7)...]

                guard let ndkHome = ProcessInfo.processInfo.environment["ANDROID_NDK_HOME"] else {
                    fatalError("ANDROID_NDK_HOME is not set")
                }

                let abi: String
                switch triple.arch {
                case "aarch64":
                    abi = "arm64-v8a"
                default:
                    fatalError("Unknown arch for Android")
                }

                contents = """
                set(ANDROID_ABI      "\(abi)"             CACHE STRING "Target ABI")
                set(ANDROID_PLATFORM "android-\(version)" CACHE STRING "Minimum API level")
                set(ANDROID_STL      "c++_static"         CACHE STRING "NDK C++ runtime")
                set(ANDROID_ARM_NEON ON                   CACHE BOOL   "Enable NEON")

                set(CMAKE_ANDROID_API_MIN \(version))

                include("\(ndkHome.replacing("\\", with: "/"))/build/cmake/android.toolchain.cmake")
                """
            } else {
                contents = """
                set(CMAKE_SYSTEM_NAME Linux)
                set(CMAKE_SYSTEM_PROCESSOR \(triple.arch))

                set(CMAKE_C_COMPILER clang)
                set(CMAKE_C_COMPILER_TARGET \(triple))
                set(CMAKE_CXX_COMPILER clang++)
                set(CMAKE_CXX_COMPILER_TARGET \(triple))

                # Where to find the target's headers/libs
                #set(CMAKE_SYSROOT /path/to/sysroot)
                #set(CMAKE_FIND_ROOT_PATH /path/to/sysroot)

                # Search behavior for find_* commands
                #set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
                #set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
                #set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
                #set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
                """
            }
        } else {
            throw CMakeError.badTriple(triple)
        }

        let toolchainFile = outputDir + "/cmake.toolchain"
        try contents.write(toFile: toolchainFile, atomically: true, encoding: .utf8)
        return toolchainFile
    }
}

struct Triple: ExpressibleByArgument, CustomStringConvertible {
    var arch: Substring
    var vendor: Substring
    var os: Substring
    var env: Substring?

    public init?(argument: String) {
        let components = argument.split(separator: "-")
        self.arch = components[0]
        self.vendor = components[1]
        self.os = components[2]
        self.env = components.count > 3 ? components[3] : nil
    }

    var description: String {
        let triple = "\(arch)-\(vendor)-\(os)"
        if let env {
            return triple + "-\(env)"
        } else {
            return triple
        }
    }
}

enum CMakeError: Error {
    case configureError(TerminationStatus)
    case badTriple(Triple)
    case missingEnvVar(String)
    case noProductsDir
    case boom
}
