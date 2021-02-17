import Foundation

extension String {
    
    public var quotedForSourceCode: String {
        return "\"" + self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }
}
