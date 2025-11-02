import Foundation
import Crypto

/// Manages build caching to avoid unnecessary CMake rebuilds
public struct BuildCache {
    private let cacheDir: String

    public init(cacheDir: String) {
        self.cacheDir = cacheDir
    }

    /// Compute hash of all inputs that affect the build
    public func computeInputHash(sourceDir: String, config: SPMCMakeConfig) -> String {
        var hasher = SHA256()

        // Hash CMakeLists.txt
        if let cmakeData = try? Data(contentsOf: URL(fileURLWithPath: (sourceDir as NSString).appendingPathComponent("CMakeLists.txt"))) {
            hasher.update(data: cmakeData)
        }

        // Hash .spm-cmake.json
        let configData = (try? JSONEncoder().encode(config)) ?? Data()
        hasher.update(data: configData)

        // Hash CMake version
        if let version = getCMakeVersion() {
            hasher.update(data: Data(version.utf8))
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Check if cached build is still valid
    public func isValid(for inputHash: String) -> Bool {
        let manifestPath = (cacheDir as NSString).appendingPathComponent("build-manifest.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let manifest = try? JSONDecoder().decode(BuildManifest.self, from: data) else {
            return false
        }
        return manifest.inputHash == inputHash
    }

    /// Save build manifest
    public func saveManifest(_ manifest: BuildManifest) throws {
        let manifestPath = (cacheDir as NSString).appendingPathComponent("build-manifest.json")
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: URL(fileURLWithPath: manifestPath))
    }

    private func getCMakeVersion() -> String? {
        // Try to get cmake --version
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["cmake"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

/// Manifest of a completed build
public struct BuildManifest: Codable {
    public let cmakeVersion: String
    public let buildDate: Date
    public let defines: [String: String]
    public let producedLibraries: [String]
    public let inputHash: String

    public init(cmakeVersion: String, buildDate: Date, defines: [String: String], producedLibraries: [String], inputHash: String) {
        self.cmakeVersion = cmakeVersion
        self.buildDate = buildDate
        self.defines = defines
        self.producedLibraries = producedLibraries
        self.inputHash = inputHash
    }
}
