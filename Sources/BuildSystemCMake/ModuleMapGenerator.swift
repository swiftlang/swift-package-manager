import Foundation

public enum ModuleMapGenerator {
    public static func generate(umbrellaDir: String,
                                outFile: String,
                                topLevelModuleName: String,
                                excludes: [String] = [],
                                textualHeaders: [String] = []) throws {
        var lines: [String] = []
        lines.append("module \(topLevelModuleName) [system] {")
        lines.append("  umbrella \"\(umbrellaDir)\"")

        // Exclude headers (e.g., main headers, or headers that will be textual)
        for ex in excludes {
            lines.append("  exclude header \"\(ex)\"")
        }

        // Textual headers (included via #include, not compiled into module)
        // These are perfect for SDL's begin_code.h/close_code.h pattern
        for textual in textualHeaders {
            lines.append("  textual header \"\(textual)\"")
        }

        lines.append("  export *")
        lines.append("  module * { export * }")
        lines.append("}")
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: (outFile as NSString).deletingLastPathComponent),
                                                withIntermediateDirectories: true, attributes: nil)
        try lines.joined(separator: "\n").write(toFile: outFile, atomically: true, encoding: .utf8)
    }

    public static func copyProvided(from provided: String, to dest: String, sanityName: String?) throws {
        guard FileManager.default.fileExists(atPath: provided) else {
            throw ModuleMapError.badProvidedPath(provided)
        }
        let contents = try String(contentsOfFile: provided)
        if let expected = sanityName {
            let found = ModuleMapPolicy.parseModuleName(from: contents)
            if found != expected { throw ModuleMapError.nameMismatch(expected: expected, found: found) }
        }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: (dest as NSString).deletingLastPathComponent),
                                                withIntermediateDirectories: true, attributes: nil)
        try contents.write(toFile: dest, atomically: true, encoding: .utf8)
    }
}
