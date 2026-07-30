import Foundation
import ArgumentParser
import Subprocess
import TSCBasic

@main
struct CMakeBuilder: AsyncParsableCommand {
    @Option
    var outputDir: String

    @Option
    var archs: String

    @Option
    var vendor: String

    @Option
    var os: String

    @Option
    var sdk: String?

    func run() async throws {
        if !FileManager.default.fileExists(atPath: outputDir) {
            try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }

        if !FileManager.default.fileExists(atPath: outputDir + "/build.ninja") {
            try await configure()
        }

        try await build()
    }

    // Do the build of the static library (skipping tests and utilities)
    func build() async throws {
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
    func configure() async throws {
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
    func generateToolchain(toolchainFile: String) throws {
        let contents: String

        // TODO multiple archs
        let arch = archs
        let triple = "\(arch)-\(vendor)-\(os)"

        if vendor == "apple", os.hasPrefix("macos") {
            let version = os[os.index(os.startIndex, offsetBy: 5)...]
            
            let sysroot: String
            if let sdkPath = sdk {
                sysroot = "\n\n" + """
                set(CMAKE_OSX_SYSROOT \(sdkPath))
                """
            } else {
                sysroot = ""
            }
            
            contents = """
            set(CMAKE_SYSTEM_NAME Darwin)
            set(CMAKE_SYSTEM_PROCESSOR \(arch))

            set(CMAKE_OSX_DEPLOYMENT_TARGET \(version))
            set(CMAKE_OSX_ARCHITECTURES \(arch))

            set(CMAKE_C_COMPILER   clang)
            set(CMAKE_CXX_COMPILER clang++)
            """ + sysroot
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
}
