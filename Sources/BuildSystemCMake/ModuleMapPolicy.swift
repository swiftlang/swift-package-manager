// swift-tools-version: 6.0
import Foundation

public enum ModuleMapMode: String, Codable {
    case auto, provided, overlay, none
}

public struct ModuleMapOverlay: Codable {
    public var vfs: String?
    public var moduleMapFile: String?
    public init(vfs: String? = nil, moduleMapFile: String? = nil) {
        self.vfs = vfs; self.moduleMapFile = moduleMapFile
    }
}

public struct ModuleMapConfig: Codable {
    public var mode: ModuleMapMode = .auto
    public var path: String?            // for provided
    public var installAt: String?       // default "include/module.modulemap"
    public var overlay: ModuleMapOverlay?
    public var sanityCheckModuleName: String?
    public var textualHeaders: [String]? // headers to include textually (not compiled into module)
    public var excludeHeaders: [String]? // headers to exclude from umbrella

    public init(mode: ModuleMapMode = .auto,
                path: String? = nil,
                installAt: String? = nil,
                overlay: ModuleMapOverlay? = nil,
                sanityCheckModuleName: String? = nil,
                textualHeaders: [String]? = nil,
                excludeHeaders: [String]? = nil) {
        self.mode = mode
        self.path = path
        self.installAt = installAt
        self.overlay = overlay
        self.sanityCheckModuleName = sanityCheckModuleName
        self.textualHeaders = textualHeaders
        self.excludeHeaders = excludeHeaders
    }
}

public struct SPMCMakeConfig: Codable {
    public var defines: [String:String]? = nil
    public var env: [String:String]? = nil
    public var moduleMap: ModuleMapConfig? = nil
}

public enum ModuleMapError: Error, CustomStringConvertible {
    case badProvidedPath(String)
    case nameMismatch(expected: String, found: String?)
    public var description: String {
        switch self {
        case .badProvidedPath(let p): return "Provided module map not found: \(p)"
        case .nameMismatch(let e, let f): return "Module name mismatch. Expected \(e), found \(f ?? "<none>")"
        }
    }
}

public enum ModuleMapPolicy {
    /// Load config with per-triple fallback support
    /// 1. Try: .spm-cmake/<triple>.json
    /// 2. Fallback: .spm-cmake.json
    /// 3. Fallback: auto-detect
    public static func loadConfig(at targetRoot: String, triple: String? = nil) -> SPMCMakeConfig {
        // Try per-triple config first
        if let triple = triple {
            let tripleJsonPath = (targetRoot as NSString).appendingPathComponent(".spm-cmake/\(triple).json")
            if FileManager.default.fileExists(atPath: tripleJsonPath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: tripleJsonPath)),
               let cfg = try? JSONDecoder().decode(SPMCMakeConfig.self, from: data) {
                return cfg
            }
        }

        // Fallback to generic config
        let jsonPath = (targetRoot as NSString).appendingPathComponent(".spm-cmake.json")
        if FileManager.default.fileExists(atPath: jsonPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
           let cfg = try? JSONDecoder().decode(SPMCMakeConfig.self, from: data) {
            return cfg
        }

        // Autodetect: if a module.modulemap exists under include/, prefer provided
        let includeMM = (targetRoot as NSString).appendingPathComponent("include/module.modulemap")
        if FileManager.default.fileExists(atPath: includeMM) {
            return SPMCMakeConfig(defines: nil, env: nil,
                                  moduleMap: ModuleMapConfig(mode: .provided, path: "include/module.modulemap", installAt: "include/module.modulemap"))
        }
        let rootMM = (targetRoot as NSString).appendingPathComponent("module.modulemap")
        if FileManager.default.fileExists(atPath: rootMM) {
            return SPMCMakeConfig(defines: nil, env: nil,
                                  moduleMap: ModuleMapConfig(mode: .provided, path: "module.modulemap", installAt: "include/module.modulemap"))
        }
        return SPMCMakeConfig()
    }

    public static func parseModuleName(from moduleMapText: String) -> String? {
        // very light parser: look for "module <name>" possibly followed by attributes
        let pattern = #"module\s+([A-Za-z0-9_][A-Za-z0-9_.-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(location: 0, length: moduleMapText.utf16.count)
        if let match = regex.firstMatch(in: moduleMapText, options: [], range: range),
           match.numberOfRanges > 1 {
            let captureRange = match.range(at: 1)
            if let swiftRange = Range(captureRange, in: moduleMapText) {
                return String(moduleMapText[swiftRange])
            }
        }
        return nil
    }
}
