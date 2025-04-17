import Foundation

@main
struct Tool {
    static func main() async throws {
        print("warning: Whoops! Coming from the executable", to: &StdErr.shared)
        
        let path = CommandLine.arguments[2]
        print("Writing a file to \(path)")
        
        try #"""
        public struct MyGeneratedStruct {
            public static var message: String = "You got struct'd"
        }
        """#.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }
}

struct StdErr: TextOutputStream {
    static var shared: Self = .init()
    mutating func write(_ string: String) {
        string.withCString { ptr in
            _ = fputs(ptr, stderr)
        }
    }
}
