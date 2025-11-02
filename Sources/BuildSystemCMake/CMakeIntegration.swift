import Foundation

public struct CMakeIntegrationResult {
    public let includeDir: String
    public let libFiles: [String]
    public let extraCFlags: [String]
}

public enum CMakeIntegration {
    /// Main entry used by the BuildPlan hook.
    public static func buildAndPrepare(targetRoot: String,
                                       buildDir: String,
                                       stagingDir: String,
                                       configuration: String,
                                       topLevelModuleName: String,
                                       triple: String? = nil,
                                       platformDefines: [String: String] = [:],
                                       platformEnv: [String: String] = [:]) throws -> CMakeIntegrationResult {
        // 1) Load module map policy and CMake defines (with per-triple support)
        let cfg = ModuleMapPolicy.loadConfig(at: targetRoot, triple: triple)
        var defines = cfg.defines ?? [:]

        // 2) Merge platform defines (from Swift SDK) - user config takes precedence
        for (key, value) in platformDefines {
            if defines[key] == nil {
                defines[key] = value
            }
        }

        // 3) Merge environment variables (toolchain compilers, etc.)
        var env = ProcessInfo.processInfo.environment
        for (key, value) in platformEnv {
            env[key] = value
        }
        // User config can override toolchain
        if let userEnv = cfg.env {
            for (key, value) in userEnv {
                env[key] = value
            }
        }

        // 4) Build via CMake
        let artifacts = try CMakeBuilder().configureBuildInstall(
            sourceDir: targetRoot,
            workDir: buildDir,
            stagingDir: stagingDir,
            buildType: configuration,
            defines: defines,
            env: env
        )

        // 3) Handle module map policy
        let mmCfg = cfg.moduleMap ?? ModuleMapConfig()
        let installAt = mmCfg.installAt ?? "include/module.modulemap"
        let dest = (stagingDir as NSString).appendingPathComponent(installAt)
        var extraCFlags: [String] = []

        switch mmCfg.mode {
        case .auto:
            // assume headers staged under include/<something>; set umbrella = include dir
            let excludes = mmCfg.excludeHeaders ?? []
            let textualHeaders = mmCfg.textualHeaders ?? []
            try ModuleMapGenerator.generate(umbrellaDir: artifacts.includeDir,
                                            outFile: dest,
                                            topLevelModuleName: topLevelModuleName,
                                            excludes: excludes,
                                            textualHeaders: textualHeaders)

        case .provided:
            guard let providedRel = mmCfg.path else { break }
            let providedAbs = (targetRoot as NSString).appendingPathComponent(providedRel)
            try ModuleMapGenerator.copyProvided(from: providedAbs,
                                                to: dest,
                                                sanityName: mmCfg.sanityCheckModuleName)

        case .overlay:
            if let v = mmCfg.overlay?.vfs {
                extraCFlags += ["-Xcc", "-vfsoverlay", "-Xcc", v]
            }
            if let m = mmCfg.overlay?.moduleMapFile {
                extraCFlags += ["-Xcc", "-fmodule-map-file=\(m)"]
            }
            // no file written to staging

        case .none:
            // nothing — user is responsible for flags
            break
        }

        return CMakeIntegrationResult(includeDir: artifacts.includeDir, libFiles: artifacts.libFiles, extraCFlags: extraCFlags)
    }
}
