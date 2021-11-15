import Foundation

extension String {

    var quotedForSourceCode: String {
        return "\"" + self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }
}
