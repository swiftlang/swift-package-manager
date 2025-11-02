import Foundation

/// Analyzes C/C++ headers to suggest module map configuration
public struct HeaderAnalyzer {

    /// Result of header analysis
    public struct Analysis {
        public var textualHeaders: [String] = []
        public var excludedHeaders: [String] = []
        public var warnings: [String] = []

        public var suggestedModuleMap: String {
            var lines: [String] = []
            lines.append("module YourModule [system] {")
            lines.append("  umbrella \"include\"")
            lines.append("")

            if !textualHeaders.isEmpty {
                lines.append("  // Textual headers (included via #include)")
                for header in textualHeaders {
                    lines.append("  textual header \"\(header)\"")
                }
                lines.append("")
            }

            if !excludedHeaders.isEmpty {
                lines.append("  // Excluded headers (require external dependencies)")
                for header in excludedHeaders {
                    lines.append("  exclude header \"\(header)\"")
                }
                lines.append("")
            }

            lines.append("  export *")
            lines.append("  module * { export * }")
            lines.append("}")

            return lines.joined(separator: "\n")
        }
    }

    /// Analyze headers in a directory
    public static func analyze(includeDir: String) -> Analysis {
        var analysis = Analysis()
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(atPath: includeDir) else {
            return analysis
        }

        for case let file as String in enumerator {
            guard file.hasSuffix(".h") || file.hasSuffix(".hpp") else { continue }

            let fullPath = (includeDir as NSString).appendingPathComponent(file)
            guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
                continue
            }

            // Detect textual header patterns
            if file.contains("begin_code") || file.contains("close_code") ||
               file.contains("_pre.h") || file.contains("_post.h") {
                analysis.textualHeaders.append(file)
                continue
            }

            // Detect headers requiring external dependencies
            let externalIncludes = [
                "<GL/", "<EGL/", "<vulkan/", "<X11/", "<windows.h>",
                "<d3d", "<metal", "<cuda"
            ]

            for pattern in externalIncludes {
                if content.contains(pattern) {
                    analysis.excludedHeaders.append(file)
                    analysis.warnings.append("Header \(file) includes \(pattern) - may require external dependency")
                    break
                }
            }

            // Detect #error directives that might indicate conditional compilation
            if content.contains("#error") && !content.contains("This header should not be included directly") {
                analysis.warnings.append("Header \(file) contains #error directive - review carefully")
            }
        }

        return analysis
    }

    /// Generate a suggested .spm-cmake.json config
    public static func suggestConfig(for analysis: Analysis, libraryName: String) -> String {
        var config: [String: Any] = [:]

        var moduleMap: [String: Any] = [
            "mode": "auto"
        ]

        if !analysis.textualHeaders.isEmpty {
            moduleMap["textualHeaders"] = analysis.textualHeaders
        }

        if !excludedHeaders.isEmpty {
            moduleMap["excludeHeaders"] = analysis.excludedHeaders
        }

        config["moduleMap"] = moduleMap

        if let jsonData = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "{}"
    }
}
