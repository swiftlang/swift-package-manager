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

    @Option(help: "The build products dir to copy the result into")
    var productsDir: String

    @Option(help: "The CPU architectures to build for")
    var arches: String

    @Option(help: "The vendor field of the triple")
    var vendor: String

    @Option(help: "The os field of the triple")
    var os: String

    @Option(help: "the suffix field of the triple")
    var suffix: String

    @Option(help: "The SDK root directory")
    var sdk: String

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

    static func getEnv(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name] else {
            throw CMakeError.missingEnvVar(name)
        }
        return value
    }

    // Do the build of the static library (skipping tests and utilities)
    func build(outputDir: String) async throws {
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
    func configure(sourceDir: String, outputDir: String) async throws {
        let toolchainFile = outputDir + "/cmake.toolchain"
        try generateToolchain(toolchainFile: toolchainFile)

        let result = try await Subprocess.run(
            .name("cmake"),
            arguments: [
                "-G", "Ninja",
                "-S", sourceDir,
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
    func generateToolchain(toolchainFile: String) throws {
        let contents: String

        // TODO multiple archs
        let arch = arches
        let triple = "\(arch)-\(vendor)-\(os)\(suffix)"

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
    case noProductsDir
    case boom
}
