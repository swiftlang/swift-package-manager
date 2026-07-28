import Foundation
import ArgumentParser
import Subprocess
import TSCBasic

@main
struct CMakeBuilder: AsyncParsableCommand {
    @Option
    var outputDir: String

    func run() async throws {
        print("Running CMake")

        let result = try await Subprocess.run(
            .name("cmake"),
            arguments: [
                "-G", "Ninja",
                "-B", outputDir,
                "-DSDL_STATIC=ON",
                "-DSDL_SHARED=OFF",
            ],
            output: .currentStandardOutput,
            error: .currentStandardOutput
        )
        guard result.terminationStatus.isSuccess else {
            print("CMakeBuilder failed")
            Darwin.exit(1)
        }

        print("CMakeBuilder complete")
    }

       /*
        run
           guard try run(title: "cmake configure", command: [
                "cmake",
                "-S", context.package.directoryURL.path,
                "-B", context.pluginWorkDirectoryURL.path,
                "-G", "Ninja",
                "--toolchain", toolchainFile.path,
                "-DSDL_STATIC=ON",
                "-DSDL_SHARED=OFF",
            ]) else {
                return
            }
        */
    

    /*
    func build(context: PluginContext, arguments: [String], buildContext: BuildContext) async throws {
        let toolchainFile = context.pluginWorkDirectoryURL.appending(path: "toolchain.cmake")
        if !FileManager.default.fileExists(atPath: toolchainFile.path) {
            guard try genToolchain(file: toolchainFile, buildContext: buildContext) else {
                return
            }

            guard try run(title: "cmake configure", command: [
                "cmake",
                "-S", context.package.directoryURL.path,
                "-B", context.pluginWorkDirectoryURL.path,
                "-G", "Ninja",
                "--toolchain", toolchainFile.path,
                "-DSDL_STATIC=ON",
                "-DSDL_SHARED=OFF",
            ]) else {
                return
            }
        }

        _ = try run(title: "cmake build", command: [
            "cmake",
            "--build", context.pluginWorkDirectoryURL.path,
            "--target", "SDL3-static"
        ])
    }

    func genToolchain(file: URL, buildContext: BuildContext) throws -> Bool {
        let contents: String
        let tripleComps = buildContext.triple.split(separator: "-")
        let arch = tripleComps[0]
        let vendor = tripleComps[1]
        let os = tripleComps[2]
        
        if vendor == "apple", os.hasPrefix("macosx") {
            let version = os[os.index(os.startIndex, offsetBy: 6)...]
            
            let sysroot: String
            if let sdkPath = buildContext.sdkPath?.path {
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
            set(CMAKE_C_COMPILER_TARGET \(buildContext.triple))
            set(CMAKE_CXX_COMPILER clang++)
            set(CMAKE_CXX_COMPILER_TARGET \(buildContext.triple))

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
            Diagnostics.error("unknown triple: \(buildContext.triple)")
            return false
        }

        try contents.write(to: file, atomically: true, encoding: .utf8)
        return true
    }

    func run2(title: String, command: [String]) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            Diagnostics.error("\(title) failed: \(process.terminationStatus)")
            return false
        } else {
            return true
        }
    }
    */
}

enum CMakeErrors: Error {
    case configureError(Int32)
}
