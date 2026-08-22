import Foundation
import Subprocess

@main
struct CMakeBuilder {
    static func main() async throws {
        let outputDir = try CommandLine.arguments[1] + "/" + getEnv("SWIFT_CONFIGURATION") + getEnv("SWIFT_PLATFORM")

        if !FileManager.default.fileExists(atPath: outputDir) {
            try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }

        if !FileManager.default.fileExists(atPath: outputDir + "/build.ninja") {
            try await configure(outputDir: outputDir)
        }

        try await build(outputDir: outputDir)
    }

    static func getEnv(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name] else {
            throw CMakeError.missingEnvVar(name)
        }
        return value
    }

    // Do the build of the static library (skipping tests and utilities)
    static func build(outputDir: String) async throws {
        _ = try await Subprocess.run(
            .name("cmake"),
            arguments: [
                "--build", outputDir,
                "--target", "SDL3-static"
            ],
            output: .currentStandardOutput,
            error: .currentStandardError
        )
    }

    // Run the configure step of the CMake build
    static func configure(outputDir: String) async throws {
        let toolchainFile = outputDir + "/cmake.toolchain"
        try generateToolchain(toolchainFile: toolchainFile)

        let result = try await Subprocess.run(
            .name("cmake"),
            arguments: [
                "-G", "Ninja",
                "-B", outputDir,
                "--toolchain", toolchainFile,
                "-DSDL_STATIC=ON",
                "-DSDL_SHARED=OFF",
            ],
            output: .currentStandardOutput,
            error: .currentStandardError
        )
        guard result.terminationStatus.isSuccess else {
            print("ouch!!!")
            throw CMakeError.configureError(result.terminationStatus)
        }
    }
    
    // Generate the toolchain for the build
    static func generateToolchain(toolchainFile: String) throws {
        let contents: String

        // TODO multiple archs
        let arch = try getEnv("SWIFT_ARCHS")
        let vendor = try getEnv("SWIFT_VENDOR")
        let os = try getEnv("SWIFT_OS")
        let suffix = try getEnv("SWIFT_SUFFIX")
        let triple = "\(arch)-\(vendor)-\(os)\(suffix)"

        let sdk = try getEnv("SWIFT_SDK")

        if vendor == "apple", os.hasPrefix("macos") {
            let version = os[os.index(os.startIndex, offsetBy: 5)...]
            
            contents = """
            set(CMAKE_SYSTEM_NAME Darwin)
            set(CMAKE_SYSTEM_PROCESSOR \(arch))

            set(CMAKE_OSX_DEPLOYMENT_TARGET \(version))
            set(CMAKE_OSX_ARCHITECTURES \(arch))
            set(CMAKE_OSX_SYSROOT \(sdk))

            set(CMAKE_C_COMPILER   clang)
            set(CMAKE_CXX_COMPILER clang++)
            """
        } else if vendor == "linux" {
            contents = """
            set(CMAKE_SYSTEM_NAME Linux)
            set(CMAKE_SYSTEM_PROCESSOR \(arch))

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
        } else {
            throw CMakeError.badTriple(triple)
        }

        try contents.write(toFile: toolchainFile, atomically: true, encoding: .utf8)
    }
}

enum CMakeError: Error {
    case configureError(TerminationStatus)
    case badTriple(String)
    case missingEnvVar(String)
    case boom
}
