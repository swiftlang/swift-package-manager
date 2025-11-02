import Foundation

public struct CMakeArtifacts {
    public let includeDir: String
    public let libFiles: [String]
}

public enum CMakeError: Error, CustomStringConvertible {
    case cmakeNotFound
    case ninjaNotFound
    case failed(String, hint: String?)
    case configurationFailed(output: String)
    case buildFailed(output: String)

    public var description: String {
        switch self {
        case .cmakeNotFound:
            return """
            CMake not found on PATH

            Install CMake:
              macOS:   brew install cmake
              Ubuntu:  sudo apt-get install cmake
              Windows: winget install cmake

            Or run: swift package diagnose-cmake
            """
        case .ninjaNotFound:
            return """
            Ninja build system not found (optional but recommended)

            Install Ninja for faster builds:
              macOS:   brew install ninja
              Ubuntu:  sudo apt-get install ninja
              Windows: winget install ninja
            """
        case .failed(let output, let hint):
            var msg = "CMake build failed:\n\(output)"
            if let hint = hint {
                msg += "\n\nHint: \(hint)"
            }
            return msg
        case .configurationFailed(let output):
            return """
            CMake configuration failed

            This usually means:
            - Missing dependencies (check .spm-cmake.json defines)
            - Incompatible CMake version
            - Platform-specific requirements not met

            Output:
            \(output)
            """
        case .buildFailed(let output):
            return """
            CMake build failed

            Common causes:
            - Compiler errors in C/C++ code
            - Missing system libraries
            - Incorrect build flags

            Output:
            \(output)
            """
        }
    }
}

public final class CMakeBuilder {
    private func run(_ args: [String], cwd: String? = nil) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        if let cwd = cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            throw CMakeError.failed(out)
        }
    }

    private func which(_ prog: String) -> String? {
        let fm = FileManager.default
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for p in paths {
            let cand = (p as NSString).appendingPathComponent(prog)
            if fm.isExecutableFile(atPath: cand) { return cand }
        }
        return nil
    }

    public func configureBuildInstall(sourceDir: String,
                                      workDir: String,
                                      stagingDir: String,
                                      buildType: String,
                                      defines: [String:String] = [:]) throws -> CMakeArtifacts {
        guard let cmake = which("cmake") else { throw CMakeError.cmakeNotFound }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: workDir),
                                               withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: stagingDir),
                                               withIntermediateDirectories: true, attributes: nil)

        var args = [cmake, "-S", sourceDir, "-B", workDir,
                    "-DCMAKE_BUILD_TYPE=\(buildType)",
                    "-DCMAKE_INSTALL_PREFIX=\(stagingDir)",
                    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
                    "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"]

        // Prefer Ninja if present
        if which("ninja") != nil { args += ["-G", "Ninja"] }

        for (k,v) in defines {
            args += ["-D\(k)=\(v)"]
        }

        try run(args)
        try run([cmake, "--build", workDir, "--config", buildType, "--parallel"])
        try run([cmake, "--install", workDir, "--config", buildType])

        // Very small artifact discovery: gather libs from staging/lib*
        var libs: [String] = []
        let fm = FileManager.default
        let libRoots = ["lib", "lib64", "lib/Release", "lib/Debug"].map { (stagingDir as NSString).appendingPathComponent($0) }
        for root in libRoots where fm.fileExists(atPath: root) {
            if let items = try? fm.contentsOfDirectory(atPath: root) {
                for f in items where f.hasPrefix("lib") || f.hasSuffix(".dylib") || f.hasSuffix(".so") || f.hasSuffix(".a") {
                    libs.append((root as NSString).appendingPathComponent(f))
                }
            }
        }

        return CMakeArtifacts(includeDir: (stagingDir as NSString).appendingPathComponent("include"),
                              libFiles: libs)
    }
}
