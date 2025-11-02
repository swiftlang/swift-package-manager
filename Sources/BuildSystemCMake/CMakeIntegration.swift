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
                                       topLevelModuleName: String) throws -> CMakeIntegrationResult {
        // 1) Load module map policy and CMake defines
        let cfg = ModuleMapPolicy.loadConfig(at: targetRoot)
        let defines = cfg.defines ?? [:]

        // 2) Build via CMake
        let artifacts = try CMakeBuilder().configureBuildInstall(
            sourceDir: targetRoot,
            workDir: buildDir,
            stagingDir: stagingDir,
            buildType: configuration,
            defines: defines
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
