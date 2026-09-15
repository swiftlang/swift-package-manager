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

    @Option(help: "The SDK root directory")
    var sdk: String

    @Option(help: "The triple to build")
    var triple: String

    @Argument(help: "The directory containing the project's CMakeLists.txt.")
    var sourceDir: String

    func run() async throws {
        if !FileManager.default.fileExists(atPath: outputDir) {
            try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }

        if !FileManager.default.fileExists(atPath: outputDir + "/build.ninja") {
            print("Configuring...")
            try await configure(sourceDir: sourceDir, outputDir: outputDir)
        }

        print("Building...")
        try await build(outputDir: outputDir)
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

        let tripleComps = triple.split(separator: "-")
        if tripleComps.count > 3, tripleComps[3].hasPrefix("android") {
            _ = try await Subprocess.run(
                .name("cmake"),
                arguments: [
                    "--build", outputDir,
                    "--target", "SDL3-jar"
                ],
                output: .currentStandardOutput,
                error: .currentStandardError
            )
        }
    }

    // Run the configure step of the CMake build
    func configure(sourceDir: String, outputDir: String) async throws {
        let toolchainFile = outputDir + "/cmake.toolchain"
        try generateToolchain(toolchainFile: toolchainFile)

        var arguments = [
            "-G", "Ninja",
            "-S", sourceDir,
            "-B", outputDir,
            "--toolchain", toolchainFile,
            "-DSDL_STATIC=ON",
            "-Wno-author",
        ]

        let tripleComps = triple.split(separator: "-")
        if tripleComps.count > 3, tripleComps[3].hasPrefix("android"), let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] {
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
    func generateToolchain(toolchainFile: String) throws {
        let contents: String

        let components = triple.split(separator: "-")
        let arch = components[0]
        let vendor = components[1]
        let os = components[2]

        if vendor == "apple", components[2].hasPrefix("macos") {
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
        } else if os == "linux" {
            if components.count > 3, components[3].hasPrefix("android") {
                let os = components[3]
                let version = os[os.index(os.startIndex, offsetBy: 7)...]

                guard let ndkHome = ProcessInfo.processInfo.environment["ANDROID_NDK_HOME"] else {
                    fatalError("ANDROID_NDK_HOME is not set")
                }

                let abi: String
                switch arch {
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

                include("\(ndkHome)/build/cmake/android.toolchain.cmake")
                """
            } else {
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
            }
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
